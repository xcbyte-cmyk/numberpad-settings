# Microsoft Number Pad 설정

Microsoft Number Pad의 키 배치와 다른 PC로 이전하기 위한 설정 도구입니다.

**Windows 적용 파일은 `windows/`에 있습니다. macOS 설정 파일은 아직 포함하지 않습니다.**

![넘버패드의 Codex 기능 배치](docs/numberpad-codex.svg)

사용자가 지정한 Codex 단축키는 `codex/`에 별도로 포함했습니다. 대화 기록·인증 정보·전체 앱 설정은 포함하지 않습니다.

## Windows에서 사용

1. 이 저장소를 **Code → Download ZIP**으로 내려받고 압축을 풉니다. `windows/`, `codex/`, `shared/`의 상대 위치를 유지하세요. `shared/`에는 두 도구가 사용하는 공통 함수가 있으므로 개별 폴더만 떼어 옮기면 실행되지 않습니다.
2. Number Pad를 연결하고 Microsoft 마우스·키보드 센터를 설치합니다.
3. Codex와 Microsoft 마우스·키보드 센터 창을 완전히 종료합니다.
4. `windows/1-Apply.cmd`를 일반 사용자로 실행합니다. 기존 설정을 먼저 백업합니다.
5. Codex 사용자 지정 기능까지 옮기려면 `codex/Apply.cmd`를 실행합니다. 같은 명령은 이 프로필로 바꾸고, 다른 기존 명령은 유지합니다. `null`로 저장한 단축키 해제도 그대로 적용됩니다.
6. `/`, `*`를 좌우 Shift로 사용하려면 `windows/2-Windows-Shift.cmd`를 실행해 관리자 권한을 승인합니다.
7. PC를 재부팅한 뒤 `windows/Check.cmd`, `codex/Check.cmd`와 실제 키 입력으로 확인합니다.

자세한 적용 범위·복구 방법은 [Windows 사용 안내](windows/사용안내.md)를 확인하세요.

| Number Pad 키 | 기능 |
|---|---|
| 0 | Ctrl + Alt + F24 → Codex 앱샷 |
| / | F22 → Windows 변환 적용 후 왼쪽 Shift |
| * | F23 → Windows 변환 적용 후 오른쪽 Shift |
| - | Tab |
| Backspace | Esc |
| 1 / 2 / 3 | 추론 수준 낮추기 / 높이기 / 모델 선택 |
| 4 / 5 / 6 | F16 / F17 / F18 — 사용자 지정 기능 없음 |
| 7 / 8 / 9 | 프로젝트 없는 새 작업 / 빠른 채팅 / 보조 채팅 열기 |
| . | 기본 소수점 입력 |
| 계산기 | 계산기 실행 |

위 Codex 기능에는 `codex/Apply.cmd` 적용이 필요합니다. 4~6은 사용자 지정 파일에 연결된 명령이 없다는 뜻이며, 다른 앱이나 기본 동작까지 없다고 단정하지 않습니다. Windows의 F22/F23 변환은 해당 PC 전체에 적용됩니다.

추가 Codex 단축키: `Ctrl+Shift+Space` 메인 채팅 포커스, `Ctrl+Shift+A` 보조 채팅 포커스, `F6` 스킬 다시 불러오기, `Ctrl+Alt+Space` 창 호출. `archiveThread`, `composer.cycleReasoningEffort`, `keyboardShortcuts`는 사용자 지정 파일에서 단축키가 해제되어 있습니다.

Codex 추가 설정은 `codex/Restore.cmd`로 복구합니다. 전체 적용을 되돌릴 때는 **codex/Restore.cmd → windows/Restore.cmd → windows/Restore-Windows-Shift.cmd** 순서입니다. 해당 PC에서 이후 수정한 단축키가 있으면 자동 복구를 중단합니다.

## 안전한 적용과 반복 실행

설정이 이미 같으면 Apply는 파일·레지스트리·복구 기준을 다시 쓰지 않습니다. 실제 변경이 필요할 때만 새 백업을 만듭니다. Codex 설정은 전체 파일을 다시 직렬화하지 않고 대상 최상위 단축키 속성만 편집합니다. 중첩 객체의 같은 이름과 다른 설정의 숫자·문자열 표현은 보존합니다.

JSON 설정 저장은 같은 폴더의 임시 파일을 완성한 뒤 교체합니다. 저장 직전의 변경 여부를 재확인하며, Codex의 두 설정 파일 중 하나가 실패하면 완료한 파일을 조건부로 복구합니다. 다른 프로그램이 이후 수정한 파일은 덮어쓰지 않습니다. 이는 전원 손실까지 보장하는 다중 파일 데이터베이스 트랜잭션은 아니므로 원래 백업도 유지합니다.

Number Pad 적용 기준은 `windows/profile.json`입니다. `windows/numberpad.reg`는 기존 내보내기 참고본이며 자동 적용 경로에서는 가져오지 않습니다. 레지스트리·매크로 적용은 파일 두 개의 트랜잭션과 별도입니다. 실패 시 `windows/Restore.cmd`로 복구하고, 실제 입력은 대상 PC에서 확인해야 합니다.

## Mac에서 사용

Windows의 `.cmd`, `.ps1`, `.reg` 파일을 Mac에서 실행하지 마세요. [Karabiner-Elements](https://karabiner-elements.pqrs.org/)에서 Microsoft Number Pad만 대상으로 설정하고 EventViewer로 실제 입력을 먼저 확인해야 합니다.

`/` → 왼쪽 Shift, `*` → 오른쪽 Shift, `-` → Tab, Backspace → Esc 등은 Mac용 규칙으로 구성합니다. `0`의 앱샷 연결은 해당 Mac의 Codex 버전·단축키·실제 첨부 동작을 확인해야 합니다. 이 저장소는 Mac에서 동작 검증된 매핑을 제공하지 않습니다.

## 개발 및 자동 검증

일반 사용에는 Windows 기본 PowerShell 5.1만 필요하며 Node.js, Python, 추가 PowerShell 모듈이 필요하지 않습니다. 개발용 테스트는 저장소 루트에서 실행합니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run.Tests.ps1
# PowerShell 7이 설치된 개발 환경에서는 추가 실행
pwsh -NoProfile -File .\tests\Run.Tests.ps1
```

GitHub Actions도 두 엔진에서 같은 테스트를 실행합니다. 테스트는 JSON 속성 보존, 잘못된 입력 거부, 단축키 병합, 임시 파일 정리, 동시 변경 방지, 파일 저장 실패 복구, 반복 적용, 스캔 코드 인코딩과 Windows 파일 체크섬을 확인합니다. Codex 통합 테스트는 임시 `CODEX_HOME`과 `LOCALAPPDATA`만 사용하며 실제 사용자 설정·레지스트리·기기 입력은 변경하지 않습니다.

구조 변경과 한계는 [리팩토링 기록](docs/refactoring-notes.md)에 정리했습니다.

## 검증 범위

- 기존 내보내기 당시 원래 Windows PC에서 0번의 실제 앱샷 실행을 사용자가 확인했습니다.
- 기존 내보내기 당시 16개 키 설정과 매크로 2개가 원본과 일치함을 확인했습니다. 이번 리팩토링은 해당 설정 파일과 키 배치도를 바꾸지 않습니다.
- 자동 테스트는 코드와 임시 파일 기반 동작을 검증하며, 실제 키보드 드라이버·관리자 권한 승인·재부팅 후 동작을 대신 검증하지 않습니다.
- 다른 PC의 실제 입력과 앱샷 첨부는 대상 PC에서 별도로 확인해야 합니다.

인증 정보, 블루투스 페어링 정보, 전체 Codex 설정은 포함하지 않습니다. 복구 백업은 적용할 PC의 LocalAppData/ProgramData에 별도로 저장됩니다.
