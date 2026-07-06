"""Model definitions. Input: (batch, 1, 128, 215) log-mel windows."""

import torch
from torch import nn
from torchvision.models import ResNet18_Weights, resnet18


class ConvBlock(nn.Module):
    def __init__(self, c_in, c_out):
        super().__init__()
        self.block = nn.Sequential(
            nn.Conv2d(c_in, c_out, kernel_size=3, padding=1, bias=False),
            nn.BatchNorm2d(c_out),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(2),
        )

    def forward(self, x):
        return self.block(x)


class SmallCNN(nn.Module):
    """Baseline trained from scratch, ~0.4M parameters."""

    def __init__(self, n_classes, dropout=0.3):
        super().__init__()
        self.features = nn.Sequential(
            ConvBlock(1, 32),
            ConvBlock(32, 64),
            ConvBlock(64, 128),
            ConvBlock(128, 256),
        )
        self.head = nn.Sequential(
            nn.AdaptiveAvgPool2d(1),
            nn.Flatten(),
            nn.Dropout(dropout),
            nn.Linear(256, n_classes),
        )

    def forward(self, x):
        return self.head(self.features(x))


def build_resnet18(n_classes, pretrained=True, freeze_early=False, dropout=0.3):
    """ImageNet-pretrained ResNet18 adapted to 1-channel spectrograms.

    The first conv is rebuilt for 1 input channel; pretrained RGB kernels are
    averaged over the color dim, so their learned edge/texture filters survive.
    freeze_early keeps the generic texture filters (layer1-2) fixed and
    fine-tunes only layer3-4 and the head.
    """
    m = resnet18(weights=ResNet18_Weights.IMAGENET1K_V1 if pretrained else None)
    old_conv = m.conv1
    m.conv1 = nn.Conv2d(1, 64, kernel_size=7, stride=2, padding=3, bias=False)
    if pretrained:
        with torch.no_grad():
            m.conv1.weight.copy_(old_conv.weight.mean(dim=1, keepdim=True))
    if freeze_early:
        for part in (m.bn1, m.layer1, m.layer2):
            for p in part.parameters():
                p.requires_grad = False
    m.fc = nn.Sequential(nn.Dropout(dropout), nn.Linear(m.fc.in_features, n_classes))
    return m


def build_model(name, n_classes, **kwargs):
    if name == "small_cnn":
        return SmallCNN(n_classes)
    if name == "resnet18":
        return build_resnet18(n_classes, **kwargs)
    raise ValueError(f"unknown model: {name}")
