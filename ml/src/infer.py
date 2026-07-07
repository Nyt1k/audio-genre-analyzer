"""Sliding-window genre inference over an audio stream.

The server feeds arbitrary-sized chunks of audio into SlidingWindowClassifier;
every hop (default 1s) it emits the genre distribution of the last 5s window
plus a running mean over the whole session.

CLI for a quick check on a file:
    python infer.py ../../data/runs/baseline/best.pt some_track.mp3
"""

import argparse
from collections import deque
from pathlib import Path

import librosa
import numpy as np
import torch

from dataset import DB_MIN, WINDOW_FRAMES
from models import build_model
from preprocess import HOP_LENGTH, N_FFT, N_MELS, SR

WINDOW_SAMPLES = WINDOW_FRAMES * HOP_LENGTH  # 5s of audio at SR

# EMA weight of the newest window in the 'recent' aggregate; with 1s hops
# the effective memory is ~1/alpha = 7s of audio
RECENT_ALPHA = 0.15

# the session mean covers at most this many windows (~5 min at 1s hops);
# without a cap an endless gapless stream freezes the verdict, because a new
# window only weighs 1/n
SESSION_MAX_WINDOWS = 300


def load_checkpoint(path, device="cpu"):
    ckpt = torch.load(path, map_location=device, weights_only=False)
    model = build_model(ckpt.get("model_name", "small_cnn"), len(ckpt["classes"]))
    model.load_state_dict(ckpt["model"])
    model.eval()
    return model.to(device), ckpt["classes"], ckpt["normalize"]


def window_to_input(samples, normalize):
    """5s of audio at SR -> model input (1, 1, N_MELS, WINDOW_FRAMES)."""
    mel = librosa.feature.melspectrogram(
        y=samples, sr=SR, n_mels=N_MELS, n_fft=N_FFT, hop_length=HOP_LENGTH
    )
    # ref=max like in preprocess.py; there it was the whole-track max,
    # here the window max -- in practice the model is robust to this shift
    logmel = librosa.power_to_db(mel, ref=np.max)[:, :WINDOW_FRAMES]
    if normalize == "global":
        logmel = (logmel - DB_MIN) / -DB_MIN
    else:
        logmel = (logmel - logmel.mean()) / (logmel.std() + 1e-6)
    return torch.from_numpy(logmel.astype(np.float32)).unsqueeze(0).unsqueeze(0)


class SlidingWindowClassifier:
    """Stateful stream classifier: feed chunks, get per-hop distributions."""

    def __init__(self, checkpoint_path, hop_s=1.0, device="cpu"):
        self.device = torch.device(device)
        self.model, self.classes, self.normalize = load_checkpoint(
            checkpoint_path, self.device)
        self.hop_samples = int(hop_s * SR)
        self.reset()

    def reset(self):
        self.buffer = np.zeros(0, dtype=np.float32)
        self.window_probs = deque(maxlen=SESSION_MAX_WINDOWS)
        self.n_windows = 0
        # EMA over windows: follows what is playing right now, unlike the
        # session mean which weighs its whole history equally
        self.recent_probs = np.full(len(self.classes), 1 / len(self.classes))

    @property
    def session_probs(self):
        """Mean distribution over the session (capped at SESSION_MAX_WINDOWS)."""
        if not self.window_probs:
            return np.full(len(self.classes), 1 / len(self.classes))
        return np.mean(self.window_probs, axis=0)

    def _predict(self, samples):
        x = window_to_input(samples, self.normalize).to(self.device)
        with torch.no_grad():
            return torch.softmax(self.model(x), dim=1)[0].cpu().numpy()

    def add_audio(self, samples, sr):
        """Append a chunk (any length, any sr, mono float). Returns a list of
        {'window': probs, 'session': probs} — one entry per completed hop."""
        samples = np.asarray(samples, dtype=np.float32)
        if sr != SR:
            samples = librosa.resample(samples, orig_sr=sr, target_sr=SR)
        self.buffer = np.concatenate([self.buffer, samples])

        results = []
        # first window fires as soon as 5s accumulate, then every hop
        while len(self.buffer) >= WINDOW_SAMPLES:
            window = self.buffer[:WINDOW_SAMPLES]
            probs = self._predict(window)
            self.window_probs.append(probs)
            if self.n_windows == 0:
                self.recent_probs = probs.copy()
            else:
                self.recent_probs = ((1 - RECENT_ALPHA) * self.recent_probs
                                     + RECENT_ALPHA * probs)
            self.n_windows += 1
            results.append({"window": probs, "session": self.session_probs.copy(),
                            "recent": self.recent_probs.copy()})
            self.buffer = self.buffer[self.hop_samples:]
        return results


def image_to_logmel(image_bytes):
    """Rendered spectrogram image -> approximate log-mel array in dB.

    Assumes a plain spectrogram image: low frequencies at the bottom,
    brightness monotonic in level (true for viridis/magma colormaps whose
    luminance tracks the value). Grayscale luminance maps linearly onto
    [-80, 0] dB; one pixel column = one frame.
    """
    from io import BytesIO

    from PIL import Image

    img = Image.open(BytesIO(image_bytes)).convert("L")
    width = max(img.width, WINDOW_FRAMES)
    img = img.resize((width, N_MELS), Image.BILINEAR)
    arr = np.asarray(img, dtype=np.float32) / 255.0
    arr = np.flipud(arr)  # image row 0 is the top = highest frequency
    return arr * -DB_MIN + DB_MIN


def logmel_distribution(model, logmel, normalize, device="cpu"):
    """Mean prediction over 5s windows of a full log-mel array.

    Returns (probs, n_windows)."""
    device = torch.device(device)
    hop = WINDOW_FRAMES // 2
    starts = range(0, max(logmel.shape[1] - WINDOW_FRAMES, 0) + 1, hop)
    probs = []
    for start in starts:
        window = logmel[:, start:start + WINDOW_FRAMES]
        if window.shape[1] < WINDOW_FRAMES:
            break
        if normalize == "global":
            x = (window - DB_MIN) / -DB_MIN
        else:
            x = (window - window.mean()) / (window.std() + 1e-6)
        t = (torch.from_numpy(np.ascontiguousarray(x, dtype=np.float32))
             .unsqueeze(0).unsqueeze(0).to(device))
        with torch.no_grad():
            probs.append(torch.softmax(model(t), dim=1)[0].cpu().numpy())
    return np.mean(probs, axis=0), len(probs)


def classify_file(checkpoint_path, audio_path, hop_s=2.5, device="cpu"):
    """Whole-file distribution: mean of window probs, like track-level eval."""
    clf = SlidingWindowClassifier(checkpoint_path, hop_s=hop_s, device=device)
    y, sr = librosa.load(audio_path, sr=SR, mono=True)
    clf.add_audio(y, sr)
    return clf.session_probs, clf.classes


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("audio", type=Path)
    parser.add_argument("--top", type=int, default=5)
    args = parser.parse_args()

    probs, classes = classify_file(args.checkpoint, args.audio)
    order = np.argsort(probs)[::-1]
    for i in order[:args.top]:
        print(f"{classes[i]:20} {probs[i]*100:5.1f}%")


if __name__ == "__main__":
    main()
