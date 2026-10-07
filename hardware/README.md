# 하드웨어 handoff

| 파일 | 원본 | 용도 |
|---|---|---|
| `design_ADB_valid2_wrapper.xsa` | `finalk/` | DMA 입력 버전의 Vitis 플랫폼 생성 |
| `design_ADB_wrapper.xsa` | `workspace/` | 이전 AXI-Lite 참조 버전 |

- 보드: Digilent Zybo Z7-20, `xc7z020clg400-1`
- Vivado export: 2024.1
- ARM Cortex-A9: 약 666.7MHz
- PL / AXI: 50MHz
- XSA에 bitstream 포함

## 하드웨어 통합 순서

보존 XSA의 PS 설정과 현재 RTL로 DDR·PWM 연결을 다시 만드는 스크립트는 [rebuild 안내](rebuild/README.md)에 있다. 보드 없이 프로젝트를 생성하도록 구성했으며, 이 환경에서는 Vivado 합성·구현까지 실행하지 않았다.

Vivado에서 [RTL](../fpga/rtl/)과 Divider Generator IP를 통합한 뒤 AXI4-Lite 설정 포트, DMA MM2S 스트림, PWM 출력을 연결합니다.

보존된 XSA는 PS·AXI 설정을 참조하는 handoff입니다. 해당 HWH에는 DMA `M_AXI_MM2S`의 DDR 연결과 외부 PWM 포트가 포함되어 있지 않습니다. 전체 시스템을 재구성할 때는 다음 연결을 추가하고 bitstream·XSA를 다시 생성합니다.

1. DMA `M_AXI_MM2S`를 PS의 DDR 접근 포트에 연결하고 주소 영역을 할당합니다.
2. DMA `M_AXIS_MM2S`를 퍼지 제어 입력 스트림에 연결합니다.
3. 방향·범위 출력에 PWM 모듈을 연결하고 실제 보드 배선에 맞는 XDC 핀 제약을 적용합니다.
4. 클럭·리셋을 연결한 뒤 timing을 검사하고 새 XSA를 export합니다.

구현 결과 캡처와 프로토타입 사진, 시연 영상은 [구현 결과](../docs/results.md)에 정리했습니다.
