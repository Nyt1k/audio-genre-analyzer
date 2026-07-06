"""Train the baseline CNN on 5s spectrogram windows.

Usage:
    python train.py --spec-dir ../../data/spectrograms --out-dir ../../data/runs/baseline

Selects the best checkpoint by window-level macro F1 on validation.
Track-level aggregation is evaluated separately (evaluate.py, later).
"""

import argparse
import time
from pathlib import Path

import numpy as np
import pandas as pd
import torch
from sklearn.metrics import f1_score
from torch import nn
from torch.utils.data import DataLoader
from torch.utils.tensorboard import SummaryWriter

from dataset import SpectrogramWindows, class_weights
from models import build_model

SEED = 42


def evaluate(model, loader, criterion, device):
    model.eval()
    losses, preds, targets = [], [], []
    with torch.no_grad():
        for x, y in loader:
            x, y = x.to(device), y.to(device)
            logits = model(x)
            losses.append(criterion(logits, y).item())
            preds.append(logits.argmax(1).cpu())
            targets.append(y.cpu())
    preds = torch.cat(preds).numpy()
    targets = torch.cat(targets).numpy()
    acc = (preds == targets).mean()
    f1 = f1_score(targets, preds, average="macro")
    return float(np.mean(losses)), acc, f1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec-dir", type=Path, default=Path("../../data/spectrograms"))
    parser.add_argument("--out-dir", type=Path, default=Path("../../data/runs/baseline"))
    parser.add_argument("--model", default="small_cnn", choices=["small_cnn", "resnet18"])
    parser.add_argument("--epochs", type=int, default=15)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--lr", type=float, default=3e-4)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--normalize", default="global", choices=["global", "per_window"])
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--augment", action="store_true",
                        help="SpecAugment masking on train windows")
    parser.add_argument("--freeze-early", action="store_true",
                        help="resnet18 only: freeze layer1-2")
    parser.add_argument("--mixup", type=float, default=0.0,
                        help="mixup Beta(a, a); 0 disables, typical 0.2-0.4")
    parser.add_argument("--label-smoothing", type=float, default=0.0)
    args = parser.parse_args()

    torch.manual_seed(SEED)
    np.random.seed(SEED)
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    args.out_dir.mkdir(parents=True, exist_ok=True)

    train_ds = SpectrogramWindows(args.spec_dir, "training", normalize=args.normalize,
                                  augment=args.augment)
    val_ds = SpectrogramWindows(args.spec_dir, "validation", normalize=args.normalize)
    print(f"device={device} train={len(train_ds)} val={len(val_ds)} "
          f"classes={len(train_ds.classes)} normalize={args.normalize} "
          f"augment={args.augment}")

    train_loader = DataLoader(train_ds, batch_size=args.batch_size, shuffle=True,
                              num_workers=args.workers, persistent_workers=args.workers > 0)
    val_loader = DataLoader(val_ds, batch_size=128,
                            num_workers=args.workers, persistent_workers=args.workers > 0)

    kwargs = {"freeze_early": args.freeze_early} if args.model == "resnet18" else {}
    model = build_model(args.model, n_classes=len(train_ds.classes), **kwargs).to(device)
    n_params = sum(p.numel() for p in model.parameters())
    n_train = sum(p.numel() for p in model.parameters() if p.requires_grad)
    print(f"model={args.model} params={n_params/1e6:.2f}M trainable={n_train/1e6:.2f}M")
    writer = SummaryWriter(args.out_dir / "tb")

    criterion = nn.CrossEntropyLoss(weight=class_weights(train_ds).to(device),
                                    label_smoothing=args.label_smoothing)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr,
                                  weight_decay=args.weight_decay)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)

    history = []
    best_f1 = 0.0
    for epoch in range(1, args.epochs + 1):
        model.train()
        t0 = time.time()
        losses = []
        for step, (x, y) in enumerate(train_loader):
            x, y = x.to(device), y.to(device)
            optimizer.zero_grad()
            if args.mixup > 0:
                # mixed inputs, loss split between both label sets
                lam = float(np.random.beta(args.mixup, args.mixup))
                perm = torch.randperm(x.size(0), device=device)
                logits = model(lam * x + (1 - lam) * x[perm])
                loss = lam * criterion(logits, y) + (1 - lam) * criterion(logits, y[perm])
            else:
                loss = criterion(model(x), y)
            loss.backward()
            optimizer.step()
            losses.append(loss.item())
            if (step + 1) % 100 == 0:
                writer.add_scalar("loss/train_step", np.mean(losses[-100:]),
                                  (epoch - 1) * len(train_loader) + step + 1)
            if (step + 1) % 500 == 0:
                print(f"  epoch {epoch} step {step + 1}/{len(train_loader)} "
                      f"loss={np.mean(losses[-500:]):.4f}", flush=True)
        scheduler.step()

        train_loss = float(np.mean(losses))
        val_loss, val_acc, val_f1 = evaluate(model, val_loader, criterion, device)
        history.append({"epoch": epoch, "train_loss": train_loss, "val_loss": val_loss,
                        "val_acc": val_acc, "val_f1": val_f1})
        pd.DataFrame(history).to_csv(args.out_dir / "history.csv", index=False)
        for key, value in history[-1].items():
            if key != "epoch":
                writer.add_scalar(f"epoch/{key}", value, epoch)
        writer.add_scalar("epoch/lr", scheduler.get_last_lr()[0], epoch)
        writer.flush()

        marker = ""
        if val_f1 > best_f1:
            best_f1 = val_f1
            torch.save({"model": model.state_dict(), "model_name": args.model,
                        "classes": train_ds.classes, "normalize": args.normalize,
                        "epoch": epoch, "val_f1": val_f1},
                       args.out_dir / "best.pt")
            marker = " *best"
        print(f"epoch {epoch}/{args.epochs} train_loss={train_loss:.4f} "
              f"val_loss={val_loss:.4f} val_acc={val_acc:.4f} val_f1={val_f1:.4f} "
              f"({time.time() - t0:.0f}s){marker}", flush=True)

    print(f"done, best val_f1={best_f1:.4f}, checkpoints in {args.out_dir}")


if __name__ == "__main__":
    main()
