"""Local inference server for the macOS app.

Holds one streaming session: the app posts raw audio chunks, the server
returns the genre distribution of the current 5s window, an exponential
moving average ("recent", what is playing now) and the running mean over
the whole session.

Run from the repo root:
    uvicorn server.main:app --port 8000

Env vars:
    GENRE_CHECKPOINT  path to a training checkpoint
                      (default data/runs/baseline_aug/best.pt)
    GENRE_DEVICE      torch device for inference (default cpu)
"""

import logging
import os
import sys
import time
from pathlib import Path

import numpy as np
from fastapi import FastAPI, HTTPException, Query, Request

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "ml" / "src"))

from infer import (  # noqa: E402
    SlidingWindowClassifier,
    image_to_logmel,
    logmel_distribution,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("genre")
# per-request access lines are noise next to per-window logs
logging.getLogger("uvicorn.access").setLevel(logging.WARNING)

CHECKPOINT = Path(os.environ.get(
    "GENRE_CHECKPOINT", REPO_ROOT / "data" / "runs" / "baseline_aug" / "best.pt"))
DEVICE = os.environ.get("GENRE_DEVICE", "cpu")
HOP_S = 1.0

app = FastAPI(title="audio-genre-analyzer")

t0 = time.perf_counter()
clf = SlidingWindowClassifier(CHECKPOINT, hop_s=HOP_S, device=DEVICE)
# warm up mel + model so the first real request does not pay cold-start latency
clf.add_audio(np.zeros(22050 * 5, dtype=np.float32), 22050)
clf.reset()
logger.info("model loaded: %s on %s, %d classes, ready in %.1fs",
            CHECKPOINT.name, DEVICE, len(clf.classes), time.perf_counter() - t0)


def distribution(probs):
    return {genre: round(float(p), 4)
            for genre, p in zip(clf.classes, probs)}


def top1(probs):
    i = int(np.argmax(probs))
    return f"{clf.classes[i]} {probs[i] * 100:.0f}%"


@app.get("/status")
def status():
    return {
        "checkpoint": str(CHECKPOINT),
        "device": DEVICE,
        "classes": clf.classes,
        "windows_seen": clf.n_windows,
        "buffered_seconds": round(len(clf.buffer) / 22050, 2),
    }


@app.post("/reset")
def reset():
    if clf.n_windows > 0:
        logger.info("reset: session had %d windows, verdict was %s",
                    clf.n_windows, top1(clf.session_probs))
    clf.reset()
    return {"ok": True}


@app.post("/image")
async def image(request: Request):
    """Body: a rendered spectrogram image (png/jpg/webp).

    Reconstructs an approximate log-mel array from pixel brightness and runs
    the same windowed classification as for audio. Works best on plain
    spectrogram images without axes or colorbars.
    """
    body = await request.body()
    try:
        logmel = image_to_logmel(body)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"cannot read image: {e}")

    probs, n_windows = logmel_distribution(clf.model, logmel, clf.normalize, DEVICE)
    logger.info("image analyzed: %d frames, %d windows -> %s",
                logmel.shape[1], n_windows, top1(probs))
    return {
        "distribution": distribution(probs),
        "windows": n_windows,
        "frames": int(logmel.shape[1]),
    }


@app.post("/audio")
async def audio(request: Request, sr: int = Query(..., gt=0)):
    """Body: raw mono float32 little-endian PCM at the given sample rate.

    Returns the window distribution for the last completed hop (null if the
    chunk did not complete a new window yet), the recent EMA and the session
    running mean.
    """
    body = await request.body()
    samples = np.frombuffer(body, dtype=np.float32)
    t0 = time.perf_counter()
    emissions = clf.add_audio(samples, sr)
    elapsed_ms = (time.perf_counter() - t0) * 1000

    for i, e in enumerate(emissions):
        logger.info("window %d: %s | recent %s | session %s (%.0fms)",
                    clf.n_windows - len(emissions) + i + 1,
                    top1(e["window"]), top1(e["recent"]),
                    top1(e["session"]), elapsed_ms)

    last = emissions[-1] if emissions else None
    return {
        "new_windows": len(emissions),
        "window": distribution(last["window"]) if last else None,
        "recent": distribution(clf.recent_probs),
        "session": distribution(clf.session_probs),
        "windows_seen": clf.n_windows,
    }
