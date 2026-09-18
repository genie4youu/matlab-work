%% verify_Esm.m — Esm.slx 의 완료 조건을 기계로 재고 _덤프\ 에 산출물을 낸다
%
%   실행: build_Esm.m 다음, test_Esm.m 앞에.
%     matlab -wait -nosplash -batch "run('<OUT>\build_Esm.m'); run('<OUT>\verify_Esm.m'); run('<OUT>\test_Esm.m')" -logfile <OUT>\build.log
%
%   [1] Esm.slx 열기 + set_param(...,'SimulationCommand','update')
%   [2] emit_dump → emit_transtable → compare_spec(Esm_사양.md)      — 하네스 _shared\harness(+build)
%   [3] 이름 규칙 — 덤프 JSON 에서 State 이름 ≤ 12 · 데이터/이벤트 ≤ 8 · 라벨 한 줄 ≤ 40
%   [4] 구조(금지 조건 F5) — Init 으로 가는 전이는 `[req == 1]`, 나머지는 `!err` 포함
%   🔴 수치는 전부 이 스크립트가 센 값이다 → _덤프\검증수치.md. 결과 폴더(OUT) 밖에는 아무것도 쓰지 않는다.

OUT  = fileparts(mfilename('fullpath'));
HARN = 'C:\Users\leeyj\matlab-work\_shared\harness';
MDL  = 'Esm';
SLX  = fullfile(OUT, [MDL '.slx']);
DUMP = fullfile(OUT, '_덤프');
SPEC = fullfile(OUT, 'Esm_사양.md');

fprintf('\n==== verify_Esm ====\n');
assert(isfolder(OUT),  'result folder not found: %s', OUT);
assert(isfolder(HARN), 'harness not found: %s', HARN);
cd(OUT);
addpath(HARN, fullfile(HARN, 'build'));
Simulink.fileGenControl('set', ...
    'CacheFolder',   fullfile(OUT, '_slprj'), ...
    'CodeGenFolder', fullfile(OUT, '_slprj'), 'createDir', true);
if ~isfolder(DUMP), mkdir(DUMP); end

R = struct();
R.matlab = version;
R.when   = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

% ── [1] 열기 + update ────────────────────────────────────────────────
if bdIsLoaded(MDL), close_system(MDL, 0); end
assert(isfile(SLX), 'Esm.slx not found — run build_Esm.m first');
load_system(SLX);
diagLog = fullfile(DUMP, 'update_diag.log');          % 진단 뷰어 내용(오류 원문)을 파일로
if isfile(diagLog), delete(diagLog); end
sldiagviewer.diary(diagLog);  sldiagviewer.diary('on');
try
    set_param(MDL, 'SimulationCommand', 'update');
    R.update = 'ok';
catch e
    R.update = ['ERROR: ' strrep(e.message, newline, ' / ')];
end
sldiagviewer.diary('off');
fprintf('[1] update: %s\n', R.update);
if isfile(diagLog)
    if dir(diagLog).bytes == 0, delete(diagLog); fprintf('  진단 뷰어 출력 없음(경고 0)\n');
    else, fprintf('  진단: %s\n', diagLog); end
end

% ── [2] 덤프 · 전이표 · 사양 대조 ───────────────────────────────────
emit_dump(MDL, DUMP);
emit_transtable(DUMP);
rep = compare_spec(SPEC, DUMP);
R.compare = struct('total', rep.total, 'ok', rep.ok, 'states', '-', 'trans', '-', 'defaults', '-', ...
                   'missing', NaN, 'extra', NaN, 'mismatch', NaN);
if ~isempty(rep.chart)
    r = rep.chart(1);
    R.compare.states   = sprintf('%d/%d', r.nStateSpec, r.nStateDump);
    R.compare.trans    = sprintf('%d/%d', r.nTransSpec, r.nTransDump);
    R.compare.defaults = sprintf('%d/%d', r.nDefSpec,   r.nDefDump);
    R.compare.missing  = numel(r.missingStates) + numel(r.missingTrans) + numel(r.missingDefaults);
    R.compare.extra    = numel(r.extraStates)   + numel(r.extraTrans)   + numel(r.extraDefaults);
    R.compare.mismatch = size(r.stateMismatch, 1) + size(r.propMismatch, 1);
end
fprintf('[2] compare_spec total = %d (%s) — 빠짐 %d · 남음 %d · 불일치 %d\n', rep.total, ...
    tern(rep.ok, 'PASS', 'FAIL'), R.compare.missing, R.compare.extra, R.compare.mismatch);

% ── [3] 이름 규칙 — 덤프 JSON 에서 센다 ─────────────────────────────
nodes  = readjson(fullfile(DUMP, 'nodes.json'));
edges  = readjson(fullfile(DUMP, 'edges.json'));
charts = readjson(fullfile(DUMP, 'charts.json'));
stN = nodes(strcmp({nodes.kind}, 'State'));
stateNames = {stN.name};
dataNames = {};  dataScopes = {};  evNames = {};
if isfield(charts(1), 'data') && ~isempty(charts(1).data)
    dd = charts(1).data; if iscell(dd), dd = [dd{:}]; end
    dataNames = {dd.name};  dataScopes = {dd.scope};
end
if isfield(charts(1), 'events') && ~isempty(charts(1).events)
    ee = charts(1).events; if iscell(ee), ee = [ee{:}]; end
    evNames = {ee.name};
end
L = {};
for k = 1:numel(stN),  L = [L; cellstr(splitlines(string(stN(k).label)))];  end   %#ok<AGROW>
for k = 1:numel(edges), L = [L; cellstr(splitlines(string(edges(k).label)))]; end   %#ok<AGROW>
R.names.stateMax = max(cellfun(@strlength, stateNames));
R.names.dataMax  = max(cellfun(@strlength, [dataNames, evNames]));
R.names.lineMax  = max(cellfun(@strlength, L));
R.names.nStates  = numel(stateNames);  R.names.nData = numel(dataNames);  R.names.nEvent = numel(evNames);
R.names.ok = R.names.stateMax <= 12 && R.names.dataMax <= 8 && R.names.lineMax <= 40;
R.names.inputs  = dataNames(strcmp(dataScopes, 'Input'));
R.names.outputs = dataNames(strcmp(dataScopes, 'Output'));
fprintf('[3] State 최대 %d · 데이터/이벤트 최대 %d · 라벨 한 줄 최대 %d → %s | 입력 %s · 출력 %s\n', ...
    R.names.stateMax, R.names.dataMax, R.names.lineMax, tern(R.names.ok, 'PASS', 'FAIL'), ...
    strjoin(R.names.inputs, ','), strjoin(R.names.outputs, ','));

% ── [4] 구조 — F5 ────────────────────────────────────────────────────
isDef = logical([edges.isDefault]);
lab = {edges.label};  dst = {edges.dst};
toInit = ~isDef & strcmp(dst, 'Al.Init');
other  = ~isDef & ~toInit;
R.struct.nTrans = sum(~isDef);  R.struct.nDefaults = sum(isDef);
R.struct.nToInit = sum(toInit);
R.struct.F5 = all(strcmp(lab(toInit), '[req == 1]')) && all(contains(lab(other), '!err'));
fprintf('[4] 전이 %d (default %d) · Init 행 %d개 · F5=%d\n', R.struct.nTrans, R.struct.nDefaults, R.struct.nToInit, R.struct.F5);

% ── [5] 결과 파일 ────────────────────────────────────────────────────
mf = fullfile(DUMP, '검증수치.md');
fid = fopen(mf, 'w', 'n', 'UTF-8');
fprintf(fid, '# 검증 수치 — verify_Esm.m 이 센 값\n\n- 생성: %s · MATLAB %s\n- 모델: `%s`\n\n', R.when, R.matlab, SLX);
fprintf(fid, '> 🔴 이 파일의 수는 전부 스크립트가 센 것이다. 수용 시험 결과는 `build.log` 의 test_Esm 출력이 정본이다.\n\n');
fprintf(fid, '| 항목 | 값 |\n| --- | --- |\n');
fprintf(fid, '| `set_param(''Esm'',''SimulationCommand'',''update'')` | **%s** |\n', R.update);
fprintf(fid, '| compare_spec 합계 | **%d** → %s |\n', R.compare.total, tern(R.compare.ok, '통과', '실패'));
fprintf(fid, '| State / 전이 / default (사양/덤프) | %s / %s / %s |\n', R.compare.states, R.compare.trans, R.compare.defaults);
fprintf(fid, '| 빠짐 / 남음 / 불일치 | %d / %d / %d |\n', R.compare.missing, R.compare.extra, R.compare.mismatch);
fprintf(fid, '| State 이름 최대(≤ 12) | %d (State %d개) |\n', R.names.stateMax, R.names.nStates);
fprintf(fid, '| 데이터·이벤트 이름 최대(≤ 8) | %d (데이터 %d개 · 이벤트 %d개) |\n', R.names.dataMax, R.names.nData, R.names.nEvent);
fprintf(fid, '| 라벨 한 줄 최대(≤ 40) | %d |\n', R.names.lineMax);
fprintf(fid, '| 이름 규칙 | %s |\n', tern(R.names.ok, '통과', '실패'));
fprintf(fid, '| Input / Output 데이터 | %s / %s |\n', strjoin(R.names.inputs, ' '), strjoin(R.names.outputs, ' '));
fprintf(fid, '| F5 (Init 행 전이 `[req == 1]`, 나머지 `!err`) | %d (Init 행 %d개 / 전이 %d개) |\n', R.struct.F5, R.struct.nToInit, R.struct.nTrans);
fclose(fid);
fprintf('  → %s\n', mf);
fprintf('==== verify_Esm done: update=%s compare=%d names=%s ====\n', R.update, R.compare.total, tern(R.names.ok, 'ok', 'FAIL'));

% ══════════════════════════════════════════════════════════════════════
function S = readjson(p)
    d = jsondecode(fileread(p));
    if iscell(d), d = [d{:}]; end
    S = reshape(d, 1, []);
end

function v = tern(c, a, b)
    if c, v = a; else, v = b; end
end
