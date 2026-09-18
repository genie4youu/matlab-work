% build_Esm_ecc.m — Esm_ecc.slx 를 Stateflow API 로 처음부터 다시 만든다 (R2025b). 수동 편집 없음.
%
% 실행:
%   matlab -wait -nosplash -batch "run('C:\Users\leeyj\Documents\yj.lee\ecc\회차\2026-09-17_esm_간단_재대결\build_Esm_ecc.m')" -logfile ...\build.log
%
% 대상: EtherCAT 슬레이브 상태기(ESM) — ETG.1000.6 AL 상태기의 네 상태 Init(1)·PreOp(2)·SafeOp(4)·Op(8)
%       + 과제가 정한 오류 표시/해제 규칙. 사양은 Esm_ecc_사양.md 가 정본이다.
% 구조: 부모 State `Al` 의 during 이 규칙 1(ack → err 해제)을 자식 전이(규칙 2)보다 먼저 실행한다.
% 이름 규칙: 데이터·이벤트 ≤ 8자, State ≤ 12자, 라벨 한 줄 ≤ 40자.
% 이 스크립트는 결과 폴더(OUT) 밖에 아무것도 쓰지 않는다(slprj 는 fileGenControl 로 OUT 안).

OUT   = fileparts(mfilename('fullpath'));
MDL   = 'Esm_ecc';
CHART = 'EsmChart';
SLX   = fullfile(OUT, [MDL '.slx']);

cd(OUT);
Simulink.fileGenControl('set', 'CacheFolder', fullfile(OUT, '_검증'), 'CodeGenFolder', fullfile(OUT, '_검증'), 'createDir', true);
DIAG = fullfile(OUT, '_검증', 'build_diag_ecc.log');                          % 배치 모드의 Stateflow 파서·update 진단을 파일로
if isfile(DIAG), delete(DIAG); end                               % (diary 는 덧붙이므로 이번 실행분만 남긴다)
sldiagviewer.diary(DIAG, 'UTF-8');
fprintf('[build] %s  MATLAB %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), version);

%% 0. 기존 모델 정리 — 항상 처음부터
if bdIsLoaded(MDL), close_system(MDL, 0); end
if isfile(SLX), delete(SLX); end

new_system(MDL);
set_param(MDL, ...
    'SolverType', 'Fixed-step', 'Solver', 'FixedStepDiscrete', 'FixedStep', '0.001', ...
    'StopTime', '0.01', 'SignalLogging', 'on', 'SignalLoggingName', 'logsout');

%% 1. Chart
chBlk = [MDL '/' CHART];
add_block('sflib/Chart', chBlk, 'Position', [260 40 460 200]);
rt = sfroot;
ch = rt.find('-isa', 'Stateflow.Chart', 'Path', chBlk);
ch.ActionLanguage = 'C';
ch.ChartUpdate    = 'DISCRETE';
ch.SampleTime     = '0.001';                 % 1 ms = 한 틱
% Decomposition 은 기본 EXCLUSIVE_OR. ExecuteAtInitialization 은 기본 false 로 둔다 —
% t = 0 스텝에서 Chart 가 Al.Init 에 들어가고(초기화 틱), 그 스텝에는 전이·during 을 보지 않는다.

%% 2. 데이터 — 이름 ≤ 8자 (Inport/Outport 순서 = 생성 순서)
%      이름      범위      타입       초기값  설명
D = { 'req',    'Input',  'uint8',   '',    '요청 상태 코드. 0 = 요청 없음, 1/2/4/8 = Init/PreOp/SafeOp/Op'
      'ack',    'Input',  'boolean', '',    '오류 해제'
      'st',     'Output', 'uint8',   '1',   '현재 상태 코드 1/2/4/8'
      'err',    'Output', 'boolean', '',    '오류 표시'
      'outEn',  'Output', 'boolean', '',    '출력 활성 = (st == 8)' };
for i = 1:size(D, 1)
    d = Stateflow.Data(ch);
    d.Name        = D{i, 1};
    d.Scope       = D{i, 2};
    d.DataType    = D{i, 3};
    d.Description = D{i, 5};
    if ~isempty(D{i, 4}), d.Props.InitialValue = D{i, 4}; end
end

%% 3. 부모 State `Al` — 규칙 1 을 자식 전이보다 먼저
% (C action language 의 State Action 에는 if 문이 없다 → 불 대수로 쓴다. ack 이면 err = 0.)
al = mkState(ch, sprintf('Al\nduring:\nerr = err && !ack;'), [20 60 1040 460]);

%% 4. AL State 넷 — entry 가 st·outEn(규칙 3), during 이 불법 요청(규칙 2 의 「그 밖」)
% during 은 허용 전이가 하나도 성립하지 않았을 때만 실행된다 → 그때 req 가 0 도 st 도 아니면 불법 요청.
% err 가 이미 1 이면 그대로 1(무시).
W = 190; H = 110; y = 140;
DUR = sprintf('during:\nerr = err || (req != 0 && req != st);');
S = struct();
S.Init   = mkState(al, sprintf('Init\nentry: st = 1; outEn = 0;\n%s',   DUR), [ 60 y W H]);
S.PreOp  = mkState(al, sprintf('PreOp\nentry: st = 2; outEn = 0;\n%s',  DUR), [320 y W H]);
S.SafeOp = mkState(al, sprintf('SafeOp\nentry: st = 4; outEn = 0;\n%s', DUR), [580 y W H]);
S.Op     = mkState(al, sprintf('Op\nentry: st = 8; outEn = 1;\n%s',     DUR), [840 y W H]);

%% 5. 전이 — 허용 전이 9개(ETG). Init 요청은 오류 중에도 통과(!err 없음), 항상 1번.
%   (parent, src, dst, label, order, srcClock, dstClock, midDy)
mkTrans(al, S.Init,   S.PreOp,  '[req == 2 && !err]', 1, 2, 10,   0);   % 1→2 위쪽 직선
mkTrans(al, S.PreOp,  S.Init,   '[req == 1]',         1, 8,  4,   0);   % 2→1 아래쪽 직선
mkTrans(al, S.PreOp,  S.SafeOp, '[req == 4 && !err]', 2, 2, 10,   0);   % 2→4
mkTrans(al, S.SafeOp, S.Init,   '[req == 1]',         1, 6,  6, 100);   % 4→1 바닥 곡선
mkTrans(al, S.SafeOp, S.PreOp,  '[req == 2 && !err]', 2, 8,  4,   0);   % 4→2
mkTrans(al, S.SafeOp, S.Op,     '[req == 8 && !err]', 3, 2, 10,   0);   % 4→8
mkTrans(al, S.Op,     S.Init,   '[req == 1]',         1, 6,  6, 180);   % 8→1 가장 바깥 곡선
mkTrans(al, S.Op,     S.PreOp,  '[req == 2 && !err]', 2, 6,  6, 130);   % 8→2 바닥 곡선
mkTrans(al, S.Op,     S.SafeOp, '[req == 4 && !err]', 3, 8,  4,   0);   % 8→4

%% 6. 기본 전이 — Chart → Al, Al → Init
mkDefault(ch, al);
mkDefault(al, S.Init);

%% 7. 루트 Inport / Outport 연결 (이름·타입 고정)
inNames  = D(strcmp(D(:, 2), 'Input'),  1);  inTypes  = D(strcmp(D(:, 2), 'Input'),  3);
outNames = D(strcmp(D(:, 2), 'Output'), 1);
for i = 1:numel(inNames)
    yy = 60 + 60 * (i - 1);
    add_block('simulink/Sources/In1', [MDL '/' inNames{i}], ...
        'Position', [80 yy 110 yy+14], 'OutDataTypeStr', inTypes{i}, 'Interpolate', 'off');
    add_line(MDL, [inNames{i} '/1'], [CHART '/' num2str(i)], 'autorouting', 'on');
end
ph = get_param(chBlk, 'PortHandles');
for i = 1:numel(outNames)
    yy = 60 + 50 * (i - 1);
    add_block('simulink/Sinks/Out1', [MDL '/' outNames{i}], 'Position', [600 yy 630 yy+14]);
    add_line(MDL, [CHART '/' num2str(i)], [outNames{i} '/1'], 'autorouting', 'on');
    set_param(ph.Outport(i), 'Name', outNames{i}, 'DataLogging', 'on');
end

%% 8. 저장 + 갱신(update) 검사
save_system(MDL, SLX);
fprintf('[build] saved %s\n', SLX);
set_param(MDL, 'SimulationCommand', 'update');
fprintf('[build] update ok\n');

nS = numel(ch.find('-isa', 'Stateflow.State'));
nT = numel(ch.find('-isa', 'Stateflow.Transition'));
nD = numel(ch.find('-isa', 'Stateflow.Data'));
fprintf('[build] State %d · Transition %d (기본 전이 2 포함) · Data %d\n', nS, nT, nD);
close_system(MDL, 0);
fprintf('[build] done\n');

%% ---------------------------------------------------------------- 보조 함수
function s = mkState(parent, label, pos)
    s = Stateflow.State(parent);
    s.LabelString = label;          % 첫 줄이 이름
    s.Position    = pos;
end

function t = mkTrans(parent, src, dst, label, order, srcClock, dstClock, midDy)
    t = Stateflow.Transition(parent);
    t.Source            = src;
    t.Destination       = dst;
    t.SourceOClock      = srcClock;
    t.DestinationOClock = dstClock;
    % 곡선이 부모 State 상자 밖으로 나가면 부모를 나갔다 들어오는 전이가 된다 →
    % 직선 중점(+ 아래로 midDy)으로 상자 안에 가둔다. midDy 는 긴 하강 전이의 겹침을 피한다.
    t.MidPoint          = (t.SourceEndpoint + t.DestinationEndpoint) / 2 + [0 midDy];
    t.LabelString       = label;
    t.ExecutionOrder    = order;
end

function t = mkDefault(parent, dst)
    % 기본 전이의 시작점은 부모 상자 안에 있어야 그 부모의 기본 전이가 된다 → 위에서 내려온다
    t = Stateflow.Transition(parent);
    t.Destination       = dst;
    t.DestinationOClock = 0;
    t.SourceEndpoint    = t.DestinationEndpoint - [0 30];
    t.MidPoint          = t.DestinationEndpoint - [0 15];
end
