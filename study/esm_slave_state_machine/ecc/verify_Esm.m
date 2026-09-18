% verify_Esm.m — Esm.slx 의 기계 검증(관문 3) + 이름 규칙 수치.
%
% 실행:
%   matlab -wait -nosplash -batch "run('C:\Users\leeyj\Documents\yj.lee\ecc\회차\2026-09-17_esm_간단_재대결\verify_Esm.m')" -logfile ...\verify.log
%
% 순서: load_system → update → emit_dump → emit_transtable → compare_spec → §0 인터페이스 대조
%       → 이름 규칙 수치 → _덤프\검증수치.md
% 수용 시험은 test_Esm.m 이 따로 한다. 이 스크립트는 결과 폴더(OUT) 밖에 아무것도 쓰지 않는다.

OUT   = fileparts(mfilename('fullpath'));
MDL   = 'Esm';
CHART = 'EsmChart';
SLX   = fullfile(OUT, [MDL '.slx']);
DUMP  = fullfile(OUT, '_덤프');
SPEC  = fullfile(OUT, 'Esm_사양.md');
NUM   = fullfile(DUMP, '검증수치.md');

addpath('C:\Users\leeyj\matlab-work\_shared\harness');
addpath('C:\Users\leeyj\matlab-work\_shared\harness\build');
cd(OUT);
Simulink.fileGenControl('set', 'CacheFolder', OUT, 'CodeGenFolder', OUT, 'createDir', true);
if ~isfolder(DUMP), mkdir(DUMP); end

L = {};
L{end+1} = sprintf('# 검증수치 — %s', MDL);
L{end+1} = sprintf('- 실행: %s · MATLAB %s', datestr(now, 'yyyy-mm-dd HH:MM:SS'), version);
L{end+1} = sprintf('- 모델: `%s`', SLX);
L{end+1} = '';

%% 1. 열기 + update
if bdIsLoaded(MDL), close_system(MDL, 0); end
load_system(SLX);
set_param(MDL, 'SimulationCommand', 'update');
fprintf('[verify] update ok\n');
L{end+1} = '## 1. 열기·갱신';
L{end+1} = '- `load_system` + `set_param(''Esm'',''SimulationCommand'',''update'')`: 오류 없음';
L{end+1} = '';

%% 2. 덤프 · 전이표 · 사양 대조
emit_dump(MDL, DUMP);
emit_transtable(DUMP);
fprintf('[verify] dump + transtable ok\n');
rep = compare_spec(SPEC, DUMP);
disp(rep);
fprintf('[verify] compare_spec rep.total = %d\n', rep.total);
L{end+1} = '## 2. 덤프·전이표·사양 대조';
L{end+1} = sprintf('- `compare_spec` rep.total = **%d** (0 이 통과)', rep.total);
fn = fieldnames(rep);
for i = 1:numel(fn)
    v = rep.(fn{i});
    if isnumeric(v) && isscalar(v) || islogical(v) && isscalar(v)
        L{end+1} = sprintf('  - rep.%s = %g', fn{i}, double(v));
    elseif iscell(v) || isstruct(v)
        L{end+1} = sprintf('  - rep.%s: %d 항목', fn{i}, numel(v));
    end
end
% §0 인터페이스는 compare_spec 대상이 아니다 → charts.json 의 data 와 직접 대조(이름·방향·타입)
txt  = fileread(SPEC);
rows = regexp(txt, '^\| `(\w+)` \| (Input|Output|Local|Constant) \| (\w+) \|', 'tokens', 'lineanchors');
specIf = cellfun(@(r) sprintf('%s/%s/%s', r{1}, r{2}, r{3}), rows, 'UniformOutput', false);
cj = jsondecode(fileread(fullfile(DUMP, 'charts.json')));
dumpIf = arrayfun(@(d) sprintf('%s/%s/%s', d.name, d.scope, d.dataType), cj.data, 'UniformOutput', false);
ifMissing = setdiff(specIf, dumpIf);  ifExtra = setdiff(dumpIf, specIf);
fprintf('[iface] 사양 %d · 덤프 %d · 빠짐 %d · 남음 %d\n', numel(specIf), numel(dumpIf), numel(ifMissing), numel(ifExtra));
L{end+1} = sprintf('- §0 인터페이스 ↔ charts.json data (이름/방향/타입): 사양 %d · 덤프 %d · 빠짐 %d · 남음 %d', ...
    numel(specIf), numel(dumpIf), numel(ifMissing), numel(ifExtra));
if ~isempty(ifMissing), L{end+1} = ['  - 빠짐: ' strjoin(ifMissing, ', ')]; end
if ~isempty(ifExtra),   L{end+1} = ['  - 남음: ' strjoin(ifExtra, ', ')]; end
% 루트 Inport/Outport 이름·타입(과제 고정 인터페이스)
inB  = find_system(MDL, 'SearchDepth', 1, 'BlockType', 'Inport');
outB = find_system(MDL, 'SearchDepth', 1, 'BlockType', 'Outport');
inDesc  = cellfun(@(b) sprintf('%s(%s)', get_param(b, 'Name'), get_param(b, 'OutDataTypeStr')), inB, 'UniformOutput', false);
outDesc = cellfun(@(b) get_param(b, 'Name'), outB, 'UniformOutput', false);
fprintf('[root] Inport %s · Outport %s · Solver %s/%s FixedStep %s\n', strjoin(inDesc, ', '), strjoin(outDesc, ', '), ...
    get_param(MDL, 'SolverType'), get_param(MDL, 'Solver'), get_param(MDL, 'FixedStep'));
L{end+1} = sprintf('- 루트 Inport: %s · Outport: %s · Solver %s/%s · FixedStep %s', strjoin(inDesc, ', '), strjoin(outDesc, ', '), ...
    get_param(MDL, 'SolverType'), get_param(MDL, 'Solver'), get_param(MDL, 'FixedStep'));
L{end+1} = '';

%% 3. 이름 규칙 — 이 Chart 안에서만 센다
rt = sfroot;
ch = rt.find('-isa', 'Stateflow.Chart', 'Path', [MDL '/' CHART]);
states = ch.find('-isa', 'Stateflow.State');
datas  = ch.find('-isa', 'Stateflow.Data');
events = ch.find('-isa', 'Stateflow.Event');
trans  = ch.find('-isa', 'Stateflow.Transition');

sNames = arrayfun(@(s) s.Name, states, 'UniformOutput', false);
sLen   = cellfun(@numel, sNames);
[sMax, si] = max(sLen);
dNames = arrayfun(@(d) d.Name, datas, 'UniformOutput', false);
eNames = arrayfun(@(e) e.Name, events, 'UniformOutput', false);
deNames = [dNames(:); eNames(:)];
deLen  = cellfun(@numel, deNames);
[deMax, dei] = max(deLen);

% 라벨 한 줄: 전이 라벨 전체 + State 라벨(이름 줄 제외)
lines = {};
for i = 1:numel(trans)
    lab = trans(i).LabelString;
    if isempty(lab), continue; end
    parts = strsplit(lab, newline);
    lines = [lines; parts(:)]; %#ok<AGROW>
end
for i = 1:numel(states)
    lab = states(i).LabelString;
    parts = strsplit(lab, newline);
    if numel(parts) > 1, lines = [lines; parts(2:end)']; end %#ok<AGROW>
end
lines = lines(~cellfun(@isempty, lines));
lLen  = cellfun(@numel, lines);
[lMax, li] = max(lLen);

fprintf('[names] State %d개, 최대 %d자 (%s)\n', numel(states), sMax, sNames{si});
fprintf('[names] Data %d개 + Event %d개, 최대 %d자 (%s)\n', numel(datas), numel(events), deMax, deNames{dei});
fprintf('[names] 라벨 줄 %d개, 최대 %d자 (%s)\n', numel(lines), lMax, lines{li});
fprintf('[names] 초과 — State>12: %d · Data/Event>8: %d · 라벨>40: %d\n', sum(sLen > 12), sum(deLen > 8), sum(lLen > 40));
fprintf('[count] Transition %d개 (기본 전이 %d개 포함)\n', numel(trans), sum(arrayfun(@(t) isempty(t.Source), trans)));

L{end+1} = sprintf('## 3. 이름 규칙 (Chart `%s` 안에서만 셈)', CHART);
L{end+1} = '| 항목 | 개수 | 최대 길이 | 기준 | 초과 | 최대인 것 |';
L{end+1} = '| --- | --- | --- | --- | --- | --- |';
L{end+1} = sprintf('| State 이름 | %d | %d | ≤ 12 | %d | `%s` |', numel(states), sMax, sum(sLen > 12), sNames{si});
L{end+1} = sprintf('| 데이터·이벤트 이름 | %d + %d | %d | ≤ 8 | %d | `%s` |', numel(datas), numel(events), deMax, sum(deLen > 8), deNames{dei});
L{end+1} = sprintf('| 라벨 한 줄(전이 + State Action) | %d | %d | ≤ 40 | %d | `%s` |', numel(lines), lMax, sum(lLen > 40), strrep(lines{li}, '|', '\|'));
L{end+1} = sprintf('| Transition | %d | | | | 기본 전이 %d 포함 |', numel(trans), sum(arrayfun(@(t) isempty(t.Source), trans)));
L{end+1} = '';
L{end+1} = '### State 이름 전부';
L{end+1} = '| 이름 | 길이 |';
L{end+1} = '| --- | --- |';
for i = 1:numel(sNames), L{end+1} = sprintf('| `%s` | %d |', sNames{i}, sLen(i)); end
L{end+1} = '';
L{end+1} = '### 데이터·이벤트 이름 전부';
L{end+1} = '| 이름 | 길이 |';
L{end+1} = '| --- | --- |';
for i = 1:numel(deNames), L{end+1} = sprintf('| `%s` | %d |', deNames{i}, deLen(i)); end
L{end+1} = '';
L{end+1} = '### 라벨 줄 전부 (길이 내림차순)';
[~, ord] = sort(lLen, 'descend');
for i = ord(:)'
    L{end+1} = sprintf('- %d자: `%s`', lLen(i), strrep(lines{i}, '|', '\|'));
end
L{end+1} = '';

fid = fopen(NUM, 'w', 'n', 'UTF-8');
fprintf(fid, '%s\n', L{:});
fclose(fid);
fprintf('[verify] wrote %s\n', NUM);
close_system(MDL, 0);
fprintf('[verify] done — rep.total=%d · 이름 초과 %d\n', rep.total, sum(sLen > 12) + sum(deLen > 8) + sum(lLen > 40));
