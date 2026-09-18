%% build_Esm_cur.m — Esm_cur.slx 를 Stateflow API 로 처음부터 다시 만든다
%
%   실행:  matlab -wait -nosplash -batch "run('<OUT>\build_Esm_cur.m')" -logfile <OUT>\build.log
%
%   정본은 Esm_cur_사양.md 다. 이 스크립트는 그 사양표를 구현하며, 수동 편집 없이
%   이 파일만으로 Esm_cur.slx 가 재생성된다. 기존 Esm_cur.slx 가 있으면 지우고 만든다.
%   결과 폴더(OUT) 밖에는 아무것도 쓰지 않는다 — slprj 캐시도 OUT\_slprj 로 보낸다.
%
%   공개 출처: ETG.1000.6 AL 상태기 — Init(1) · Pre-Operational(2) ·
%   Safe-Operational(4) · Operational(8). 오류 표시/해제 규칙은 과제 정의(사양표 §4).

OUT = fileparts(mfilename('fullpath'));
MDL = 'Esm_cur';
SLX = fullfile(OUT, [MDL '.slx']);

fprintf('\n==== build_Esm_cur ====\n');
fprintf('MATLAB %s | OUT = %s\n', version, OUT);
assert(isfolder(OUT), 'result folder not found: %s', OUT);
cd(OUT);
Simulink.fileGenControl('set', ...
    'CacheFolder',   fullfile(OUT, '_검증', '_slprj'), ...
    'CodeGenFolder', fullfile(OUT, '_검증', '_slprj'), 'createDir', true);

% ── 0. 깨끗한 시작 ──────────────────────────────────────
if bdIsLoaded(MDL), close_system(MDL, 0); end
if isfile(SLX), delete(SLX); fprintf('deleted old %s\n', SLX); end

new_system(MDL);
set_param(MDL, 'Solver', 'FixedStepDiscrete', 'FixedStep', '0.001', 'StopTime', '0.01');
load_system('sflib');
add_block('sflib/Chart', [MDL '/Esm'], 'Position', [300 60 480 200]);

rt = sfroot;
m  = rt.find('-isa', 'Simulink.BlockDiagram', '-and', 'Name', MDL);
ch = m.find('-isa', 'Stateflow.Chart', '-and', 'Name', 'Esm');
assert(numel(ch) == 1, 'chart Esm not found');

% ── 1. Chart 속성 (사양표 1.1) ───────────────────────────
ch.ActionLanguage = 'C';          % 빈 Chart 에서만 바꿀 수 있다 — 객체보다 먼저
ch.Decomposition  = 'EXCLUSIVE_OR';
ch.ChartUpdate    = 'DISCRETE';
ch.SampleTime     = '0.001';

% ── 2. Data (사양표 0. 인터페이스) — 이름 ≤ 8자 ─────────
mkdata(ch, 'req',   'Input',  'uint8',   1, '');
mkdata(ch, 'ack',   'Input',  'boolean', 2, '');
mkdata(ch, 'st',    'Output', 'uint8',   1, '1');
mkdata(ch, 'err',   'Output', 'boolean', 2, 'false');
mkdata(ch, 'outEn', 'Output', 'boolean', 3, 'false');

% ── 3. State (사양표 1.2 · 1.3) — 이름 ≤ 12자, 한 줄 ≤ 40자 ──
%   Al      : 상위 State. during 이 자식보다 먼저 돌므로 여기서 ack 를 처리한다(틱 규칙 1).
%   Al.*    : AL 상태 넷. entry 가 st·outEn 을 내고(틱 규칙 3), during 이 불법 요청을
%             잡는다(틱 규칙 2 「그 밖 → err = 1」). 허용 전이는 outer transition 이
%             during 보다 먼저 평가되므로, during 에 닿았다는 것이 곧 「허용 전이 없음」이다.
%   if 문 대신 불리언 식으로 쓴다(첫 빌드에서 if 문을 쓴 판은 update 파싱에 실패했다):
%   err = err && !ack  ·  err = err || (req != 0 && req != st)
NL = newline;
W = 280; H = 120;
%   🔴 자식 사이의 transition 이 Al 상자 밖으로 나가면 「natural parent 가 Chart」가 되어
%      전이 때마다 Al 을 나갔다 들어온다(첫 시뮬레이션에서 경고 3건, [req == 1] 셋).
%      여백을 넉넉히 주고, transition 끝점(OClock)과 MidPoint 를 직선으로 명시해 Al 안에 가둔다.
P.Al     = [20 20 1000 640];
P.Init   = [200 140 W H];
P.PreOp  = [600 140 W H];
P.SafeOp = [200 420 W H];
P.Op     = [600 420 W H];
Al = mkstate(ch, ['Al' NL 'during: err = err && !ack;'], P.Al);

illegal = ['during:' NL ...
           'err = err || (req != 0 && req != st);'];
S.Init   = mkstate(Al, ['Init'   NL 'entry: st = 1; outEn = false;' NL illegal], P.Init);
S.PreOp  = mkstate(Al, ['PreOp'  NL 'entry: st = 2; outEn = false;' NL illegal], P.PreOp);
S.SafeOp = mkstate(Al, ['SafeOp' NL 'entry: st = 4; outEn = false;' NL illegal], P.SafeOp);
S.Op     = mkstate(Al, ['Op'     NL 'entry: st = 8; outEn = true;'  NL illegal], P.Op);

% ── 4. Transition (사양표 1.4) — 만든 순서가 곧 ExecutionOrder ──
mkdefault(ch, Al,     [60 5]);       % Chart → Al
mkdefault(Al, S.Init, [340 90]);     % Al → Al.Init  (초기 st = 1)

% 허용 전이(ETG): 1→2 · 2→1 · 2→4 · 4→1 · 4→2 · 4→8 · 8→1 · 8→2 · 8→4
% req == 1 은 err 와 무관하게 받는다(오류 중 Init 요청). 그 밖은 !err 일 때만.
% OClock: 12 위 중앙 · 3 오른쪽 중앙 · 6 아래 중앙 · 9 왼쪽 중앙 (1.5·4.5·7.5·10.5 는 모서리)
T = {};   % {src, dst, label, order, srcClock, dstClock}
T(end+1,:) = {'Init',   'PreOp',  '[req == 2 && !err]', 1,  2.25,  9.75};
T(end+1,:) = {'PreOp',  'Init',   '[req == 1]',         1,  8.25,  3.75};
T(end+1,:) = {'PreOp',  'SafeOp', '[req == 4 && !err]', 2,  6.9,   0.9};
T(end+1,:) = {'SafeOp', 'Init',   '[req == 1]',         1, 11.25,  6.75};
T(end+1,:) = {'SafeOp', 'PreOp',  '[req == 2 && !err]', 2,  1.2,   7.2};
T(end+1,:) = {'SafeOp', 'Op',     '[req == 8 && !err]', 3,  2.25,  9.75};
T(end+1,:) = {'Op',     'Init',   '[req == 1]',         1, 10.2,   4.8};
T(end+1,:) = {'Op',     'PreOp',  '[req == 2 && !err]', 2,  0.75,  5.25};
T(end+1,:) = {'Op',     'SafeOp', '[req == 4 && !err]', 3,  8.25,  3.75};

tr = cell(size(T,1),1);
for k = 1:size(T,1)
    tr{k} = mktrans(Al, S.(T{k,1}), S.(T{k,2}), T{k,3});
    tr{k}.SourceOClock      = T{k,5};
    tr{k}.DestinationOClock = T{k,6};
    a = clockxy(P.(T{k,1}), T{k,5});
    b = clockxy(P.(T{k,2}), T{k,6});
    tr{k}.MidPoint = (a + b) / 2;    % 직선 — Al 밖으로 부풀지 않는다
end
for k = 1:size(T,1)              % 전부 만든 뒤 순서를 명시한다
    if tr{k}.ExecutionOrder ~= T{k,4}, tr{k}.ExecutionOrder = T{k,4}; end
end

% ── 5. Simulink 포트 배선 ────────────────────────────────
inSpec  = {'req','uint8'; 'ack','boolean'};
outSpec = {'st'; 'err'; 'outEn'};
for k = 1:size(inSpec,1)
    y = 80 + 60*(k-1);
    add_block('built-in/Inport', [MDL '/' inSpec{k,1}], 'Position', [120 y 150 y+14], ...
              'Port', num2str(k), 'OutDataTypeStr', inSpec{k,2}, 'Interpolate', 'off');
    add_line(MDL, [inSpec{k,1} '/1'], ['Esm/' num2str(k)], 'autorouting', 'smart');
end
for k = 1:numel(outSpec)
    y = 80 + 50*(k-1);
    add_block('built-in/Outport', [MDL '/' outSpec{k}], 'Position', [620 y 650 y+14], ...
              'Port', num2str(k));
    h = add_line(MDL, ['Esm/' num2str(k)], [outSpec{k} '/1'], 'autorouting', 'smart');
    set_param(h, 'Name', outSpec{k});   % 로깅 Dataset 요소 이름 = 출력 이름 (없으면 '' 라 포트 번호로만 찾힌다)
end

% ── 6. 저장 ──────────────────────────────────────────────
save_system(MDL, SLX);
nS = numel(ch.find('-isa','Stateflow.State'));
nT = numel(ch.find('-isa','Stateflow.Transition'));
nJ = numel(ch.find('-isa','Stateflow.Junction'));
nD = numel(ch.find('-isa','Stateflow.Data'));
fprintf('saved %s\n  State %d  Transition %d  Junction %d  Data %d\n', SLX, nS, nT, nJ, nD);
close_system(MDL, 0);
fprintf('==== build_Esm_cur done ====\n');

% ══════════════════════════════════════════════════════════
function d = mkdata(ch, name, scope, type, port, init)
    d = Stateflow.Data(ch);
    d.Name = name; d.Scope = scope; d.DataType = type;
    if ~isempty(port), d.Port = port; end
    if ~isempty(init), d.Props.InitialValue = init; end
end

function s = mkstate(parent, label, pos)
    s = Stateflow.State(parent);
    s.Position = pos;            % 부모 상자 안에 먼저 놓고
    s.LabelString = label;       % 첫 줄이 이름
end

function t = mkdefault(parent, dst, srcPt)
    t = Stateflow.Transition(parent);
    t.Destination = dst;
    t.SourceEndPoint = srcPt;
end

function t = mktrans(parent, src, dst, label)
    t = Stateflow.Transition(parent);
    t.Source = src;
    t.Destination = dst;
    if ~isempty(label), t.LabelString = label; end
end

function xy = clockxy(pos, c)
%CLOCKXY  State 상자 [x y w h] 둘레의 OClock 위치 c(0~12) 를 좌표로. 12 위 중앙에서 시계 방향.
    x = pos(1); y = pos(2); w = pos(3); h = pos(4);
    c = mod(c, 12);
    if     c < 1.5,  xy = [x + w/2 + (c/1.5)*(w/2),          y];
    elseif c < 4.5,  xy = [x + w,                            y + ((c-1.5)/3)*h];
    elseif c < 7.5,  xy = [x + w - ((c-4.5)/3)*w,            y + h];
    elseif c < 10.5, xy = [x,                                y + h - ((c-7.5)/3)*h];
    else,            xy = [x + ((c-10.5)/1.5)*(w/2),         y];
    end
end
