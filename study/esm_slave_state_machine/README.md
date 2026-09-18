# esm_slave_state_machine — EtherCAT 슬레이브 상태기, 세 체계 비교 (2026-09-17)

같은 과제 문장을 세 에이전트 체계(**cur** = 현행 Claude Code + 볼트 규칙, **ruflo**, **ecc**)에 헤드리스로 주고, 각각이 만든 Stateflow 모델을 **숨은 입력 시퀀스로 채점**한 기록이다. 결과: 셋 다 숨은 시험 14/14·공개 3/3, 같은 설계로 수렴. 갈린 것은 배치(ruflo 세로 한 줄)와 비용뿐 → 그 배치 습관을 `_shared/harness/build/layout_chart.m` 로 옮겼다.

**한 폴더에 나란히** — 파일 이름의 `_cur` · `_ruflo` · `_ecc` 가 어느 체계의 결과물인지 말한다(`_ref` 는 검증 세션이 채점기 자가검사용으로 만든 참조 모델). 모델 안의 이름도 파일과 같다(`Esm_cur` …).

## 과제 (요지)

- 공개 출처: ETG.1000.6 AL 상태기 중 네 상태 — Init(1) · Pre-Operational(2) · Safe-Operational(4) · Operational(8). 허용 전이 9개: 1→2 · 2→1 · 2→4 · 4→1 · 4→2 · 4→8 · 8→1 · 8→2 · 8→4.
- 이 과제가 더한 규칙: 불법 요청 → `err = 1`(상태 유지) · `ack` 가 `err` 를 지움 · `err` 중에는 Init 요청만 통과 · `req == st` 면 무시.
- 인터페이스 고정: Inport `req`(uint8)·`ack`(boolean), Outport `st`·`err`·`outEn`(= `st == 8`), 고정 스텝 1 ms. **t = 0 은 초기화 틱**(입력 무시, `st = 1`), k번째 입력은 t = k ms.
- 틱 순서: ① `ack` → `err = 0` ② 요청 처리 ③ `outEn`.

## 파일 — 맨 위는 결과물만

| 결과물 (× `_cur` `_ruflo` `_ecc`) | 내용 |
| --- | --- |
| `Esm_<side>.slx` | 모델 (안의 모델 이름도 같다) |
| `build_Esm_<side>.m` | Stateflow API 로 그 모델을 처음부터 재생성 |
| `Esm_<side>_사양.md` | 전이표 형식 사양표(그 체계의 설계) |
| `open_all.m` | 네 모델을 나란히 연다 |

| 보조 | 내용 |
| --- | --- |
| `_검증/` | 각 체계의 `test_*.m`(공개 시험 3) · `verify_*.m`(update · 덤프 · `compare_spec` · 이름 규칙) · 검증 세션의 재채점 기록(`채점_*.md` · `독립측정_*.json`) · 참조 모델 `build_Esm_ref.m`/`Esm_ref.slx`(3/3 · 14/14, 가드를 뺀 오답은 6/14) · `tests/`(기준 구현 `esm_ref.m` · `public_cases.m` · `gen_hidden.m`→`hidden_cases.mat` 숨은 14/285틱 · `run_hidden.m` · `measure_esm.m`). 덤프·캐시(`_덤프_*` · `_slprj`)도 여기 생긴다 |
| `_그림/` | Chart 그림 — `*_원본.png`(각 체계 배치) · `*_전.png`/`*_후.png`(`layout_chart` 전/후) |

## 돌려 보기

```matlab
cd <이 폴더>
build_Esm_ruflo; run('_검증/test_Esm_ruflo.m')          % 한 체계 재생성 + 공개 시험
addpath _검증/tests; run_hidden('Esm_ruflo.slx')        % 숨은 시험 — 14/14 이면 규칙과 같다
open_all                                                % 넷 나란히
```

`verify_*.m` 은 `_shared/harness`(덤프·`compare_spec`)를 절대 경로로 `addpath` 한다 — 다른 PC 에서는 그 줄만 고친다. 결과물 스크립트의 출력 폴더는 자기 위치, `_검증/` 의 스크립트는 상위(작업 폴더).

## 결과 (검증 세션 재실행 값, 2026-09-18 새 이름으로 재확인)

| | cur | ruflo | ecc |
| --- | --- | --- | --- |
| 숨은 14 / 공개 3 | 14 / 3 | 14 / 3 | 14 / 3 |
| `compare_spec`(사양표 ↔ 모델) | 0 | 0 | 0 |
| 구조 | State 5(상위 1 + 4) · 전이 11 · 데이터 5 | 같음 | 같음 |
| 이름 최대 State/데이터/라벨 | 6 / 5 / 18 | 6 / 5 / 18 | 6 / 5 / 18 |
| 배치 | 2×2 격자, 대각선 교차 | **세로 한 줄** | 가로 한 줄, 라벨 겹침 |

세 모델 모두 같은 설계다: 상위 State `Al` 의 `during: err = err && !ack;` → 자식 4개의 가드 전이 `[req == N && !err]`(→Init 은 `[req == 1]`) → 자식 `during: err = err || (req != 0 && req != st);`.
