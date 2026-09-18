%% build_Esm.m — Esm.slx 를 Stateflow API 로 처음부터 다시 만든다 (MATLAB R2025b)
%
%   실행:  matlab -wait -nosplash -batch "run('<OUT>\build_Esm.m')" -logfile <OUT>\build.log
%   이 스크립트 하나로 재생성된다(수동 편집 없음). 있던 Esm.slx 는 지우고 새로 만든다.
%   결과 폴더(OUT) 밖에는 아무것도 쓰지 않는다 — Simulink 캐시(slprj)도 OUT\_slprj 로 돌린다.
%
%   대상  : EtherCAT 슬레이브 AL 상태기(ETG.1000.6) 네 상태 Init(1)·PreOp(2)·SafeOp(4)·Op(8)
%           + 이 과제가 정한 오류 표시(err)/해제(ack) 규칙. 정본은 Esm_사양.md
%   틱 순서(정본): ① ack → err=0   ② 요청: 허용 전이면 st=req, 그 밖(req≠0·req≠st)이면 err=1,
%                  err 중에는 req==1 만 받는다   ③ outEn = (st == 8)
%   Stateflow 실행 순서로 옮긴 것:
%     · 부모 State `Al` 의 during(① err = err && !ack) 은 자식보다 먼저 실행된다.
%     · 자식 State 의 outgoing 전이(② 허용 전이) 가 하나도 안 잡히면 그 자식의 during
%       (② 그 밖 → err = err || (req != 0 && req != 자기코드)). err 중 무시되는 요청도 여기 잡히지만
%       err 는 이미 1 이라 관측이 같다.
%     · outEn 은 Op 의 entry(true)/exit(false) 에서만 바뀐다(③).
%     · t = 0 은 default 전이로 Al.Init 에 들어가는 스텝 — during·전이가 돌지 않으므로 입력을 보지 않는다.
%     · C 액션 언어는 State Action 안의 if { } 를 받지 않는다(1차 실행에서 Syntax error) — 그래서 불리언 식.
%   이름 규칙: 데이터·이벤트 ≤ 8자 · State ≤ 12자 · 라벨 한 줄 ≤ 40자

OUT = fileparts(mfilename('fullpath'));
MDL = 'Esm';
SLX = fullfile(OUT, [MDL '.slx']);
TS  = '0.001';                                   % 1 ms 고정 스텝

fprintf('\n==== build_Esm — MATLAB %s ====\n', version);
assert(isfolder(OUT), 'result folder not found: %s', OUT);
cd(OUT);
Simulink.fileGenControl('set', ...
    'CacheFolder',   fullfile(OUT, '_slprj'), ...
    'CodeGenFolder', fullfile(OUT, '_slprj'), 'createDir', true);

if bdIsLoaded(MDL), close_system(MDL, 0); end
if isfile(SLX), delete(SLX); fprintf('  old Esm.slx deleted\n'); end

% ── 1. 모델 + Chart 블록 ──────────────────────────────────────────────
new_system(MDL);
set_param(MDL, 'SolverType', 'Fixed-step', 'Solver', 'FixedStepDiscrete', ...
               'FixedStep', TS, 'StopTime', '0.010', ...
               'SaveFormat', 'Dataset', 'SaveOutput', 'on', 'SaveTime', 'on');
load_system('sflib');
add_block('sflib/Chart', [MDL '/' MDL], 'Position', [300 60 480 220]);

rt = sfroot;
ch = rt.find('-isa', 'Stateflow.Chart', 'Path', [MDL '/' MDL]);
assert(numel(ch) == 1, 'chart %s/%s not found', MDL, MDL);
ch.ActionLanguage = 'C';
ch.ChartUpdate    = 'DISCRETE';
ch.SampleTime     = TS;
ch.Decomposition  = 'EXCLUSIVE_OR';              % 최상위 State 는 Al 하나

% ── 2. 데이터 (포트 번호 = 만든 순서) ────────────────────────────────
D(ch, 'req',   'Input',  'uint8');               % 1  요청 상태 코드. 0 = 요청 없음
D(ch, 'ack',   'Input',  'boolean');             % 2  오류 해제
D(ch, 'st',    'Output', 'uint8');               % 1  현재 상태 코드 1·2·4·8
D(ch, 'err',   'Output', 'boolean');             % 2  오류 표시
D(ch, 'outEn', 'Output', 'boolean');             % 3  출력 활성 = (st == 8)

% ── 3. State ─────────────────────────────────────────────────────────
% Al 은 우회 호(MidPoint 최대 x ≈ 640)가 넉넉히 들어가게 넓힌다 — 호가 경계에 닿으면 Stateflow 가
% 그 전이를 Chart 층으로 재부모화해 Al.find 에서 빠진다(2차 실행에서 실제로 났다)
Al = S(ch, sprintf('Al\nduring:\nerr = err && !ack;'), [40 40 800 620]);

names = {'Init', 'PreOp', 'SafeOp', 'Op'};
codes = [1 2 4 8];
SX = 250; SW = 270; SY = [80 220 360 500]; SH = [90 90 90 110];
S_ = struct();
for k = 1:4
    lines = {names{k}, sprintf('entry: st = %d;', codes(k)), 'during:', ...
             sprintf('err = err || (req != 0 && req != %d);', codes(k))};
    if codes(k) == 8
        lines{2} = 'entry: st = 8; outEn = true;';
        lines{end+1} = 'exit: outEn = false;';                       %#ok<SAGROW>
    end
    S_.(names{k}) = S(Al, strjoin(lines, newline), [SX SY(k) SW SH(k)]);
end

% ── 4. 전이 — 같은 Source 안에서는 적은 순서가 실행순서 ───────────────
%   허용 전이(ETG): 1→2 · 2→1 · 2→4 · 4→1 · 4→2 · 4→8 · 8→1 · 8→2 · 8→4
%   → Init 요청은 err 와 무관, 그 밖의 허용 전이는 !err 일 때만
TR = { ...
 'Init',   'PreOp',  '[req == 2 && !err]';
 'PreOp',  'Init',   '[req == 1]';
 'PreOp',  'SafeOp', '[req == 4 && !err]';
 'SafeOp', 'Init',   '[req == 1]';
 'SafeOp', 'PreOp',  '[req == 2 && !err]';
 'SafeOp', 'Op',     '[req == 8 && !err]';
 'Op',     'Init',   '[req == 1]';
 'Op',     'PreOp',  '[req == 2 && !err]';
 'Op',     'SafeOp', '[req == 4 && !err]';
};
tr = cell(1, size(TR, 1));
for r = 1:size(TR, 1)
    i = find(strcmp(names, TR{r,1}));  j = find(strcmp(names, TR{r,2}));
    src = S_.(TR{r,1});  dst = S_.(TR{r,2});
    sp = src.Position;   dp = dst.Position;
    if j == i + 1                                   % 한 단 아래로(상승) — 왼쪽 세로선
        so = 7;  do = 11;  mp = [];
        lp = [sp(1) - 170, sp(2) + sp(4) + 12];
    elseif j == i - 1                               % 한 단 위로(하강 1단) — 오른쪽 세로선
        so = 1;  do = 5;   mp = [];
        lp = [sp(1) + sp(3)*2/3 + 8, sp(2) - 32];
    else                                            % 두 단 이상 위로 — 오른쪽 바깥으로 우회
        so = 3;  do = 3;
        bulge = 70 + 50*(i - j - 1);
        mp = [sp(1) + sp(3) + bulge, (sp(2) + sp(4)/2 + dp(2) + dp(4)/2)/2];
        lp = [mp(1) + 6, mp(2) - 8];
    end
    tr{r} = T(Al, src, dst, TR{r,3}, so, do, mp, lp);
end
DT(ch, Al);
DT(Al, S_.Init);

% 실행순서 확인 — 같은 Source 의 전이는 표에 적은 순서대로 1, 2, 3 이어야 한다
allT = Al.find('-isa', 'Stateflow.Transition');
for k = 1:numel(allT)
    t = allT(k);
    sn = '(default)'; if ~isempty(t.Source), sn = t.Source.Name; end
    fprintf('  T%-2d %-9s -> %-7s [%d] %s\n', k, sn, t.Destination.Name, t.ExecutionOrder, t.LabelString);
end
for r = 1:numel(names)
    src  = S_.(names{r});
    want = find(strcmp(TR(:,1), names{r}));
    for q = 1:numel(want)
        t = tr{want(q)};
        if t.ExecutionOrder ~= q, t.ExecutionOrder = q; end
    end
    nOut = sum(arrayfun(@(t) ~isempty(t.Source) && t.Source == src, allT));
    assert(nOut == numel(want), 'outgoing count mismatch at %s (Al 안에서 %d개 — 전이가 Al 밖으로 재부모화됐나)', names{r}, nOut);
end
assert(numel(allT) == size(TR, 1) + 1, 'Al 안의 전이 수 %d ≠ %d', numel(allT), size(TR, 1) + 1);

% ── 5. 루트 입출력 ───────────────────────────────────────────────────
ins  = {'req', 'ack'};  inT = {'uint8', 'boolean'};
outs = {'st', 'err', 'outEn'};
for k = 1:numel(ins)
    add_block('simulink/Sources/In1', [MDL '/' ins{k}], 'Position', [60 40+60*k 90 54+60*k], ...
              'OutDataTypeStr', inT{k}, 'Port', num2str(k), 'Interpolate', 'off');
    h = add_line(MDL, [ins{k} '/1'], [MDL '/' num2str(k)]);
    set_param(h, 'Name', ins{k});
end
for k = 1:numel(outs)
    add_block('simulink/Sinks/Out1', [MDL '/' outs{k}], 'Position', [700 40+50*k 730 54+50*k], ...
              'Port', num2str(k));
    h = add_line(MDL, [MDL '/' num2str(k)], [outs{k} '/1']);
    set_param(h, 'Name', outs{k});
end
Simulink.BlockDiagram.arrangeSystem(MDL);

% ── 6. 이름 규칙 자체 점검 (만든 직후) ───────────────────────────────
allS = ch.find('-isa', 'Stateflow.State');
allD = ch.find('-isa', 'Stateflow.Data');
allE = ch.find('-isa', 'Stateflow.Event');
allT = ch.find('-isa', 'Stateflow.Transition');
sLen = arrayfun(@(s) strlength(s.Name), allS);
dLen = [arrayfun(@(d) strlength(d.Name), allD); arrayfun(@(e) strlength(e.Name), allE)];
L = {};
for k = 1:numel(allS), L = [L; cellstr(splitlines(string(allS(k).LabelString)))]; end   %#ok<AGROW>
for k = 1:numel(allT), L = [L; cellstr(splitlines(string(allT(k).LabelString)))]; end   %#ok<AGROW>
lLen = cellfun(@strlength, L);
assert(all(sLen <= 12), 'State 이름 12자 초과');
assert(all(dLen <= 8),  '데이터·이벤트 이름 8자 초과');
assert(all(lLen <= 40), '라벨 한 줄 40자 초과');
fprintf('  이름 규칙: State 최대 %d · 데이터/이벤트 최대 %d · 라벨 한 줄 최대 %d\n', max(sLen), max(dLen), max(lLen));

% ── 7. 저장 + 요약 ───────────────────────────────────────────────────
save_system(MDL, SLX);
nDef = sum(arrayfun(@(t) isempty(t.Source), allT));
fprintf('  saved %s\n', SLX);
fprintf('  State %d · Transition %d (default %d) · Data %d\n', numel(allS), numel(allT), nDef, numel(allD));
fprintf('==== build_Esm done ====\n');

% ══════════════════════════════════════════════════════════════════════
function d = D(ch, name, scope, type)
    d = Stateflow.Data(ch);
    d.Name = name;  d.Scope = scope;  d.DataType = type;
end

function s = S(parent, label, pos)
    s = Stateflow.State(parent);
    s.LabelString = label;
    s.Position    = pos;
end

function t = T(parent, src, dst, label, so, do, mp, lp)
    t = Stateflow.Transition(parent);
    t.Source = src;  t.Destination = dst;
    t.SourceOClock = so;  t.DestinationOClock = do;
    if ~isempty(mp), t.MidPoint = mp; end
    t.LabelString = label;
    p = t.LabelPosition;  p(1:2) = lp;  t.LabelPosition = p;
end

function t = DT(parent, dst)
    t = Stateflow.Transition(parent);
    t.Destination = dst;  t.DestinationOClock = 0;
    t.SourceEndpoint = t.DestinationEndpoint - [0 30];
    t.MidPoint       = t.DestinationEndpoint - [0 15];
end
