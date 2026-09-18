# 사양표 — Esm

- 대상: `Esm`
- 원본: ETG.1000.6 AL 상태기(공개 규격)의 네 상태 — Init(코드 1) · Pre-Operational(2) · Safe-Operational(4) · Operational(8) — 와 허용 전이 9개(1→2 · 2→1 · 2→4 · 4→1 · 4→2 · 4→8 · 8→1 · 8→2 · 8→4). 여기에 과제가 정한 **오류 표시/해제** 규칙(아래 「틱 규칙」)을 더했다. 이 표가 정본이고 `Esm.slx` 는 구현이다.
- 형식: [[work/knowledge/볼트운영/모델저작_규칙]] §2 — `emit_transtable` 의 `전이표.md` 와 같은 절·표 + §0·§5·§6. 표 칸 안의 `|` 는 `\|`.
- 이름 규칙: Chart 데이터·이벤트 ≤ 8자 · State ≤ 12자 · Transition 라벨·State Action 한 줄 ≤ 40자.
- 시간: 고정 스텝 이산, 스텝 1 ms. **t = 0 은 초기화 틱**이다 — 입력을 보지 않고 Chart 가 `Al.Init` 에 들어가며 `st = 1 · err = 0 · outEn = 0` 을 낸다. 시험 입력의 k번째 틱은 t = k ms 에 들어가고 그 틱의 출력은 t = k ms 값이다.

**틱 규칙(정본)** — 매 틱 다음 순서로 처리한다.

1. `ack == 1` 이면 `err = 0`.
2. 요청 — `req ≠ 0` 이고 `req ≠ st` 이면: `err == 1` 이고 `req ≠ 1` → **무시**; 허용 전이면 → `st = req`; 그 밖 → `err = 1`(상태 유지). `req == st` 면 아무 일 없다(req 를 계속 유지해도 재트리거 없음).
3. `outEn = (st == 8)`.

**모델이 이 순서를 지키는 방법** — 부모 State `Al` 이 네 상태를 감싼다. Stateflow 는 활성 State 를 「바깥 전이 → during → 활성 자식」 순으로 실행하므로, `Al` 의 `during`(규칙 1: `err = err && !ack;` — `ack` 이면 `err` 해제)이 자식 State 의 바깥 전이(규칙 2: 허용 전이)보다 **먼저** 실행된다. 허용 전이가 하나도 성립하지 않았을 때만 자식의 `during`(규칙 2 의 「그 밖」: `err = err || (req != 0 && req != st);` — 요청이 있는데 현재 상태도 아니고 허용 전이도 아니었으면 `err = 1`, 이미 1 이면 그대로 = 무시)이 실행된다. 오류 중에는 `[req == 1]`(Init 요청) 전이만 `!err` 조건이 없어 통과한다. 규칙 3 은 각 State 의 `entry` 가 `st` 와 함께 `outEn` 을 쓴다(`st` 는 State 진입에서만 바뀐다). C action language 의 State Action 에는 `if` 문이 없어 두 규칙을 불 대수로 썼다.

## 0. 인터페이스

| 이름 | 방향 | 타입 | 범위/단위 | 설명 |
| --- | --- | --- | --- | --- |
| `req` | Input | uint8 | 0 = 요청 없음 · 1 Init · 2 PreOp · 4 SafeOp · 8 Op · 그 외 값은 불법 요청 | 요청 상태 코드 |
| `ack` | Input | boolean | 0/1 | 오류 해제 |
| `st` | Output | uint8 | 1/2/4/8, 초기값 1 | 현재 상태 코드 |
| `err` | Output | boolean | 0/1, 초기값 0 | 오류 표시 |
| `outEn` | Output | boolean | 0/1 = (`st == 8`), 초기값 0 | 출력 활성 |

루트 Inport `req`·`ack` 와 루트 Outport `st`·`err`·`outEn` 은 Chart 의 같은 이름 데이터에 1:1 로 연결된다. Chart 안에 Local·Constant·Event 는 없다.

## 1. `Esm/EsmChart`

### 1.1 Chart

| 항목 | 값 | C 로 옮길 때 |
| --- | --- | --- |
| Decomposition | `EXCLUSIVE_OR` | 최상위 State 는 `Al` 하나 |
| ActionLanguage | `C` | |
| SampleTime | `0.001` | 1 ms = 한 틱 |

### 1.2 State 계층

| 경로 | 깊이 | 자식분해 | 실행순서 | 하위 |
| --- | --- | --- | --- | --- |
| `Al` | 0 | EXCLUSIVE_OR | 0 | 4 |
| `Al.Init` | 1 | EXCLUSIVE_OR | 0 | 0 |
| `Al.Op` | 1 | EXCLUSIVE_OR | 0 | 0 |
| `Al.PreOp` | 1 | EXCLUSIVE_OR | 0 | 0 |
| `Al.SafeOp` | 1 | EXCLUSIVE_OR | 0 | 0 |

### 1.3 State Action (원문)

**`Al`**

```
Al
during:
err = err && !ack;
```

**`Al.Init`**

```
Init
entry: st = 1; outEn = 0;
during:
err = err || (req != 0 && req != st);
```

**`Al.Op`**

```
Op
entry: st = 8; outEn = 1;
during:
err = err || (req != 0 && req != st);
```

**`Al.PreOp`**

```
PreOp
entry: st = 2; outEn = 0;
during:
err = err || (req != 0 && req != st);
```

**`Al.SafeOp`**

```
SafeOp
entry: st = 4; outEn = 0;
during:
err = err || (req != 0 && req != st);
```

### 1.4 전이표

#### 1.4.1 초기 진입 (default transition 2개)

| # | 목적지 | 종류 | 도달하는 State | 조건/액션 |
| --- | --- | --- | --- | --- |
| 1 | `Al` | State | `Al` |  |
| 2 | `Al.Init` | State | `Al.Init` |  |

#### 1.4.2 전이 (9개) — 실행순서가 곧 if 의 순서다

| Source | → | Destination | 순서 | 조건/액션 |
| --- | --- | --- | --- | --- |
| `Al.Init` | → | `Al.PreOp` | 1 | `[req == 2 && !err]` |
| `Al.PreOp` | → | `Al.Init` | 1 | `[req == 1]` |
| `Al.PreOp` | → | `Al.SafeOp` | 2 | `[req == 4 && !err]` |
| `Al.SafeOp` | → | `Al.Init` | 1 | `[req == 1]` |
| `Al.SafeOp` | → | `Al.PreOp` | 2 | `[req == 2 && !err]` |
| `Al.SafeOp` | → | `Al.Op` | 3 | `[req == 8 && !err]` |
| `Al.Op` | → | `Al.Init` | 1 | `[req == 1]` |
| `Al.Op` | → | `Al.PreOp` | 2 | `[req == 2 && !err]` |
| `Al.Op` | → | `Al.SafeOp` | 3 | `[req == 4 && !err]` |

같은 Source 의 전이는 `req` 값이 서로 달라 조건이 겹치지 않는다. 순서는 그래도 명시한다(Init 요청이 항상 1번).

## 5. 금지 조건

검사는 전부 `test_Esm.m` 의 F 절이 수용 시험 3개(§6) 실행의 **전 틱**(t = 0 포함)에서 스크립트로 센다.

| # | 문장 | 검사 방법 |
| --- | --- | --- |
| 1 | 모든 틱에서 `outEn == (st == 8)` — 출력 활성은 Operational 에서만, Operational 이면 반드시 | F1: `outEn ~= (st == 8)` 인 틱 수 = 0 |
| 2 | `st` 는 항상 1·2·4·8 중 하나 — 불법 코드가 상태로 들어오지 않는다 | F2: `~ismember(st, [1 2 4 8])` 인 틱 수 = 0 |
| 3 | `st` 가 바뀐 틱의 (이전 `st` → 현재 `st`) 는 허용 전이 9개 중 하나다 — Init→Safe/Op, PreOp→Op 같은 건너뜀이 없다 | F3: `st(k) ~= st(k-1)` 인 틱의 쌍이 허용 집합 밖인 수 = 0 |
| 4 | `err == 1` 인 틱에 `st` 가 바뀌었다면 현재 `st == 1` 이다 — 오류 중에는 Init 로만 움직인다 | F4: `err(k) == 1 && st(k) ~= st(k-1) && st(k) ~= 1` 인 틱 수 = 0 |
| 5 | `ack == 1` 이고 `req == 0` 인 틱의 `err` 는 0 이다 — 새 요청이 없는 해제는 반드시 먹는다 | F5: `ack == 1 && req == 0 && err == 1` 인 틱 수 = 0 |
| 6 | t = 0 의 출력은 입력과 무관하게 `st = 1 · err = 0 · outEn = 0` 이다 | F6: 3개 실행의 t = 0 행이 모두 (1, 0, 0) |

## 6. 수용 시험

공통: 고정 스텝 1 ms. 시험 입력은 t = 0 에 `req = 0 · ack = 0` 행(초기화 틱)을 앞에 붙여 k번째 틱을 t = k ms 에 넣는다. 기대는 각 틱 뒤의 출력이며 `test_Esm.m` 이 `sim` 으로 돌려 틱 단위로 대조하고 `통과 n/3` 을 출력한다.

| # | 입력 시퀀스 | 기대 |
| --- | --- | --- |
| T1 기동·하강 | 틱 1~7: `req` = 2 0 4 8 8 4 1 · `ack` = 0 0 0 0 0 0 0 | `st` = 2 2 4 8 8 4 1 · `err` = 0 0 0 0 0 0 0 · `outEn` = 0 0 0 1 1 0 0 — 허용 전이만 밟아 Op 까지 올라갔다 내려온다. 틱 5 의 `req = 8` 유지는 재트리거하지 않는다 |
| T2 불법 요청 | 틱 1~5: `req` = 8 0 0 2 0 · `ack` = 0 0 1 0 0 | `st` = 1 1 1 2 2 · `err` = 1 1 0 0 0 · `outEn` = 0 0 0 0 0 — 1→8 은 불법이라 `err = 1`·상태 유지, 틱 3 의 `ack` 가 해제, 이후 1→2 정상 |
| T3 오류 중 요청 | 틱 1~6: `req` = 2 8 4 1 2 4 · `ack` = 0 0 0 0 1 0 | `st` = 2 2 2 1 2 4 · `err` = 0 1 1 1 0 0 · `outEn` = 0 0 0 0 0 0 — 2→8 불법으로 `err = 1`, 오류 중 `req = 4` 는 무시, 오류 중 `req = 1` 은 Init 로 가되 `err` 유지, 틱 5 는 같은 틱의 `ack` 해제 뒤 1→2 가 성립, 틱 6 은 2→4 |

숨은 시험(같은 규칙으로 만든 입력 시퀀스)의 모서리 — 같은 틱의 `ack` + 요청(규칙 1 이 먼저) · 유지되는 `req`(`req == st` 면 무반응) · 연속 불법 요청(첫 것만 `err = 1`, 나머지는 무시) · 오류 중 Init 요청(`err` 를 지우지 않고 이동) · `ack` 와 같은 틱의 불법 요청(해제 뒤 다시 `err = 1`) — 는 전부 §1.3·§1.4 의 구조에서 나온다.
