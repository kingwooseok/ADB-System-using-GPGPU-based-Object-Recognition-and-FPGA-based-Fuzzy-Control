# YOLOv7 객체 인식 모델 학습

ADB 제어 대상인 `person`과 `car` 두 클래스를 학습하기 위한 설정 생성·실행 스크립트입니다. 실행 환경에 따라 데이터와 모델 경로를 지정할 수 있도록 정리했습니다.

## 파일

| 파일 | 역할 |
|---|---|
| `train_custom_yolov7.py` | 데이터셋·모델 YAML 생성, 사전 학습 가중치로 YOLOv7 학습 실행 |
| `requirements.txt` | 학습 준비 스크립트의 Python 의존성 |
| [PROVENANCE.md](PROVENANCE.md) | 학습 구성과 정리 내역 |

## 실행 환경

사용자가 준비한 **YOLOv7 디렉터리와 학습 환경**을 사용합니다. 해당 디렉터리에는 `train.py`, `cfg/training/yolov7.yaml`, `data/hyp.scratch.p5.yaml`이 있어야 합니다. PyTorch·CUDA 등 학습에 필요한 패키지는 그 환경에 설치합니다.

데이터셋은 YOLO 형식으로 준비합니다. 클래스 번호는 `0: person`, `1: car`입니다.

| 이미지 경로 | 대응하는 라벨 경로 |
|---|---|
| `images/train/<name>.jpg` | `labels/train/<name>.txt` |
| `images/val/<name>.jpg` | `labels/val/<name>.txt` |
| `images/test/<name>.jpg` — 선택 사항 | `labels/test/<name>.txt` |

라벨의 각 행은 `class_id x_center y_center width height`이며, 좌표와 크기는 0~1 범위로 정규화합니다.

## 설정 생성

저장소 루트에서 실행합니다. 아래 경로는 준비한 YOLOv7, 데이터셋, 가중치 위치로 바꿉니다.

```bash
python -m pip install -r gpu/requirements.txt

python gpu/train_custom_yolov7.py \
  --yolov7-dir /path/to/yolov7 \
  --dataset /path/to/adb-dataset \
  --weights /path/to/yolov7_training.pt \
  --output-dir build/yolov7-training \
  --prepare-only
```

`--prepare-only`는 `data.yaml`과 `custom_yolov7.yaml`을 생성하고 학습 명령을 출력합니다. 원본 YOLOv7 모델 설정은 유지하며, 복사한 설정의 클래스 수를 2로 변경합니다.

## 학습

위 명령에서 `--prepare-only`를 제거하면 지정한 Python 환경으로 학습을 실행합니다. 결과는 `--output-dir` 아래 `runs/`에 저장합니다.

| 옵션 | 기본값 |
|---|---:|
| `--epochs` | 100 |
| `--batch-size` | 16 |
| `--img-size` | 640 |
| `--workers` | 4 |
| `--device` | `0` |
| `--name` | `custom_yolov7_result` |

`--base-config`와 `--hyp`로 모델·학습 설정을 별도로 지정할 수 있습니다. 기본 실행은 로컬 가중치를 사용하며, 다운로드가 필요한 경우에만 `--download-weights`를 추가합니다.

## 시스템 연동

프로젝트의 객체 검출, 대상 선택, 좌표 정규화와 UDP 전송 흐름은 [시스템 설계](../docs/architecture.md)에 정리했습니다. Zybo 수신 데이터의 형식은 [통신 규격](../docs/protocol.md)을 참고합니다.
