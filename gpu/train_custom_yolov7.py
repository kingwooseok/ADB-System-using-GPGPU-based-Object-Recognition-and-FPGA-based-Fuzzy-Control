#!/usr/bin/env python3
"""Prepare and train the ADB person/car model with an existing YOLOv7 checkout.

Recovered from the project report, appendix 6.a, pages 84-87.
Paths and training parameters are command-line options; the original defaults
are retained for classes, image size, epochs, batch size, and model weights.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import shlex
import subprocess
import sys
from urllib.request import urlopen

import yaml


WEIGHTS_URL = (
    "https://github.com/WongKinYiu/yolov7/releases/download/v0.1/"
    "yolov7_training.pt"
)
CLASS_NAMES = ["person", "car"]


def positive_int(value: str) -> int:
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return number


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yolov7-dir", type=Path, required=True,
                        help="YOLOv7 checkout containing train.py")
    parser.add_argument("--dataset", type=Path, required=True,
                        help="Dataset root containing images/train and images/val")
    parser.add_argument("--output-dir", type=Path,
                        default=Path("build/yolov7-training"),
                        help="Generated YAML files and training runs")
    parser.add_argument("--base-config", type=Path,
                        help="Default: <yolov7-dir>/cfg/training/yolov7.yaml")
    parser.add_argument("--hyp", type=Path,
                        help="Default: <yolov7-dir>/data/hyp.scratch.p5.yaml")
    parser.add_argument("--weights", type=Path,
                        help="Default: <yolov7-dir>/yolov7_training.pt")
    parser.add_argument("--weights-url", default=WEIGHTS_URL,
                        help="Download source used with --download-weights")
    parser.add_argument("--download-weights", action="store_true",
                        help="Download pretrained weights if the configured local file is absent")
    parser.add_argument("--epochs", type=positive_int, default=100)
    parser.add_argument("--batch-size", type=positive_int, default=16)
    parser.add_argument("--img-size", type=positive_int, default=640)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--device", default="0")
    parser.add_argument("--name", default="custom_yolov7_result")
    parser.add_argument("--prepare-only", action="store_true",
                        help="Write configuration and print the command without downloading or training")
    args = parser.parse_args()
    if args.workers < 0:
        parser.error("--workers must be non-negative")
    return args


def download_weights(url: str, destination: Path) -> None:
    """Stream into a temporary file so failed downloads do not become weights."""
    if destination.is_file():
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_name(destination.name + ".part")
    print(f"Downloading weights to {destination}")
    try:
        with urlopen(url, timeout=60) as response, partial.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
        if partial.stat().st_size == 0:
            raise RuntimeError("The downloaded weights file is empty")
        partial.replace(destination)
    except Exception:
        partial.unlink(missing_ok=True)
        raise


def write_yaml(path: Path, contents: dict) -> None:
    with path.open("w", encoding="utf-8") as stream:
        yaml.safe_dump(contents, stream, sort_keys=False, allow_unicode=True)


def main() -> int:
    args = parse_args()
    yolov7_dir = args.yolov7_dir.resolve()
    dataset = args.dataset.resolve()
    output_dir = args.output_dir.resolve()
    base_config = (args.base_config or yolov7_dir / "cfg/training/yolov7.yaml").resolve()
    hyp = (args.hyp or yolov7_dir / "data/hyp.scratch.p5.yaml").resolve()
    weights = (args.weights or yolov7_dir / "yolov7_training.pt").resolve()

    for path in (yolov7_dir / "train.py", base_config, hyp):
        if not path.is_file():
            raise FileNotFoundError(path)
    for split in ("train", "val"):
        split_path = dataset / "images" / split
        if not split_path.is_dir():
            raise FileNotFoundError(f"Dataset split not found: {split_path}")

    # Keep the upstream model configuration intact and write a two-class copy.
    with base_config.open(encoding="utf-8") as stream:
        model_config = yaml.safe_load(stream)
    if not isinstance(model_config, dict):
        raise ValueError(f"Expected a YAML mapping in {base_config}")
    model_config["nc"] = len(CLASS_NAMES)

    data_config = {
        "train": (dataset / "images/train").as_posix(),
        "val": (dataset / "images/val").as_posix(),
        "nc": len(CLASS_NAMES),
        "names": CLASS_NAMES,
    }
    if (dataset / "images/test").is_dir():
        data_config["test"] = (dataset / "images/test").as_posix()

    output_dir.mkdir(parents=True, exist_ok=True)
    data_path = output_dir / "data.yaml"
    custom_config = output_dir / "custom_yolov7.yaml"
    write_yaml(data_path, data_config)
    write_yaml(custom_config, model_config)

    # Argument lists preserve spaces in paths and use this Python environment.
    command = [
        sys.executable, "train.py",
        "--workers", str(args.workers),
        "--device", args.device,
        "--batch-size", str(args.batch_size),
        "--data", str(data_path),
        "--img", str(args.img_size), str(args.img_size),
        "--cfg", str(custom_config),
        "--weights", str(weights),
        "--name", args.name,
        "--hyp", str(hyp),
        "--epochs", str(args.epochs),
        "--project", str(output_dir / "runs"),
    ]
    print(f"Working directory: {yolov7_dir}")
    print(shlex.join(command))
    if args.prepare_only:
        return 0

    if args.download_weights:
        download_weights(args.weights_url, weights)
    elif not weights.is_file():
        raise FileNotFoundError(
            f"Pretrained weights not found: {weights}. "
            "Provide --weights or request --download-weights."
        )
    subprocess.run(command, cwd=yolov7_dir, check=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Training setup failed: {error}", file=sys.stderr)
        raise SystemExit(1)
