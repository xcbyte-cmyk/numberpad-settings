# Mac 설정 스냅샷

2026년 9월 25일 저장된 설정입니다. Windows용 파일은 변경하지 않았습니다.

- `karabiner.json`: Microsoft Number Pad만 대상으로 하는 Karabiner-Elements 프로필입니다. 장치 식별자는 Vendor ID 1118, Product ID 2102입니다.
- `keybindings.json`: 해당 Mac에서 사용하는 Codex 사용자 지정 단축키입니다.

| 키 | Mac 기능 |
|---|---|
| 1 / 2 / 3 | 추론 수준 낮추기 / 높이기 / 모델 선택 |
| 4 | F16 → Codex 음성 대화 시작 |
| 5 | F17 → Codex 채팅창 음성 입력 시작 |
| 6 | macOS 받아쓰기 키 → 메모·웹 등의 입력란에 음성 입력 |
| 7 / 8 / 9 | 프로젝트 없는 새 작업 / 빠른 채팅 / 보조 채팅 열기 |
| 0 | 좌우 Command 동시 입력 — Codex 앱샷 연결 및 실제 동작 미확인 |
| / / * | 왼쪽 Shift / 오른쪽 Shift |
| - | Tab |
| Backspace | Esc |
| . | `0909` 입력 후 Enter |
| + / Enter | 이 프로필에서 변경하지 않음 |

2번은 `Control+Shift+Option+R`, 3번은 `Control+Shift+Option+M`을 전송하도록 구성했습니다. Codex의 대응 단축키도 동일한 조합이어야 합니다. 앱 화면에 이전 값이 남으면 단축키 편집에서 해당 넘버패드 키를 눌러 다시 등록하세요. 2·3번의 실제 동작은 아직 확인되지 않았습니다.

계산기 버튼은 `Microsoft Number Pad — Accessibility Keyboard` 단축어로 손쉬운 사용 키보드를 엽니다. 점 키는 `0909` 입력 후 Enter를 보냅니다. 다른 맥에는 같은 이름의 단축어를 별도로 준비해야 합니다. 6번 받아쓰기는 Karabiner에서 지원하는 `consumer_key_code: dictation`을 사용합니다.

## 다른 Mac에 적용

자동 설치 스크립트가 아닌 설정 스냅샷입니다. 기존 설정을 통째로 덮어쓰지 마세요.

1. Karabiner-Elements를 설치하고 필요한 입력 모니터링·손쉬운 사용·드라이버 승인을 완료합니다.
2. `~/.config/karabiner/karabiner.json`을 백업한 뒤 이 파일의 Number Pad 장치 규칙을 사용할 프로필에 병합합니다. 다른 키보드 규칙은 유지합니다.
3. `~/.codex/keybindings.json`을 백업한 뒤 필요한 명령을 병합합니다. 같은 명령의 기존 단축키와 충돌 여부를 확인합니다.
4. 시스템 설정 → 키보드 → 받아쓰기를 켜고 언어와 마이크를 확인합니다. 메모나 웹에서 입력란을 클릭한 뒤 6번을 누릅니다.
5. 실제 Number Pad로 각 키를 테스트합니다. 4·5번은 해당 명령을 지원하는 Codex에서 사용합니다.

## 확인한 범위

설정 JSON 저장과 Karabiner 드라이버 연결·가상 키보드 준비 상태는 확인했습니다. 실제 4·5·6번 음성 동작과 0번 앱샷 동작은 아직 확인하지 않았습니다. 기존 설정으로 복구하려면 적용 전 백업을 사용하세요.

인증 정보, 대화 기록, 전체 Codex 앱 상태, 블루투스 페어링 정보는 포함하지 않습니다.
