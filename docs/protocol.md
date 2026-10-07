# UDP 프로토콜

Jetson과 Zybo는 동일 이더넷 네트워크에서 통신합니다. 수신 포트는 **UDP 5001**입니다.

## 패킷

한 datagram에 공백으로 구분한 ASCII 실수 세 개를 담습니다.

```text
0.350000 0.650000 0.080000
```

| 필드 | 의미 | 범위 |
|---|---|---|
| `x_left` | 대상 왼쪽 경계 / 영상 너비 | 0~1 |
| `x_right` | 대상 오른쪽 경계 / 영상 너비 | 0~1 |
| `size` | 대상 bounding box 면적 / 영상 면적 | 0~1 |

수신 측은 유한한 실수인지 검사하고 값을 범위 안으로 제한합니다. 좌우 값이 뒤집혀 있으면 순서를 바꿉니다. 패킷이 200ms 동안 들어오지 않으면 제어 태스크가 영점 입력을 보냅니다.

## 송신 확인

아래 코드는 수신 경로를 확인할 때 사용하는 10Hz 예제입니다. IP는 보드 설정에 맞춥니다.

```python
import socket
import time

with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    for _ in range(50):
        sock.sendto(b"0.35 0.65 0.08", ("192.168.10.20", 5001))
        time.sleep(0.1)
```

Jetson의 영상 인식 출력에도 같은 형식의 datagram을 사용합니다.
