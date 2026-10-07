# FPGA fuzzy-control RTL

`rtl/`은 Verilog를 모듈별로 정리한 소스다. AXI-Stream 입력을 소속도 계산, 규칙 추론, 비퍼지화로 처리하고 50 Hz PWM 두 채널을 생성한다.

| 모듈 | 역할 |
|---|---|
| `Kalman_Filter`, `KM_Core` | 두 채널의 스파이크 제거·변화량 제한·안정 입력 재설정 |
| `my_fuzzy_ip_v1_0` | AXI 인터페이스, fuzzy core, PWM 통합 |
| `my_fuzzy_ip_slave_lite_v1_0_S00_AXI` | 설정 쓰기와 결과 캡처·읽기 |
| `my_fuzzy_ip_slave_stream_v1_0_S00_AXIS` | angle / velocity / width 3-word 수신 |
| `Fuzzy_Control_Unit`, `Fuzzifier`, `MF_Core` | 파이프라인 연결과 사다리꼴 소속도 계산 |
| `Inference_Engine`, `Rule_Memory`, `MM_Core`, `Max_Tree_Generic`, `AMU` | 규칙별 min 연산과 출력별 max 집계 |
| `Defuzzifier`, `MAC_Core`, `Adder_Tree_Generic`, `Divider_Wrapper` | 가중 singleton 평균 |
| `PWM_Generator` | 각도 제한과 PWM 주기별 펄스폭 갱신 |

모듈명과 인터페이스를 유지했다. `Kalman_Filter`는 두 `KM_Core`를 묶는 이름이며 구현은 임계값·변화량 기반 필터다. 이 필터는 별도 모듈로 보존되어 있다. `my_fuzzy_ip_v1_0`의 데이터 경로는 AXI-Stream에서 fuzzy core로 직접 연결된다.

## 통합 설정

- 대상: Zybo Z7-20, `xc7z020clg400-1`.
- AXI-Lite와 AXI-Stream에 동일한 50 MHz clock/reset을 연결한다.
- AXI-Lite 설정은 32-bit 정렬된 full-word 쓰기를 사용한다.
- 스트림 한 프레임은 signed 32-bit `[angle, velocity, width]` 세 word이며 마지막 word에 `TLAST`를 지정한다.
- 결과는 `0x000`에서 angle, `0x004`에서 width를 읽는다. 설정 레지스터는 쓰기 전용이다.
- 최종 펌웨어는 velocity 소속도를 transparent mode로 설정하여 angle과 width 중심으로 제어한다.
- PWM 출력 `o_pwm_steer`, `o_pwm_speed`를 사용하는 보드 배선에 맞춰 XDC에 연결한다.

`Divider_Wrapper`는 AMD Divider Generator 인스턴스 `div_gen_0`를 사용한다. signed dividend 32-bit, signed divisor 16-bit, non-blocking AXI-Stream 인터페이스와 48-bit remainder-format 출력을 연결한다. wrapper의 몫은 `[47:16]`, 나머지는 `[15:0]`에 대응한다. divider latency는 36클럭이다. `rtl/testbench/div_gen_0_model.v`는 회귀검사용 연산 모델이며 합성 소스에서 제외한다.

## 정리하며 반영한 수정

- Divider의 `safe_dividend`·`safe_divisor`를 실제 IP 입력에 연결해 0분모를 `0/1`로 처리.
- `MF_Core`의 valid를 데이터 3단계 파이프라인에 정렬.
- `a=b`, `c=d`인 shoulder 소속함수의 끝점에서 최대 소속도 유지.
- AXI-Lite 응답이 대기 중일 때 다음 거래의 수락을 보류하고, 결과 주소를 전체 주소로 판별.
- PWM 명령을 유효한 퍼지 결과에서만 갱신하고 다음 유효 결과까지 유지.
- reset 해제 후 divider의 36클럭 잔여 결과를 차단해 이전 명령이 PWM과 AXI 결과 레지스터에 다시 저장되지 않도록 처리.
- 임시 편집 주석을 모듈 역할과 인터페이스 설명으로 정리.

위 변경은 저장소 정리 과정의 소스 수정이며, [보존 XSA/bitstream](../hardware/README.md)에는 반영하지 않았다.

현재 RTL을 실제 Divider IP와 함께 패키징하고 DDR·PWM 경로를 연결하는 Vivado 스크립트는 [하드웨어 재구성 안내](../hardware/rebuild/README.md)에 있다.

## 검증

현재 RTL은 Icarus Verilog 14에서 단위 회귀와 최상위 통합 테스트를 모두 통과했다. 통합 테스트는 25개 결과와 약 617만 클럭을 검사했으며, reset 중이던 연산의 잔여 결과 차단과 새 프레임 재개까지 포함한다. Vivado 합성·구현과 실제 보드 검증은 수행하지 않았다.

Icarus Verilog를 설치한 환경에서는 저장소 루트에서 다음 명령으로 단위 회귀와 전체 데이터 경로 테스트를 함께 실행한다. Python 외 패키지는 필요하지 않다.

```sh
python fpga/rtl/testbench/run_tests.py
```

실행 파일이 PATH에 없으면 `--iverilog <iverilog 경로> --vvp <vvp 경로>`를 지정한다. 로그와 결과 JSON은 `build/rtl-tests/`에 생성한다. `tb_system.v`는 AXI-Lite로 소속함수·규칙·Singleton을 설정한 뒤 실제 3-word 스트림을 보내 signed 연산 결과와 AXI 읽기를 검사한다. 또한 50MHz에서 1,000,000클럭의 PWM 주기, 0도·±90도·범위 밖 명령, 부분 프레임 동안 이전 명령 유지, reset을 검사한다. 테스트의 divider는 연산 모델이므로 AMD IP 합성·구현이나 실물 PWM 배선을 검증하지 않는다.

`tb_regression.sv`의 단위 회귀 항목은 다음과 같다. 실물 시연 결과는 [구현 결과](../docs/results.md)에 정리했다.

- 소속도 데이터와 valid의 정렬 및 shoulder 끝점.
- 0분모 처리와 signed 나눗셈 wrapper.
- AXI-Lite read/write 응답 backpressure.

Vivado/XSim에서 단위 회귀만 실행할 경우 `fpga/` 디렉터리에서 다음 명령을 사용한다. divider 연산은 동봉된 시뮬레이션 모델을 사용한다.

```sh
xvlog --sv rtl/*.v rtl/testbench/div_gen_0_model.v rtl/testbench/tb_regression.sv
xelab tb_regression -s adb_rtl_regression
xsim adb_rtl_regression -runall
```
