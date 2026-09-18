%% verify_Esm.m — Esm.slx 의 완료 조건을 기계로 잰다 (update · 덤프 · 전이표 · 사양 대조 · 이름 규칙)
%
%   실행:  build_Esm.m 다음에.
%          matlab -wait -nosplash -batch "run('<OUT>\verify_Esm.m')" -logfile <OUT>\verify.log
%
%   [1] Esm.slx 열기 + set_param(...,'SimulationCommand','update')
%   [2] emit_dump → emit_transtable → compare_spec(Esm_사양.md)   (하네스 _shared\harness + build)
%   [3] 이름 규칙 — 덤프 JSON 에서 State ≤ 12 · 데이터/이벤트 ≤ 8 · 라벨 한 줄 ≤ 40
%   결과: _덤프\검증수치.md  (수치는 전부 이 스크립트가 센 값)
%   결과 폴더(OUT) 밖에는 아무것도 쓰지 않는다.

OUT  = fileparts(mfilename('fullpath'));
HARN = 'C:\Users\leeyj\matlab-work\_shared\harness';
MDL  = 'Esm';
SLX  = fullfile(OUT, [MDL '.slx']);
DUMP = fullfile(OUT, '_덤프');
SPEC = fullfile(OUT, 'Esm_사양.md');

fprintf('\n==== verify_Esm ====\n');
assert(isfolder(OUT), 'result folder not found: %s', OUT);
assert(isfolder(HARN), 'harness not found: %s', HARN);
assert(isfile(SLX), 'Esm.slx not found — run build_Esm.m first');
cd(OUT);
addpath(HARN, fullfile(HARN, 'build'));
Simulink.fileGenControl('set', ...
    'CacheFolder',   fullfile(OUT, '_slprj'), ...
    'CodeGenFolder', fullfile(OUT, '_slprj'), 'createDir', true);

R = struct();
R.matlab = version;
R.when   = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

% ── [1] 열기 + update ────────────────────────────────────
if bdIsLoaded(MDL), close_system(MDL, 0); end
load_system(SLX);
try
    set_param(MDL, 'SimulationCommand', 'update');
    R.update = 'ok';
catch e
    R.update = ['ERROR: ' strrep(e.message, newline, ' / ')];
    % 배치 모드에는 Diagnostic Viewer 가 없다 — 원인 예외를 전부 찍는다
    fprintf('  update 실패 상세:\n%s\n', getReport(e, 'extended', 'hyperlinks', 'off'));
    for q = 1:numel(e.cause)
        fprintf('  cause %d: %s\n', q, strrep(e.cause{q}.message, newline, ' / '));
    end
end
fprintf('[1] update: %s\n', R.update);

% ── [2] 덤프 · 전이표 · 사양 대조 ───────────────────────
meta = emit_dump(MDL, DUMP);
emit_transtable(DUMP);
rep  = compare_spec(SPEC, DUMP);
R.compare = struct('total', rep.total, 'ok', rep.ok, ...
                   'missingCharts', numel(rep.missingCharts), 'extraCharts', numel(rep.extraCharts));
if ~isempty(rep.chart)
    r = rep.chart(1);
    R.compare.chart           = r.chart;
    R.compare.nStateSpec      = r.nStateSpec;   R.compare.nStateDump = r.nStateDump;
    R.compare.nTransSpec      = r.nTransSpec;   R.compare.nTransDump = r.nTransDump;
    R.compare.nDefSpec        = r.nDefSpec;     R.compare.nDefDump   = r.nDefDump;
    R.compare.missingStates   = numel(r.missingStates);
    R.compare.extraStates     = numel(r.extraStates);
    R.compare.stateMismatch   = size(r.stateMismatch, 1);
    R.compare.missingTrans    = numel(r.missingTrans);
    R.compare.extraTrans      = numel(r.extraTrans);
    R.compare.missingDefaults = numel(r.missingDefaults);
    R.compare.extraDefaults   = numel(r.extraDefaults);
    R.compare.propMismatch    = size(r.propMismatch, 1);
    R.compare.junctionSpec    = r.junctionSpec;  R.compare.junctionDump = r.junctionDump;
end
fprintf('[2] compare_spec total = %d (%s)\n', rep.total, ternary(rep.ok, 'PASS', 'FAIL'));

% ── [3] 이름 규칙 — 덤프 JSON 에서 센다 ─────────────────
nodes  = readjson(fullfile(DUMP, 'nodes.json'));
edges  = readjson(fullfile(DUMP, 'edges.json'));
charts = readjson(fullfile(DUMP, 'charts.json'));
st  = nodes(strcmp({nodes.kind}, 'State'));
ch1 = charts(1);

stateNames = {st.name};
[R.names.stateMax, i] = max(cellfun(@strlength, stateNames));
R.names.stateMaxName = stateNames{i};
R.names.nStates = numel(stateNames);

dataNames = {}; dataScopes = {};
if ~isempty(ch1.data), dataNames = {ch1.data.name}; dataScopes = {ch1.data.scope}; end
evNames = {};
if isfield(ch1, 'events') && ~isempty(ch1.events), evNames = {ch1.events.name}; end
allDE = [dataNames, evNames];
[R.names.dataMax, i] = max(cellfun(@strlength, allDE));
R.names.dataMaxName = allDE{i};
R.names.nData  = numel(dataNames);
R.names.nEvent = numel(evNames);
R.names.data   = strjoin(cellfun(@(n, s) sprintf('%s(%s)', n, s), dataNames, dataScopes, 'UniformOutput', false), ' ');

L = {}; where = {};
for k = 1:numel(st)
    ls = splitlines(string(st(k).label));
    for q = 1:numel(ls), L{end+1} = char(ls(q)); where{end+1} = ['State ' st(k).path]; end %#ok<SAGROW>
end
for k = 1:numel(edges)
    ls = splitlines(string(edges(k).label));
    for q = 1:numel(ls), L{end+1} = char(ls(q)); where{end+1} = ['Trans ' edges(k).src ' -> ' edges(k).dst]; end %#ok<SAGROW>
end
lens = cellfun(@strlength, L);
[R.names.lineMax, i] = max(lens);
R.names.lineMaxText  = L{i};
R.names.lineMaxWhere = where{i};
R.names.nLines       = numel(L);
R.names.nLinesOver40 = sum(lens > 40);
R.names.rule = struct('state_le_12', R.names.stateMax <= 12, 'data_le_8', R.names.dataMax <= 8, ...
                      'line_le_40', R.names.lineMax <= 40);
fprintf('[3] State max %d (%s) | Data/Event max %d (%s) | line max %d (%s)\n', ...
    R.names.stateMax, R.names.stateMaxName, R.names.dataMax, R.names.dataMaxName, ...
    R.names.lineMax, R.names.lineMaxWhere);

% ── [4] 결과 파일 ────────────────────────────────────────
isDef = logical([edges.isDefault]);
R.struct = struct('nStates', numel(st), 'nJunctions', sum(strcmp({nodes.kind}, 'Junction')), ...
                  'nTrans', sum(~isDef), 'nDefaults', sum(isDef));
mf = fullfile(DUMP, '검증수치.md');
writemd(mf, R, meta);
fprintf('  → %s\n', mf);
close_system(MDL, 0);
fprintf('==== verify_Esm done: update=%s compare=%d names=%d/%d/%d ====\n', R.update, R.compare.total, ...
    R.names.rule.state_le_12, R.names.rule.data_le_8, R.names.rule.line_le_40);

% ══════════════════════════════════════════════════════════
function S = readjson(p)
    d = jsondecode(fileread(p));
    if iscell(d), d = [d{:}]; end
    S = reshape(d, 1, []);
end

function v = ternary(c, a, b)
    if c, v = a; else, v = b; end
end

function writemd(mf, R, meta)
    fid = fopen(mf, 'w', 'n', 'UTF-8'); oc = onCleanup(@() fclose(fid)); %#ok<NASGU>
    p = @(varargin) fprintf(fid, varargin{:});
    p('# 검증 수치 — verify_Esm.m 이 센 값\n\n');
    p('- 생성: %s · MATLAB %s\n- 모델: `Esm.slx`\n- 덤프 수집: %s\n\n', R.when, R.matlab, meta.collected);
    p('> 🔴 이 파일의 수는 전부 스크립트가 센 것이다. 수용 시험 결과는 `test_Esm.m` 의 출력(실행 로그 `build.log` 의 `==== test_Esm ====` 절)이 정본이다.\n\n');
    p('## 1. 열기 + update\n\n- `set_param(''Esm'',''SimulationCommand'',''update'')` → **%s**\n\n', R.update);
    p('## 2. compare_spec\n\n| 항목 | 값 |\n| --- | --- |\n');
    p('| 합계(total) | **%d** → %s |\n', R.compare.total, ternary(R.compare.ok, '통과', '실패'));
    if isfield(R.compare, 'chart')
        p('| Chart | `%s` |\n', R.compare.chart);
        p('| State 사양/덤프 | %d/%d (빠짐 %d · 남음 %d · 불일치 %d) |\n', R.compare.nStateSpec, R.compare.nStateDump, R.compare.missingStates, R.compare.extraStates, R.compare.stateMismatch);
        p('| 전이 사양/덤프 | %d/%d (빠짐 %d · 남음 %d) |\n', R.compare.nTransSpec, R.compare.nTransDump, R.compare.missingTrans, R.compare.extraTrans);
        p('| default 사양/덤프 | %d/%d (빠짐 %d · 남음 %d) |\n', R.compare.nDefSpec, R.compare.nDefDump, R.compare.missingDefaults, R.compare.extraDefaults);
        p('| Chart 속성 불일치 | %d |\n', R.compare.propMismatch);
        p('| Junction 사양/덤프 (정보) | %d/%d |\n', R.compare.junctionSpec, R.compare.junctionDump);
    end
    p('\n## 3. 이름 규칙\n\n| 규칙 | 측정값 | 어디 | 판정 |\n| --- | --- | --- | --- |\n');
    p('| State 이름 ≤ 12 | 최대 **%d** (State %d개) | `%s` | %s |\n', R.names.stateMax, R.names.nStates, R.names.stateMaxName, ternary(R.names.rule.state_le_12, '○', '✗'));
    p('| 데이터·이벤트 이름 ≤ 8 | 최대 **%d** (데이터 %d개 · 이벤트 %d개) | `%s` | %s |\n', R.names.dataMax, R.names.nData, R.names.nEvent, R.names.dataMaxName, ternary(R.names.rule.data_le_8, '○', '✗'));
    p('| 라벨 한 줄 ≤ 40 | 최대 **%d** (줄 %d개 중 40 초과 %d) | %s: `%s` | %s |\n', R.names.lineMax, R.names.nLines, R.names.nLinesOver40, R.names.lineMaxWhere, strrep(R.names.lineMaxText, '|', '\|'), ternary(R.names.rule.line_le_40, '○', '✗'));
    p('\n데이터: %s\n', R.names.data);
    p('\n## 4. 구조\n\n| State | Junction | 전이 | default |\n| --- | --- | --- | --- |\n| %d | %d | %d | %d |\n', ...
        R.struct.nStates, R.struct.nJunctions, R.struct.nTrans, R.struct.nDefaults);
end
