# Zynq PS firmware

FreeRTOS와 lwIP로 객체 좌표를 수신하고, FPGA 퍼지 제어기에 입력값을 전달하는 펌웨어다. 수신 태스크와 제어 태스크를 큐로 분리하고, 초기 설정 완료를 세마포어로 동기화한다.

## 구성

| 경로 | 입력 전송 | 용도 |
|---|---|---|
| [`dma/src`](dma/src) | AXI DMA → AXI-Stream | 최종 제어 설정을 반영한 주 구현 |
| [`axi_lite/src`](axi_lite/src) | AXI4-Lite 레지스터 쓰기 | 초기 인터페이스 및 제어 설정을 보존한 참조 구현 |

각 디렉터리는 독립적인 Vitis 애플리케이션 소스다. 한 애플리케이션에는 한 변형만 넣는다. 두 변형 모두 설정 쓰기와 결과 읽기에 AXI4-Lite를 사용한다.

## 데이터 흐름

1. `producer_udp_task`가 UDP 5001 포트에서 `x_left x_right size`를 받는다.
2. 유효한 세 실수를 길이 10의 큐에 넣는다. 큐가 가득 차면 새 패킷을 버린다.
3. `fuzzy_runtime_task`가 좌표를 0–1로 제한하고 좌우 순서를 정렬한다.
4. 수평 시야각 55°를 기준으로 중심 방향과 프레임 간 방향 변화량을 계산한다.
5. 정수 입력 세 개를 PL에 전달하고, DC 및 linear 결과를 읽어 UART로 출력한다.

```text
UDP: "0.40 0.60 0.20"
PL 입력: angle=0, velocity=직전 좌표에 따른 값, width=200
DMA payload: int32 angle, int32 velocity, int32 width (12 bytes)
```

`size`는 바운딩 박스 면적을 이미지 면적으로 나눈 객체의 면적 비율이다. 이 값을 `width = size × 1000`으로 변환해 RTL의 Width 입력에 전달한다. 각도 입력은 영상 중앙에서 0, 좌측 끝에서 -1000, 우측 끝에서 +1000이다. 기본 속도 특성은 시간으로 나누지 않은 프레임 간 각도 변화량이다.

200ms 동안 새 입력이 없으면 `(angle, velocity, width) = (0, 0, 0)`을 다시 전송한다. 최종 퍼지 설정에서 이 입력은 중심 방향과 Short 폭 조건에 대응한다.

## 최종 DMA 제어 설정

최종 펌웨어는 velocity 소속도를 transparent mode로 설정해 angle과 width 중심으로 추론하도록 구성한다. PL Fuzzifier는 매 클럭의 각도 차이로 velocity를 자체 계산하며, PS가 보낸 velocity 워드는 추론 계산에 사용하지 않는다. 전송 형식은 세 워드를 유지한다.

| 멤버십 함수 | a | b | c | d |
|---|---:|---:|---:|---:|
| Angle NB | -1000 | -1000 | -650 | -300 |
| Angle NM | -650 | -300 | -300 | 0 |
| Angle ZE | -500 | -200 | 200 | 500 |
| Angle PM | 0 | 300 | 300 | 650 |
| Angle PB | 300 | 650 | 1000 | 1000 |
| Velocity SLOW | -2000 | -1000 | 1000 | 2000 |
| Velocity FAST | 2000 | 3000 | 4000 | 5000 |
| Width SHORT | 0 | 0 | 100 | 500 |
| Width LONG | 300 | 400 | 1000 | 1000 |

DC singleton은 `[-50, -25, 0, 25, 50]`, linear singleton은 `[60, -70]`이다. DC의 SLOW 규칙은 NB→4, NM→3, ZE→2, PM→1, PB→0이며, FAST 규칙은 모두 action 2로 설정한다. 폭 규칙은 SHORT→0, LONG→1이다.

## 네트워크 설정

선택한 변형의 [`app_config.h`](dma/src/app_config.h)를 수정한다.

| 설정 | 기본값 |
|---|---|
| 보드 IPv4 | `192.168.10.20` |
| 서브넷 마스크 | `255.255.255.0` |
| 게이트웨이 | `192.168.10.1` |
| UDP 포트 | `5001` |
| MAC 주소 | `02:00:00:00:00:20` |
| 수평 시야각 | `55.0f` |
| 미수신 입력 전송 주기 | `200ms` |

송신 PC도 같은 서브넷으로 설정하고 목적지 주소를 보드 IP에 맞춘다. 여러 보드를 함께 쓰면 IP와 MAC 주소를 각각 다르게 지정한다.

## Vitis 빌드 및 실행

원본 개발 환경은 Vitis 2025.2, Zynq-7000 Cortex-A9, FreeRTOS, lwIP 2.2.0이다.

1. Vivado에서 하드웨어를 구성하고 bitstream을 포함한 XSA를 내보낸다. DMA 구현은 MM2S Simple mode, 32-bit AXI-Stream 입력을 사용한다.
2. Vitis에서 XSA로 platform을 만들고 `ps7_cortexa9_0`에 FreeRTOS domain을 생성한다. BSP에서 lwIP socket API를 사용하도록 설정한다.
3. 해당 domain을 대상으로 FreeRTOS 애플리케이션을 만든 뒤, 선택한 변형의 `src` 파일을 가져온다.
4. `app_config.h`를 수정하고 BSP와 애플리케이션을 빌드한다. `CMakeLists.txt`, `UserConfig.cmake`, 메모리 설정 및 linker script를 함께 제공한다.
5. FPGA를 프로그램하고 PS 초기화 후 ELF를 실행한다. UART의 IP 설정과 `[Producer] Ready on port 5001` 메시지를 확인한 뒤 영상 송신부를 실행한다.

DMA 전송을 위해 `M_AXI_MM2S`를 PS DDR에 연결된 AXI 경로로 연결하고 해당 주소 구간을 할당한다. 저장된 XSA의 이 경로와 외부 모터 포트는 비어 있으므로, 재구성할 때 DDR 경로·모터 출력·핀 제약을 연결한 하드웨어를 내보낸다. AXI-Lite 참조판은 `0x300`부터의 입력 레지스터와 `0x30C`의 START 쓰기를 처리하는 초기 RTL에 대응한다.

Fuzzy IP 주소는 `XPAR_MY_FUZZY_IP_0_BASEADDR`를 사용하며 저장된 플랫폼의 값은 `0x43C00000`이다. DMA 주소는 `0x40400000`이다. SDT BSP에서는 DMA lookup에 base address를, 기존 BSP에서는 device ID를 사용한다.

DMA 버퍼는 32-byte 경계에 정렬하고 12-byte 입력을 캐시에서 flush한 다음 전송한다. 전송 및 reset 폴링은 `app_config.h`의 반복 횟수로 제한한다. DMA 오류가 발생한 프레임에서는 PL 결과를 읽지 않고 reset을 시도한다.

## 소스 이력과 정리 내용

- DMA 코드 기반: `finalk/freertos_hello_world/src/freertos_hello_world.c`.
- 최종 제어값과 Stream 전송 방식: `dma/src/freertos_hello_world.c`.
- AXI-Lite 참조판: `workspace/hello_world_final/src/freertos_hello_world.c`.
- 각 변형의 CMake 및 linker 파일은 원본 애플리케이션에서 가져왔다. BSP와 경로가 고정된 IDE 캐시는 Vitis에서 다시 생성한다.
- 공개용 사설 IP/MAC 예제를 설정 헤더로 분리하고, 편집 중 메모를 정리했다.
- 비정상 수치 및 추가 필드가 포함된 UDP 입력을 거르고, bind 실패 시 socket을 닫는다.
- DMA 오류 및 reset 대기에 종료 조건을 추가하고, 실패한 전송의 이전 결과가 출력되지 않도록 했다.
- AXI-Lite 참조판의 Fuzzy IP 주소도 하드웨어 생성 매크로를 사용하도록 수정했다.

두 변형은 원본 SDT BSP 헤더와 Vitis 2025.2 ARM GCC에서 `-Wall -Wextra -Werror` 옵션으로 객체 파일 컴파일을 통과했다. 이 정리본에 대한 보드 실행 검증은 수행하지 않았다.
