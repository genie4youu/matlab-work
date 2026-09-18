# study/ — 공개 출처로 만든 연습·스터디 모델

> 🟢 이 폴더는 GitHub `genie4youu/matlab-work`(공개 거울)에 **그대로 올라간다**(`open_allow.txt`). 그래서 규칙이 셋이다.

1. **재료는 공개 출처만** — 표준(ETG·IEC…)·공개 문서·직접 만든 규칙. 회사 모델·코드·문서에서 온 것은 `private/` 로.
2. **회사 고유명사 금지** — 모델 이름·부품 이름·프로젝트 이름. `push_open.ps1` 이 알려진 이름은 치환하지만 새 이름은 못 잡는다.
3. **한 폴더 = 한 과제** — 폴더 이름은 영어 snake_case, 안에 `README.md`(무엇·규칙·결과)와 재현 가능한 스크립트(`build_*.m`·`test_*.m`)를 둔다.

| 폴더 | 무엇 | 언제 |
| --- | --- | --- |
| [`esm_slave_state_machine/`](esm_slave_state_machine/README.md) | EtherCAT 슬레이브 상태기(ETG.1000.6 의 4상태 + 오류/ack 규칙)를 세 체계(현행·ruflo·ecc)가 각각 만든 Stateflow 모델과 숨은 시험 채점 | 2026-09-17 |

도구는 `../_shared/harness/`(덤프·전이표·사양표 대조·`layout_chart`). 볼트의 절차·판정은 `study/agentic_engineering/extensions/my_environment/ruflo_comparison/`(비공개 볼트).
