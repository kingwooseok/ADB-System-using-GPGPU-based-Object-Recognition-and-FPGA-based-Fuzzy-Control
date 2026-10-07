# GPU code provenance

`train_custom_yolov7.py` prepares a two-class YOLOv7 training configuration and launches training.

| Stage | Behavior |
|---|---|
| Setup | Imports, weight download helper, workspace setup |
| Configuration | Person/car classes, dataset YAML, model YAML with `nc=2` |
| Training | Pretrained YOLOv7 weights and training arguments |
| Results | Training result handling and Python entry point |

The original training defaults are preserved: `person`/`car`, 640×640 input, batch size 16, 100 epochs, four workers, GPU device 0, `yolov7_training.pt`, and `hyp.scratch.p5.yaml`.

Portfolio maintenance edits:

- Dataset, YOLOv7 checkout, output directory, model configuration, pretrained weights, and hyperparameters accept command-line options.
- Generated configurations are separate from upstream configuration files.
- Training uses `subprocess.run` with individual arguments and the active Python executable.
- Weight downloads require `--download-weights` and use a timeout and a temporary file. Python's standard library replaces the original `requests` dependency.
- `--prepare-only` writes YAML and prints the training command without downloading weights or running training.

This directory contains the training launcher. The inference and UDP transmission interfaces are described in the [system design](../docs/architecture.md) and [UDP protocol](../docs/protocol.md).

Example usage from the repository root:

```bash
python -m pip install PyYAML
python gpu/train_custom_yolov7.py \
  --yolov7-dir /path/to/yolov7 \
  --dataset /path/to/adb-dataset \
  --output-dir build/yolov7-training \
  --prepare-only
```

Run the same command without `--prepare-only` and provide a local `--weights` file to start training in the supplied YOLOv7 environment. A missing pretrained file is downloaded only when `--download-weights` is explicitly supplied.
