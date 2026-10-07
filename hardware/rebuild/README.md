# DDR·PWM 연결 복구

보존된 XSA의 PS 설정과 현재 RTL을 이용해 Vivado 프로젝트를 다시 만드는 스크립트다. [원래 블록 설계 캡처](../../docs/assets/vivado-block-design.png)에 있는 DDR 읽기 경로와 PWM 외부 포트를 재구성한다. PS의 DDR 부품·타이밍·MIO 설정은 XSA에서 추출한다.

**검증 상태:** 두 XSA의 PS 설정 추출, Tcl 구문·입력 검사, Icarus RTL 시뮬레이션을 수행했다. 이 환경에는 Vitis 2024.1만 있어 Vivado 프로젝트 생성·BD validation·합성·구현은 실행하지 않았다. 아래 스크립트는 재구성 소스이며 검증된 새 bitstream을 제공하지 않는다. 기존 XSA도 교체하지 않았다.

## 새 프로젝트 생성

Python 3.10 이상, Zynq-7000 디바이스를 포함한 **Vivado 2024.1**이 필요하다. 저장소 루트에서 실행한다. `build/adb`는 아직 존재하지 않는 경로여야 한다.

```sh
python hardware/rebuild/extract_ps7.py --xsa hardware/design_ADB_valid2_wrapper.xsa --output build/ps7_config.tcl
vivado -mode batch -source hardware/rebuild/create_bd.tcl -tclargs build/ps7_config.tcl build/adb
```

1. `extract_ps7.py`가 DDR·MIO·주변장치·클럭 입력 설정을 Tcl dictionary로 저장한다. 계산된 클럭 값과 경로·날짜 메타데이터는 제외한다.
2. `package_fuzzy_ip.tcl`이 현재 RTL과 실제 AMD Divider Generator `div_gen_0`를 포함한 IP를 패키징한다. 시뮬레이션용 divider 모델은 포함하지 않는다.
3. `create_bd.tcl`이 PS7, DMA, 제어 AXI Interconnect, reset controller와 퍼지 IP를 만들고 `repair_bd.tcl`로 DDR·PWM 연결을 적용한다.
4. BD validation과 output-product 생성이 성공하면 `build/adb/project/adb_rebuilt.xpr` 및 `design_ADB_wrapper`를 제공한다. 이 명령은 합성·구현을 실행하지 않는다.

Vivado에서 지원하지 않는 PS 속성, 다른 IP 버전, 연결·주소 충돌은 오류로 중단한다. 스크립트는 현재 열린 프로젝트나 기존 출력 디렉터리를 덮어쓰지 않는다.

## 연결

| 경로 | 구성 |
|---|---|
| DDR 읽기 | `axi_dma_0/M_AXI_MM2S` → `axi_mem_intercon/S00_AXI` → `axi_mem_intercon/M00_AXI` → `processing_system7_0/S_AXI_HP0` |
| 입력 스트림 | `axi_dma_0/M_AXIS_MM2S` → `my_fuzzy_ip_0/S00_AXIS` |
| 방향 PWM | `my_fuzzy_ip_0/o_pwm_steer` → `o_pwm_steer_0` |
| 범위 PWM | `my_fuzzy_ip_0/o_pwm_speed` → `o_pwm_speed_0` |
| 공통 클럭 | PS `FCLK_CLK0`, 50 MHz |
| 공통 리셋 | `rst_ps7_0_50M/peripheral_aresetn`, active-low |
| DMA 제어 주소 | `0x40400000`, 64 KiB |
| 퍼지 제어 주소 | `0x43C00000`, 64 KiB |

DMA는 simple MM2S-only, memory/stream 32-bit 구성을 사용한다. HP0는 64-bit로 활성화하고 AXI Interconnect가 데이터 폭을 변환한다. DMA의 DDR 주소 범위는 PS가 제공하는 `HP0_DDR_LOWOCM` 주소 구간으로 배정한다.

## 기존 프로젝트에 연결 패치만 적용

이미 Vivado 프로젝트가 있다면 아래 셀을 포함하는 `design_ADB`를 열어 `repair_bd.tcl`만 적용할 수 있다. XSA 자체에는 원본 `.bd`가 없으며, 위의 `create_bd.tcl`이 이 구성을 새로 만든다.

- `processing_system7_0`: Zybo Z7-20 DDR/MIO 설정, FCLK0 50 MHz, GP0 control master.
- `ps7_0_axi_periph`: GP0에서 DMA `S_AXI_LITE`와 퍼지 `S00_AXI`로 이어지는 control interconnect.
- `axi_dma_0`: simple MM2S-only, 32-bit memory 및 32-bit stream.
- `my_fuzzy_ip_0`: 저장소의 최신 RTL을 포함하고 `S00_AXI`, `S00_AXIS`, 두 `o_pwm_*` 핀을 노출하는 IP.
- `rst_ps7_0_50M`: FCLK0에 동기화되고 active-low `FCLK_RESET0_N`을 받는 reset controller. `dcm_locked`, `aux_reset_in`, `mb_debug_sys_rst`도 유효한 비활성/잠금 상태에 연결한다.

최신 RTL IP에는 실제 Divider Generator `div_gen_0`가 필요하다. 설정은 [FPGA 문서](../../fpga/README.md)에 있다. `div_gen_0_model.v`는 시뮬레이션 전용이므로 합성 소스에 넣지 않는다. 보존된 XSA의 구형 IP에 PWM 핀이 없으면 스크립트는 새 연결을 만들기 전에 중단한다.

Vivado Tcl console에서 실행한다.

```tcl
open_bd_design <project_path>/design_ADB.bd
source <repository_path>/hardware/rebuild/repair_bd.tcl
```

주소가 이미 다른 값으로 배정되어 있거나 대상 핀이 다른 net에 연결된 경우 해당 연결을 덮어쓰지 않고 오류를 낸다. 오류가 발생하면 BD의 미저장 변경을 검토하거나 다시 연 뒤 원인을 해결한다. `ADB_BD_REPAIR_VALIDATED` 메시지는 그 Vivado 실행에서 `validate_bd_design`과 저장을 통과했다는 의미이며 보드 동작 검증을 뜻하지 않는다.

## 물리 PWM 핀

원래 steer/speed의 package-pin 대응은 남아 있지 않다. 실제 배선에 맞는 핀 두 개를 결정하고 `pwm_pins.xdc.example`을 `pwm_pins.xdc`로 복사해 프로젝트 constraints에 추가한다. 예제에는 임의의 핀 번호를 넣지 않았다.

```tcl
set ::env(ADB_PWM_STEER_PIN) <actual_package_pin>
set ::env(ADB_PWM_SPEED_PIN) <actual_package_pin>
add_files -fileset constrs_1 <path>/pwm_pins.xdc
```

값은 `JB1` 같은 PMOD 위치 이름이 아닌 FPGA package pin이다. 두 값이 빠졌거나 같으면 XDC가 오류를 낸다. 전기 규격은 원래 설계와 같은 `LVCMOS33`이다. 이미 같은 포트를 다루는 별도 XDC가 있다면 중복되지 않게 정리한다.

## Vivado와 보드에서 검증할 항목

1. 패치 적용 후 `validate_bd_design` 성공과 Address Editor의 DMA→DDR 매핑을 확인한다.
2. BD output products와 HDL wrapper를 생성하고 실제 Divider IP를 포함해 합성한다.
3. PWM 핀 XDC를 적용하고 구현·타이밍·DRC를 통과시킨다. 미지정 핀 DRC를 낮춰 bitstream 생성을 강제하지 않는다.
4. 새 bitstream과 이를 포함하는 XSA를 생성해 Vitis 플랫폼/BSP를 갱신한다.
5. 보드에서 PS DDR 버퍼를 DMA MM2S로 전송하고 완료/오류 상태, 퍼지 결과 레지스터, 두 PWM의 50 Hz 주기와 펄스폭을 검사한다.

보드 없이 수행할 수 있는 범위는 BD 연결, 주소·클럭·리셋 검사, RTL 시뮬레이션, 합성·구현·타이밍·DRC까지다. 마지막 DMA 실전송과 외부 PWM 파형은 보드에서 검사한다.

Tcl API 참고: [AMD assign_bd_address](https://docs.amd.com/r/2024.1-English/ug835-vivado-tcl-commands/assign_bd_address), [AMD BD_ADDR_SEG](https://docs.amd.com/r/2023.2-English/ug912-vivado-properties/BD_ADDR_SEG).
