# 사양표 — Esm

- 대상: `Esm`
- 형식: [[work/knowledge/볼트운영/모델저작_규칙]] §2 — `emit_transtable` 의 전이표와 같은 절·표 + 사양 전용 절(§0 인터페이스 · §5 금지 조건 · §6 수용 시험)
- 출처: ETG.1000.6 AL 상태기의 네 상태 Init(1) · Pre-Operational(2) · Safe-Operational(4) · Operational(8) 와 허용 전이 1→2 · 2→1 · 2→4 · 4→1 · 4→2 · 4→8 · 8→1 · 8→2 · 8→4. 오류 표시(`err`)/해제(`ack`) 규칙은 이 과제(2026-09-17)가 정한 것이다
- 모델 밖: Bootstrap(3) · AL Status Code · 상태별 SM/PDO 설정 검사 — 요청 코드의 합법성만 본다

> 🔴 Private. 이 표가 **정본**이고 `Esm.slx` 는 구현이다. 어긋나면 모델이 틀린 것. 표 칸 안의 `|` 는 `\|` 로 쓴다.

## 0. 인터페이스

| 이름 | 방향 | 타입 | 범위/단위 | 설명 |
| --- | --- | --- | --- | --- |
| `req` | 입력 | uint8 | 0 = 요청 없음, 그 외 = 요청 상태 코드(정상은 1·2·4·8) | 매 틱 읽는다. `req == st` 면 아무 일 없다(유지해도 재트리거 없음) |
| `ack` | 입력 | boolean | true = 오류 해제 | 매 틱 읽는다. 같은 틱의 요청보다 **먼저** 처리된다 |
| `st` | 출력 | uint8 | {1, 2, 4, 8} = Init · PreOp · SafeOp · Op | 현재 상태 코드. t = 0 에 1. 허용 전이에서만 바뀐다 |
| `err` | 출력 | boolean | | 오류 표시. 불법 요청(허용 전이 아님) 에서 true, `ack` 로만 false |
| `outEn` | 출력 | boolean | | 출력 활성 = (`st == 8`). Op 진입 true · 이탈 false |

### 0.1 틱 규칙 (정본) — 매 틱 이 순서

- t = 0 은 초기화 틱: 입력을 보지 않고 `st = 1 · err = 0 · outEn = 0` (default 전이로 `Al.Init` 에 들어가는 스텝). k번째 시험 입력은 t = k ms.
- ① `ack == 1` 이면 `err = 0`.
- ② `req ≠ 0` 이고 `req ≠ st` 이면: `err == 1` 이고 `req ≠ 1` → 무시 · 허용 전이면 `st = req` · 그 밖 → `err = 1`(상태 유지).
- ③ `outEn = (st == 8)`.
- Stateflow 로 옮긴 순서: 부모 `Al` 의 `during`(① `err = err && !ack;`) → 자식의 outgoing 전이(② 허용 전이 9개 = 전이표 전부) → 전이가 없으면 자식의 `during`(② 그 밖 → `err = err || (req != 0 && req != 자기코드);` — err 중 무시되는 요청도 여기 잡히나 err 는 이미 1 이라 관측이 같다) → `outEn` 은 `Op` 의 entry/exit(③).
- C 액션 언어는 State Action 안의 `if { }` 를 받지 않으므로(Syntax error) 분기는 전부 불리언 식이다.

## 1. `Esm/Esm`

### 1.1 Chart

| 항목 | 값 | C 로 옮길 때 |
| --- | --- | --- |
| Decomposition | `EXCLUSIVE_OR` | 최상위 State 는 `Al` 하나 |
| ActionLanguage | `C` | |
| SampleTime | `0.001` | 1 ms 고정 스텝. 모델 solver 도 FixedStepDiscrete 0.001 |
| StatesWhenEnabling | `held` | |

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
entry: st = 1;
during:
err = err || (req != 0 && req != 1);
```

**`Al.Op`**

```
Op
entry: st = 8; outEn = true;
during:
err = err || (req != 0 && req != 8);
exit: outEn = false;
```

**`Al.PreOp`**

```
PreOp
entry: st = 2;
during:
err = err || (req != 0 && req != 2);
```

**`Al.SafeOp`**

```
SafeOp
entry: st = 4;
during:
err = err || (req != 0 && req != 4);
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
| `Al.Op` | → | `Al.Init` | 1 | `[req == 1]` |
| `Al.Op` | → | `Al.PreOp` | 2 | `[req == 2 && !err]` |
| `Al.Op` | → | `Al.SafeOp` | 3 | `[req == 4 && !err]` |
| `Al.PreOp` | → | `Al.Init` | 1 | `[req == 1]` |
| `Al.PreOp` | → | `Al.SafeOp` | 2 | `[req == 4 && !err]` |
| `Al.SafeOp` | → | `Al.Init` | 1 | `[req == 1]` |
| `Al.SafeOp` | → | `Al.PreOp` | 2 | `[req == 2 && !err]` |
| `Al.SafeOp` | → | `Al.Op` | 3 | `[req == 8 && !err]` |

## 5. 금지 조건

| # | 문장 | 검사 방법 |
| --- | --- | --- |
| F1 | 모든 틱에서 `outEn == (st == 8)` 이다(출력 활성은 Op 에서만, Op 면 반드시) | 시뮬레이션 궤적 전부에서 `all(outEn == (st == 8))` |
| F2 | `st` 는 {1, 2, 4, 8} 만 가지며, 인접 틱의 변화는 허용 전이 집합 {1→2, 2→1, 2→4, 4→1, 4→2, 4→8, 8→1, 8→2, 8→4} 안에만 있다(1→4 · 1→8 · 2→8 없음) | 궤적의 인접 값 쌍(다른 것만)을 허용 집합과 비교 |
| F3 | 오류 중(`err(k-1) == 1`)이고 그 틱에 `ack == 0` 이면 `st` 는 1 로만 바뀔 수 있다(오류 중에는 Init 요청만 받는다) | 궤적에서 `err(k-1) & ~ack(k) & st(k) ~= st(k-1)` 인 k 는 전부 `st(k) == 1` |
| F4 | `err` 가 1→0 이 되는 틱은 반드시 `ack == 1` 이다(오류는 ack 로만 풀린다) | 궤적에서 `err(k-1) & ~err(k)` 인 k 는 전부 `ack(k) == 1` |
| F5 | `Al.Init` 으로 가는 전이의 라벨은 전부 `[req == 1]`(err 무관), 그 밖의 전이는 전부 `!err` 를 포함한다 | 덤프 `edges.json` 에서 `dst == 'Al.Init'` 인 전이의 라벨 집합 == {`[req == 1]`}, 나머지 전이는 `contains(label, '!err')` |
| F6 | `req == 0` 인 틱에는 `st` 가 바뀌지 않고 `err` 가 0→1 이 되지 않는다(요청 없음은 아무 일 없음) | 궤적에서 `req(k) == 0` 인 k(k ≥ 1)는 전부 `st(k) == st(k-1)` 이고 `~(err(k) & ~err(k-1))` |

## 6. 수용 시험

> 각 틱 뒤의 기대 출력. k번째 틱은 t = k ms 에 넣고 그 틱의 출력은 t = k ms 값이다. t = 0 은 `st = 1 · err = 0 · outEn = 0`. `test_Esm.m` 이 `sim` 으로 돌려 틱 단위로 대조하고 `통과 n/3` 을 낸다.

| # | 입력 시퀀스 | 기대 출력/State |
| --- | --- | --- |
| T1 기동·하강 | 틱 1~7: `req` = 2 0 4 8 8 4 1 · `ack` = 0 0 0 0 0 0 0 | `st` = 2 2 4 8 8 4 1 · `err` = 0 0 0 0 0 0 0 · `outEn` = 0 0 0 1 1 0 0 (유지되는 req 8 은 재트리거 없음) |
| T2 불법 요청 | 틱 1~5: `req` = 8 0 0 2 0 · `ack` = 0 0 1 0 0 | `st` = 1 1 1 2 2 · `err` = 1 1 0 0 0 · `outEn` = 0 0 0 0 0 (1→8 불법 → err, ack 로 해제, 1→2 허용) |
| T3 오류 중 요청 | 틱 1~6: `req` = 2 8 4 1 2 4 · `ack` = 0 0 0 0 1 0 | `st` = 2 2 2 1 2 4 · `err` = 0 1 1 1 0 0 · `outEn` = 0 0 0 0 0 0 (2→8 불법 → err, 오류 중 4 는 무시, 오류 중 1 은 받음, 같은 틱의 ack+req 2 는 ack 먼저) |
