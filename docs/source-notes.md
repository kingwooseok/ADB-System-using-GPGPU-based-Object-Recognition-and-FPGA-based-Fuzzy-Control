# 자료 및 소스 안내

## 프로젝트 기록

시연 영상, 구현 결과 이미지, 펌웨어와 RTL을 정리했습니다.

| 자료 | 저장소 경로 | 정리 내용 |
|---|---|---|
| 시연 영상 | `media/adb-demo.mp4` | 추적·차광 시연 |
| 구현 결과 이미지 | `docs/assets/` | 구조도, 타이밍·전력 캡처, 실물 사진 |
| Vitis `finalk`, `workspace` | `firmware/`, `hardware/` | 직접 작성한 소스·빌드 설정·XSA 선별 |
| 학습 코드 | `gpu/` | YOLOv7 학습 스크립트 |
| FPGA 코드 | `fpga/rtl/` | Verilog 모듈 |

최종 DMA 펌웨어에는 소속함수·Singleton 설정을 반영했습니다. 초기 AXI-Lite 구현은 별도 참조 경로에 보존했습니다.

## 공개 정리본의 수정

- 네트워크 주소와 제어 설정을 헤더로 분리하고 사설 IP 예시를 사용했습니다.
- BSP가 제공하는 하드웨어 주소를 사용하도록 AXI-Lite 주소를 수정했습니다.
- UDP 입력 검사와 DMA 오류·timeout 처리를 정리했습니다.
- PDF에서 추출한 코드의 줄바꿈·들여쓰기·임시 주석을 정리했습니다.
- RTL 수정과 시뮬레이션 항목은 [FPGA 안내](../fpga/README.md), 펌웨어 수정은 [firmware 안내](../firmware/README.md)에 기록했습니다.

저장소 문서는 소스의 최종 설정을 기준으로 화각을 55°로 설명하며, 성과표에는 Vivado 캡처로 확인되는 타이밍·전력 수치를 사용했습니다.

## 실행 환경

Vitis에서는 XSA를 기반으로 FreeRTOS/lwIP BSP를 생성합니다. Vivado에서는 복구한 RTL과 Divider Generator IP를 통합합니다. IDE 캐시, 자동 생성 BSP, 빌드 중간 산출물, 데이터셋과 학습 가중치는 저장소에 넣지 않았습니다.

Jetson 추론·UDP 전송의 동작과 인터페이스는 [시스템 설계](architecture.md)와 [UDP 프로토콜](protocol.md)에 정리했습니다. `gpu/`에는 학습 스크립트를 제공합니다.
