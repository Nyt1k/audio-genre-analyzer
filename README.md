# Audio Genre Analyzer

Live music genre classification on macOS: the app listens to system audio and shows a
real-time probability distribution over music genres, plus an aggregated verdict for the
whole track. Capstone project for the Advanced Deep Learning for AI Applications course
(MSc Computer Science).

## Architecture

The project has three parts:

- `ml/` - model training. Audio -> log-mel spectrograms -> CNN classifier. Two models are
  compared: a small CNN trained from scratch and a transfer-learning model (ResNet18 on
  spectrograms treated as images). Python scripts live in `ml/src`, analysis and results
  notebooks in `ml/notebooks`.
- `server/` (planned) - local FastAPI inference server. Accepts audio chunks, keeps a
  sliding window, returns the genre distribution for the current window plus a running
  mean over the whole session.
- `app/` (planned) - Flutter macOS app. Captures system audio via ScreenCaptureKit
  (Swift platform channel), shows a waveform timeline, live genre percentages, and the
  aggregated result.

## ML pipeline

- Dataset: [FMA](https://github.com/mdeff/fma) `medium` subset - 25 000 30-second track
  excerpts, 16 top-level genres.
- Class selection: Easy Listening (21 tracks) and Blues (74) are dropped as too small;
  Rock (7103) and Electronic (6314) are randomly capped to 3000 tracks each (seed=42).
  Result: 14 classes, 17 488 tracks.
- Train/validation/test split: the official artist-aware split from FMA metadata
  (no artist leakage between sets). Splitting is always by track, never by window.
- Features: log-mel spectrograms - 22 050 Hz mono, 128 mel bins, FFT 2048, hop 512,
  power converted to dB. One spectrogram is stored per full 30 s track (float16 `.npy`);
  slicing into 5 s training windows happens on the fly in the Dataset.
- Class imbalance (3000 vs ~120 tracks) is handled at training time with class weights /
  weighted sampling, not by discarding data.

## Results

The final model is the small CNN (0.39M parameters) trained with SpecAugment. On the
held-out test set (1794 tracks, evaluated once): track-level accuracy 59.4%, macro-F1
0.534, top-3 accuracy 83.8%. All ResNet18 transfer-learning variants performed worse
than the from-scratch CNN; the full experiment log with plots and conclusions is in
`ml/notebooks/resnet_results.ipynb`, final test evaluation in
`ml/notebooks/final_evaluation.ipynb`.

## Reproducing

Requirements: Python 3.13+, ffmpeg (`brew install ffmpeg`).

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# metadata (~342 MB) - also done automatically by ml/notebooks/data_analyze.ipynb
curl -o data/fma_metadata.zip https://os.unil.cloud.switch.ch/fma/fma_metadata.zip
tar -xf data/fma_metadata.zip -C data

# audio (~23 GB)
curl -o data/fma_medium.zip https://os.unil.cloud.switch.ch/fma/fma_medium.zip
tar -xf data/fma_medium.zip -C data

# mp3 -> log-mel spectrograms (~5.4 GB, a few minutes on 8 cores)
python ml/src/preprocess.py --fma-dir data/fma_medium --metadata-dir data/fma_metadata \
    --out-dir data/spectrograms --workers 8
```

Note: use `tar` (bsdtar) rather than macOS `unzip` - the FMA archives are zip64 and
`unzip` fails on them. A few FMA mp3s are known to be corrupt; they are skipped and
listed in `data/spectrograms/failed.csv`.

Everything under `data/` (audio, metadata, spectrograms, checkpoints) stays local and is
not part of the repository. The preprocessing is deterministic (fixed seed, official
split), so the resulting dataset is reproducible exactly.

Notebooks (`ml/notebooks/`): `data_analyze.ipynb` - metadata EDA and class decisions;
`spectrogram_analyze.ipynb` - a look at the preprocessed spectrograms;
`baseline_results.ipynb` - baseline CNN results; `resnet_results.ipynb` - the transfer
learning experiment log; `final_evaluation.ipynb` - one-time test evaluation of the
chosen model.

## Training setup and tools

Everything was trained locally on a MacBook Pro (Apple M3 Pro, 18 GB RAM) using the MPS
backend of PyTorch - no cloud GPUs. Rough timings: full dataset preprocessing ~3 minutes
with 8 workers; one SmallCNN epoch ~5 minutes; one ResNet18 epoch ~7 minutes; the whole
experiment series is about 10 GPU-hours.

Training runs are launched with `ml/src/train.py` (run from `ml/src`):

```bash
# baseline SmallCNN
python train.py --out-dir ../../data/runs/baseline

# final model: SmallCNN + SpecAugment, longer schedule
python train.py --augment --epochs 25 --out-dir ../../data/runs/baseline_aug

# ResNet18 transfer learning variants
python train.py --model resnet18 --lr 1e-4 --epochs 12 \
    --out-dir ../../data/runs/resnet18_vanilla
python train.py --model resnet18 --lr 1e-4 --epochs 12 --augment --freeze-early \
    --out-dir ../../data/runs/resnet18_aug
python train.py --model resnet18 --lr 1e-4 --epochs 12 --augment --freeze-early \
    --mixup 0.3 --label-smoothing 0.1 --out-dir ../../data/runs/resnet18_mixup
```

Each run writes `history.csv`, the best checkpoint (`best.pt`, selected by validation
macro-F1) and TensorBoard logs into its own folder under `data/runs/`. Live monitoring
of all runs at once:

```bash
tensorboard --logdir data/runs
```

![TensorBoard: all training runs](docs/img/tensorboard.png)

## Dataset license and attribution

This project uses the FMA dataset for non-commercial, educational research:

> Michaël Defferrard, Kirell Benzi, Pierre Vandergheynst, Xavier Bresson.
> *FMA: A Dataset For Music Analysis.* 18th International Society for Music Information
> Retrieval Conference (ISMIR), 2017. https://arxiv.org/abs/1612.01840

- The audio comes from the [Free Music Archive](https://freemusicarchive.org/); each
  track is distributed under its own Creative Commons license (per-track license info is
  in the FMA metadata).
- The FMA metadata is released under CC BY 4.0.
- No audio or metadata is redistributed in this repository - the scripts above download
  everything from the official FMA mirrors.
