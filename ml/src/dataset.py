"""Dataset of 5s windows sliced on the fly from full-track log-mel spectrograms.

Spectrograms are stored one per 30s track (see preprocess.py); each dataset
item is a window cut from a fixed grid. The split is always by track, so
windows of one track never end up in different splits.
"""

from pathlib import Path

import numpy as np
import pandas as pd
import torch
from torch.utils.data import Dataset

from preprocess import SR, HOP_LENGTH

WINDOW_S = 5.0
TRAIN_HOP_S = 2.5

WINDOW_FRAMES = int(WINDOW_S * SR / HOP_LENGTH)
TRAIN_HOP_FRAMES = int(TRAIN_HOP_S * SR / HOP_LENGTH)

# power_to_db with ref=max and top_db=80 gives values in [-80, 0]
DB_MIN = -80.0


class SpectrogramWindows(Dataset):
    """Windows from all tracks of one split.

    normalize:
        'global'     -- map [-80, 0] dB to [0, 1], keeps loudness differences
        'per_window' -- standardize each window (mean 0, std 1), drops loudness
    augment:
        SpecAugment-style masking (train only): random frequency and time
        stripes zeroed out, so the model cannot memorize exact windows
    """

    N_MASKS = 2
    MAX_FREQ_MASK = 16
    MAX_TIME_MASK = 30

    def __init__(self, spec_dir, split, hop_frames=TRAIN_HOP_FRAMES,
                 normalize="global", augment=False):
        assert normalize in ("global", "per_window")
        self.spec_dir = Path(spec_dir)
        self.normalize = normalize
        self.augment = augment

        index = pd.read_csv(self.spec_dir / "index.csv", index_col=0)
        # label mapping is built from the full index so it is identical for all splits
        self.classes = sorted(index["genre"].unique())
        self.class_to_idx = {g: i for i, g in enumerate(self.classes)}

        part = index[index["split"] == split]
        self.track_ids = part.index.to_numpy()
        self.track_labels = part["genre"].map(self.class_to_idx).to_numpy()

        # window grid: (track position, start frame) for every window
        self.items = []
        for pos, track_id in enumerate(self.track_ids):
            n_frames = self._track_shape(track_id)[1]
            starts = range(0, n_frames - WINDOW_FRAMES + 1, hop_frames)
            self.items.extend((pos, s) for s in starts)

    def _track_path(self, track_id):
        return self.spec_dir / f"{track_id:06d}.npy"

    def _track_shape(self, track_id):
        # reads only the npy header, not the data
        return np.load(self._track_path(track_id), mmap_mode="r").shape

    def __len__(self):
        return len(self.items)

    def __getitem__(self, i):
        pos, start = self.items[i]
        spec = np.load(self._track_path(self.track_ids[pos]), mmap_mode="r")
        window = np.asarray(spec[:, start:start + WINDOW_FRAMES], dtype=np.float32)

        if self.normalize == "global":
            window = (window - DB_MIN) / -DB_MIN
        else:
            window = (window - window.mean()) / (window.std() + 1e-6)

        if self.augment:
            # masked value 0 = silence for 'global', mean for 'per_window'
            for _ in range(self.N_MASKS):
                f = np.random.randint(0, self.MAX_FREQ_MASK + 1)
                f0 = np.random.randint(0, window.shape[0] - f + 1)
                window[f0:f0 + f, :] = 0.0
                t = np.random.randint(0, self.MAX_TIME_MASK + 1)
                t0 = np.random.randint(0, window.shape[1] - t + 1)
                window[:, t0:t0 + t] = 0.0

        x = torch.from_numpy(window).unsqueeze(0)  # (1, n_mels, WINDOW_FRAMES)
        y = int(self.track_labels[pos])
        return x, y

    def window_labels(self):
        """Label of every window, aligned with __getitem__ order."""
        return np.array([self.track_labels[pos] for pos, _ in self.items])


def class_weights(dataset):
    """Inverse-frequency weights over windows, normalized to mean 1. For the loss."""
    counts = np.bincount(dataset.window_labels(), minlength=len(dataset.classes))
    weights = len(dataset) / (len(dataset.classes) * counts)
    return torch.tensor(weights, dtype=torch.float32)
