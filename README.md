# matlab-work — 업무 MATLAB 작업 폴더

회사 업무의 **MATLAB/Simulink/Stateflow 실작업**이 여기서 일어난다.
모델 파일, `.m` 소스, 생성된 C 코드, 검증 스크립트가 들어간다.

노트·문서는 여기가 아니라 **볼트**에 있다 → `C:\Users\leeyj\Documents\yj.lee\work\`

> ⭐ **날짜 폴더는 볼트 `work/projects/sessions/` 와 1:1 이다** (2026-08-04 확립 · **2026-08-10 에 `work/sessions/` 에서 `work/projects/sessions/` 로 옮겼다**).
> `matlab-work\20260804\` 에서 한 일은 → `볼트\work\projects\sessions\20260804\` 에 쓴다. **폴더 이름이 문자 그대로 같다.**
> 세션 노트가 **원본**이고, 볼트 `work/projects/` 쪽에는 작업 로그 한 줄과 링크만 남는다.
> 목록·규칙: `볼트\work\projects\sessions\_안내.md`

---

## 왜 볼트 바깥인가

기밀 문제가 아니다 (`work/**` 는 2026-08-04 에 전면 해제됐다). 이유는 전부 기술적인 것이다.

| 이유 | 설명 |
| --- | --- |
| **코드 생성** | 코드 생성 툴체인은 **비ASCII·공백 경로에서 깨진다.** 볼트 경로엔 `yj.lee` 의 점이 있고 하위 폴더는 한글 규칙(`자료/`)을 쓴다. 지금 주 업무가 하필 MATLAB→C 변환이라 이게 직격이다 |
| **빌드 찌꺼기** | `slprj/` `*_ert_rtw/` `*.asv` 가 계속 쏟아진다. Obsidian 이 전부 색인하면 볼트 검색이 쓰레기로 덮인다 |
| **버전 관리** | 볼트는 `git init` 을 하지 않는 규칙이다. 코드는 버전 관리가 필요하다. 분리하면 여기만 git 을 쓸 수 있다 |
| **이름 규칙 충돌** | 볼트는 한글 폴더 + 언더스코어 파일. MATLAB 식별자는 하이픈·한글을 못 쓴다 |

`stateflow-ai-practice` 를 볼트 바깥에 둔 것과 같은 이유다.

---

## 폴더

```
matlab-work\
├── README.md              이 파일
├── start-session.ps1      컴퓨터 켜고 이것부터 실행
├── .gitignore
│
├── m1-supervisor\         M1 감독제어기 (분석 → C 변환 → EtherCAT)
│   ├── models\            .slx .mdl
│   ├── src\               .m 소스
│   ├── tests\             MATLAB↔C 동작 비교 검증
│   └── codegen\           생성된 C — 빌드 산출물, git 에 안 올린다
│
├── adrc\                  ADRC 제어기
├── legacy-stateflow\      전임자 Stateflow 산출물
├── _shared\               공용 유틸 (harness\ = 덤프·전이표·사양표 대조·layout_chart)
│
├── results\               작업별 결과물 — 작업 하나 = 폴더 하나, 맨 위는 결과물만(slx·build·사양표 × _cur/_ruflo/_ecc), 보조는 _검증\·_그림\
│   ├── esm_slave_state_machine\   EtherCAT 슬레이브 상태기(공개 표준) — GitHub 공개 거울에 올라감
│   └── ecapp_master_lifecycle\    EtherCAT 마스터 앱 수명주기(🔴 회사 C 발췌) — 안 올라감
├── open_allow.txt         공개 거울에 올릴 경로 목록 (results\<과제> 를 한 줄씩. 여기 없는 것은 안 올라감)
└── push_open.ps1          공개 거울 동기화 — GitHub genie4youu/matlab-work
```

**공개 거울(2026-09-18):** 이 저장소는 원격이 없다(회사 모델 포함). GitHub `genie4youu/matlab-work` 는 `open_allow.txt` 의 경로(`_shared`·`results/<과제>`·루트 스크립트)만 복사한 별도 저장소이고 `push_open.ps1` 로만 올린다 — 목록에 없는 폴더는 기본 거부, 회사 모델 이름은 예시 이름으로 치환, 남으면 push 가 막힌다. 새 작업을 올리려면 `results/<과제>` 한 줄을 목록에 더한다(회사 자료에서 온 작업은 적지 않는다).

**업무 하나 = 폴더 하나.** 볼트 `work/projects/` 규칙과 같게 맞췄다.

| 여기 | 볼트 노트 | 축 |
| --- | --- | --- |
| `m1-supervisor/` | `work/projects/M1-감독제어기/` | 주제 |
| `adrc/` | `work/projects/ADRC-제어기/` | 주제 |
| `legacy-stateflow/` | `work/projects/전임자-Stateflow산출물/` | 주제 |
| **`20260804/` 같은 날짜 폴더** | **`work/projects/sessions/20260804/`** | **시간** |

> ⚠️ `codegen/` 은 MATLAB 경로에 **등록되지 않는다** (`startup.m` 이 제외한다).
> 등록하면 옛 생성 코드가 실제 소스를 가려서 *"고쳤는데 안 바뀐다"* 가 된다.

---

## 시작 순서

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\leeyj\matlab-work\start-session.ps1
```

1. 스크립트가 환경을 점검하고 **MATLAB 을 띄운다**
2. `startup.m` 이 경로 등록 + `satk`(세션 공유)를 **자동으로** 한다
3. **그 다음에** Claude Code 를 연다 ← 순서가 중요하다
4. Claude Code 에서 `/mcp` 로 `matlab` 이 connected 인지 확인

> 🔴 **MATLAB 이 먼저, Claude Code 가 나중.**
> MCP 는 Claude Code 가 시작할 때 붙는다. 반대로 하면 도구 목록은 보이는데 호출이 안 된다.

세션을 공유하고 싶지 않은 날은 MATLAB 켜기 전에 `setx MATLAB_NO_SHARE 1`.

---

## 발행 경계 — 여기 것은 나가지 않는다

이 폴더는 **회사 업무**다. 볼트의 `work/**` 와 같은 취급이다.

🔴 여기 있는 모델·코드·구조를 블로그(`portfolio/`)나 공개 GitHub 로 옮기지 않는다.
공개용 예제는 `study/` 에서 공개 출처를 인용해 **처음부터 따로** 쓴다.

> 회사 자료를 자유롭게 읽게 되면서 이 구분이 전보다 더 중요해졌다.
> 읽은 게 많아질수록 *"그냥 내가 아는 일반 원리"* 로 착각할 여지도 같이 커진다.

- 발행 규칙: `Documents\yj.lee\CLAUDE.md` 의 Zone 규칙
- 시작 순서 매뉴얼: `Documents\yj.lee\work\knowledge\AI도구_작업환경_시작순서.md`
