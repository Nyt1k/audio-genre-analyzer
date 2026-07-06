"""Preprocess fma_medium: mp3 -> log-mel spectrograms (.npy) + index.csv.

Stores one spectrogram per full 30s track; slicing into windows happens
later in the Dataset. The script is resumable — already computed files
are skipped on rerun.

Usage:
    python preprocess.py --fma-dir data/fma_medium \
        --metadata-dir data/fma_metadata --out-dir data/spectrograms

Requires ffmpeg (brew install ffmpeg).
"""

import argparse
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import librosa
import numpy as np
import pandas as pd
from tqdm import tqdm

SR = 22050
N_MELS = 128
N_FFT = 2048
HOP_LENGTH = 512

SEED = 42
DROP_GENRES = ["Easy Listening", "Blues"]
CAP_GENRES = {"Rock": 3000, "Electronic": 3000}


def build_track_index(metadata_dir: Path) -> pd.DataFrame:
    """Read FMA metadata, filter classes, return track_id/genre/split."""
    tracks = pd.read_csv(metadata_dir / "tracks.csv", index_col=0, header=[0, 1])
    medium = tracks[tracks[("set", "subset")].isin(["small", "medium"])]

    df = pd.DataFrame({
        "genre": medium[("track", "genre_top")],
        "split": medium[("set", "split")],
    })
    df = df[~df["genre"].isin(DROP_GENRES)]

    # Cap oversized classes, deterministic via seed
    rng = np.random.RandomState(SEED)
    keep_parts = []
    for genre, group in df.groupby("genre"):
        cap = CAP_GENRES.get(genre)
        if cap is not None and len(group) > cap:
            group = group.loc[rng.choice(group.index, cap, replace=False)]
        keep_parts.append(group)
    df = pd.concat(keep_parts).sort_index()
    df.index.name = "track_id"
    return df


def track_audio_path(fma_dir: Path, track_id: int) -> Path:
    # FMA shards mp3s into folders by the first three digits of id: 000/000002.mp3
    tid = f"{track_id:06d}"
    return fma_dir / tid[:3] / f"{tid}.mp3"


def process_track(args) -> tuple:
    """One track -> log-mel float16 .npy. Returns (track_id, n_frames|None, err|None)."""
    track_id, mp3_path, out_path = args
    try:
        y, _ = librosa.load(mp3_path, sr=SR, mono=True)
        mel = librosa.feature.melspectrogram(
            y=y, sr=SR, n_mels=N_MELS, n_fft=N_FFT, hop_length=HOP_LENGTH
        )
        logmel = librosa.power_to_db(mel, ref=np.max).astype(np.float16)
        np.save(out_path, logmel)
        return track_id, logmel.shape[1], None
    except Exception as e:
        return track_id, None, str(e)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fma-dir", type=Path, required=True)
    parser.add_argument("--metadata-dir", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=8)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    index = build_track_index(args.metadata_dir)
    print(f"Tracks after filtering: {len(index)}")
    print(index["genre"].value_counts())

    jobs = []
    for track_id in index.index:
        out_path = args.out_dir / f"{track_id:06d}.npy"
        if out_path.exists():
            continue
        mp3_path = track_audio_path(args.fma_dir, track_id)
        if not mp3_path.exists():
            continue
        jobs.append((track_id, mp3_path, out_path))
    print(f"To process: {len(jobs)} (the rest already done or mp3 missing)")

    failed = []
    n_frames = {}
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(process_track, job) for job in jobs]
        for fut in tqdm(as_completed(futures), total=len(futures)):
            track_id, frames, err = fut.result()
            if err is None:
                n_frames[track_id] = frames
            else:
                failed.append((track_id, err))

    # index.csv only lists tracks that actually have a spectrogram on disk
    have = {int(p.stem) for p in args.out_dir.glob("*.npy")}
    final = index[index.index.isin(have)].copy()
    final.to_csv(args.out_dir / "index.csv")
    print(f"Done. Spectrograms: {len(final)}, errors: {len(failed)}")
    if failed:
        pd.DataFrame(failed, columns=["track_id", "error"]).to_csv(
            args.out_dir / "failed.csv", index=False
        )
        print("Errors listed in failed.csv (FMA has a few known corrupt mp3s)")


if __name__ == "__main__":
    main()
