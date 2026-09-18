---
type: spec
tags: [study, ethercat, stateflow, 사양표]
created: 2026-09-17
updated: 2026-09-17
---

# 사양표 — Esm
- 대상: `Esm_cur`
- 공개 출처: ETG.1000.6 AL 상태기 — Init(1) · Pre-Operational(2) · Safe-Operational(4) · Operational(8). Bootstrap(3) 은 과제 범위 밖.
- 오류 표시/해제 규칙: 과제 정의(§4 틱 규칙)가 정본. ETG 의 AL Status Code 는 다루지 않고 `err` 한 비트로 줄였다.
- 형식: 모델저작_규칙 §2 (전이표와 같은 절·표 + §0 인터페이스 · §5 금지 조건 · §6 수용 시험)
- 이름 규칙: Chart 데이터·이벤트 ≤ 8자, State ≤ 12자, Transition 라벨·State Action 한 줄 ≤ 40자.

## 0. 인터페이스

| 이름 | 방향 | 타입 | 범위/단위 | 설명 |
| --- | --- | --- | --- | --- |
| `req` | Input | uint8 | 0 · 1 · 2 · 4 · 8 (그 밖은 불법) | 요청 상태 코드. 0 = 요청 없음. 같은 값을 계속 유지해도 재트리거 없음 |
| `ack` | Input | boolean | true = 오류 해제 | 틱 처리 순서 1 — 같은 틱의 요청보다 먼저 `err` 를 지운다 |
| `st` | Output | uint8 | 1 · 2 · 4 · 8 | 현재 AL 상태 코드. 초기 1. Chart Data 초기값 1 |
| `err` | Output | boolean | 초기 false | 오류 표시. 불법 요청에 true, `ack` 에 false. 허용 전이는 건드리지 않는다 |
| `outEn` | Output | boolean | `st == 8` | 출력 활성. Operational 에서만 true |

고정 스텝 이산, 스텝 1 ms. 모델 루트 Inport `req`·`ack`, Outport `st`·`err`·`outEn`. Chart 는 `Esm_cur/Esm` 하나.

## 1. `Esm_cur/Esm`

### 1.1 Chart

| 항목 | 값 | 비고 |
| --- | --- | --- |
| Decomposition | `EXCLUSIVE_OR` | 상위 State `Al` 하나 |
| ActionLanguage | `C` | 손 변환 대상이라 C |
| ChartUpdate | `DISCRETE` | |
| SampleTime | `0.001` | 1 ms. 틱 = Chart 실행 1회 |
| ExecuteAtInitialization | `false` | 「Execute (enter) chart at initialization」 끔(기본값) — t = 0 이 초기화 틱이 된다 |

`ExecuteAtInitialization` 이 꺼져 있어야 t = 0 이 **초기화 틱**이다 — 첫 실행(t = 0)에서 default transition 으로 `Al.Init` 에 들어가고, 그 틱에는 막 들어간 State 의 outer transition 도 during 도 돌지 않으므로 입력을 보지 않는다. 켜면 초기화 시점에 이미 들어가 있어 t = 0 에 입력을 본다.

### 1.2 State 계층

| 경로 | 깊이 | 자식분해 | 실행순서 | 하위 |
| --- | --- | --- | --- | --- |
| `Al` | 0 | EXCLUSIVE_OR | 0 | 4 |
| `Al.Init` | 1 | EXCLUSIVE_OR | 0 | 0 |
| `Al.PreOp` | 1 | EXCLUSIVE_OR | 0 | 0 |
| `Al.SafeOp` | 1 | EXCLUSIVE_OR | 0 | 0 |
| `Al.Op` | 1 | EXCLUSIVE_OR | 0 | 0 |

### 1.3 State Action (원문)

**`Al`**

```
Al
during: err = err && !ack;
```

**`Al.Init`**

```
Init
entry: st = 1; outEn = false;
during:
err = err || (req != 0 && req != st);
```

**`Al.PreOp`**

```
PreOp
entry: st = 2; outEn = false;
during:
err = err || (req != 0 && req != st);
```

**`Al.SafeOp`**

```
SafeOp
entry: st = 4; outEn = false;
during:
err = err || (req != 0 && req != st);
```

**`Al.Op`**

```
Op
entry: st = 8; outEn = true;
during:
err = err || (req != 0 && req != st);
```

### 1.4 전이표

#### 1.4.1 초기 진입 (default transition 2개)

| # | 목적지 | 종류 | 도달하는 State | 조건/액션 |
| --- | --- | --- | --- | --- |
| 1 | `Al` | State | `Al` | |
| 2 | `Al.Init` | State | `Al.Init` | |

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

Junction 은 없다. 같은 Source 의 조건은 `req` 값이 서로 다르므로 동시에 참이 될 수 없다 — 순서는 「Init 으로 가는 것 1, 나머지 코드 오름차순」으로 고정했다.

## 4. 틱 규칙 · 설계 메모 (대조 대상 아님)

틱 규칙(정본) — 초기 `st = 1`, `err = 0`. t = 0 은 초기화 틱(입력 무시, `st = 1 · err = 0 · outEn = 0`). k번째 시험 입력은 t = k ms 에 들어가고 출력도 그 틱 값이다. 매 틱:

1. `ack == 1` 이면 `err = 0`.
2. 요청 — `req ≠ 0` 이고 `req ≠ st` 이면: `err == 1` 이고 `req ≠ 1` → 무시; 허용 전이면 → `st = req`; 그 밖 → `err = 1`(상태 유지). 허용 전이(ETG): 1→2 · 2→1 · 2→4 · 4→1 · 4→2 · 4→8 · 8→1 · 8→2 · 8→4. `req == st` 면 아무 일 없다.
3. `outEn = (st == 8)`.

Stateflow 실행 순서로 옮긴 방법 — 활성 State 하나는 「outer transition → during → inner transition → 활성 자식」 순서로 돈다.

- 규칙 1 은 상위 State `Al` 의 `during` 에 둔다: `err = err && !ack;` — `ack` 면 지우고 아니면 유지. `Al` 의 during 이 자식(`Al.Init` 등)보다 먼저 돌므로, 자식의 transition 과 during 은 이미 지워진 `err` 를 본다(같은 틱의 ack + 요청).
- 규칙 2 「허용 전이」는 자식 사이의 outer transition 이다. `req == 1`(Init 요청)은 `err` 와 무관하게 받고, 나머지는 `&& !err` 로 막는다(오류 중 무시). 자식의 outer transition 은 그 자식의 during 보다 먼저 평가된다.
- 규칙 2 「그 밖 → err = 1」은 자식의 `during` 이다: `err = err || (req != 0 && req != st);`. during 에 닿았다는 것은 허용 transition 이 하나도 안 잡혔다는 뜻이므로, `req ≠ 0 && req ≠ st` 면 불법 요청이거나 오류 중 무시된 허용 요청이며, 어느 쪽이든 `err` 는 1 이 된다(이미 1 이면 유지). 「연속 불법 요청」도 1 유지.
- C 액션 언어의 State Action 에 `if` 문을 쓴 첫 판은 `update` 파싱에 실패했다. 그래서 두 during 을 불리언 식 한 줄로 썼다(한 줄 ≤ 40자).
- 규칙 3 은 자식의 `entry` 다. transition 이 잡힌 틱에 목적지의 entry 가 `st`·`outEn` 을 낸다. 상태가 유지되는 틱에는 값이 그대로 남는다(Chart Output 은 유지된다).
- 같은 값의 `req` 를 유지해도 `req == st` 라 transition 조건이 거짓이고 during 의 `req != st` 도 거짓 → 재트리거 없음.
- `err` 는 `Al` 의 during(해제)과 자식의 during(표시) 두 곳에서만 쓴다. 허용 transition 은 `err` 를 건드리지 않으므로, 오류 중 `req == 1` 로 Init 에 가도 `err` 는 1 로 남는다(T3 틱 4).

## 5. 금지 조건

| # | 문장 | 검사 방법 |
| --- | --- | --- |
| F1 | `outEn` 이 true 인 틱은 `st == 8` 인 틱과 정확히 같다 | 시뮬레이션 로그 전 틱에서 `all(outEn == (st == 8))`. `test_Esm_cur.m` T1~T3 |
| F2 | `st` 는 1 · 2 · 4 · 8 밖의 값을 갖지 않는다 | 로그에서 `all(ismember(st, [1 2 4 8]))`. T1~T3 |
| F3 | `st` 의 변화는 허용 전이 9쌍 밖으로 일어나지 않는다(1→4 · 1→8 · 2→8 없음) | 로그의 연속 쌍 `(st(k-1), st(k))` 중 값이 바뀐 것이 전부 ETG 9쌍 안. T1~T3 |
| F4 | `err` 가 true 인 채로(같은 틱에 `ack` 없이) `st` 가 바뀌면 그 목적지는 1(Init) 뿐이다 — 오류 중에는 Init 요청만 받는다 | 로그에서 `err(k-1) && ~ack(k) && st(k) ~= st(k-1)` 인 k 는 전부 `st(k) == 1`. T3 틱 4 |
| F5 | 한 틱에 허용 전이와 오류 표시가 동시에 일어나지 않는다(`st` 가 바뀐 틱에 `err` 가 0→1 이 되지 않는다) | 로그에서 `diff(st) ~= 0 & diff(err) == 1` 인 틱 0개. T1~T3 |
| F6 | t = 0 출력은 입력과 무관하게 `st = 1 · err = 0 · outEn = 0` 이다 | 시험 입력의 t = 0 행 출력 대조. T1~T3 |
| F7 | Init 이 아닌 State 로 가는 transition 은 전부 `!err` 를 조건에 갖고, Init 으로 가는 transition 은 `[req == 1]` 뿐이다 | 전이표 1.4.2 검사: Destination ≠ `Al.Init` 인 9−3 = 6행에 `!err`, Destination = `Al.Init` 인 3행이 `[req == 1]` |

## 6. 수용 시험

시험 입력은 t = 0 에 0 행(초기화 틱, `req = 0 · ack = 0`)을 앞에 붙여 k번째 틱을 t = k ms 에 넣는다. 기대는 각 틱 뒤의 출력.

| # | 입력 시퀀스 | 기대 |
| --- | --- | --- |
| T1 기동·하강 | 틱 1~7 `req` = 2 0 4 8 8 4 1, `ack` = 0 0 0 0 0 0 0 | `st` = 2 2 4 8 8 4 1 · `err` = 0 0 0 0 0 0 0 · `outEn` = 0 0 0 1 1 0 0 |
| T2 불법 요청 | 틱 1~5 `req` = 8 0 0 2 0, `ack` = 0 0 1 0 0 | `st` = 1 1 1 2 2 · `err` = 1 1 0 0 0 · `outEn` = 0 0 0 0 0 |
| T3 오류 중 요청 | 틱 1~6 `req` = 2 8 4 1 2 4, `ack` = 0 0 0 0 1 0 | `st` = 2 2 2 1 2 4 · `err` = 0 1 1 1 0 0 · `outEn` = 0 0 0 0 0 0 |

모서리 — T1 틱 4·5(유지되는 `req = 8`, 재트리거 없음) · T2 틱 1·2(불법 뒤 `req = 0` 유지, `err` 유지) · T3 틱 3(오류 중 허용 요청 4 무시) · T3 틱 4(오류 중 Init 요청은 받되 `err` 유지) · T3 틱 5(같은 틱의 `ack` + 요청 2 → 해제 뒤 전이).

---
🔗 `build_Esm_cur.m`(구현) · `test_Esm_cur.m`(수용 시험) · `verify_Esm_cur.m`(update · 덤프 · 대조 · 이름 규칙) · `_덤프/사양대조.md`
