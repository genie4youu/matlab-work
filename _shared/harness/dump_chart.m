function dump_chart(chartPath, outFile)
%DUMP_CHART  Stateflow Chart 하나를 마크다운으로 전수 덤프한다.
%
%   dump_chart('Example_Main_SF/SF', 'out\Main_SF.md')
%
%   덤프 항목
%     - Chart 속성 (Decomposition, 실행순서 지정 방식, Action Language, 갱신 방식)
%     - Data 전수 (Scope, DataType, Size, InitialValue, Range)
%     - State 계층 (경로, Decomposition, ExecutionOrder, entry/during/exit Action)
%     - Transition 전수 (Source -> Destination, Label, ExecutionOrder)
%     - Junction 목록
%
%   State 의 LabelString 에 entry/during/exit Action 이 그대로 들어 있으므로
%   "어떤 값이 어디로 들어가는가" 를 이 덤프만으로 추적할 수 있다.

    r = sfroot;
    ch = r.find('-isa','Stateflow.Chart','-and','Path',chartPath);
    if isempty(ch)
        error('dump_chart:notFound','Chart 를 찾지 못했습니다: %s', chartPath);
    end
    c = ch(1);

    d = fileparts(outFile);
    if ~isempty(d) && ~isfolder(d), mkdir(d); end
    fid = fopen(outFile,'w','n','UTF-8');
    oc  = onCleanup(@() fclose(fid));

    p = @(varargin) fprintf(fid, varargin{:});

    p('# Chart 덤프 — `%s`\n\n', c.Path);

    % ── Chart 속성 ────────────────────────────────────
    p('## A. Chart 속성\n\n');
    p('| 항목 | 값 |\n| --- | --- |\n');
    p('| Decomposition | `%s` |\n', c.Decomposition);
    p('| ActionLanguage | `%s` |\n', getp(c,'ActionLanguage'));
    p('| ChartUpdate | `%s` |\n', getp(c,'ChartUpdate'));
    p('| SampleTime | `%s` |\n', getp(c,'SampleTime'));
    p('| 실행순서 사용자지정 | `%s` |\n', getp(c,'UserSpecifiedStateTransitionExecutionOrder'));
    p('| ExecuteAtInitialization | `%s` |\n', getp(c,'ExecuteAtInitialization'));
    p('| StatesWhenEnabling | `%s` |\n', getp(c,'StatesWhenEnabling'));
    p('\n');

    % ── Data ──────────────────────────────────────────
    dat = c.find('-isa','Stateflow.Data');
    p('## B. Data (%d개)\n\n', numel(dat));
    p('| # | 이름 | Scope | DataType | Size | InitialValue | 비고 |\n');
    p('| --- | --- | --- | --- | --- | --- | --- |\n');
    for k = 1:numel(dat)
        v = dat(k);
        init = '';
        try, init = v.Props.InitialValue; catch, end
        rng = '';
        try
            lo = v.Props.Range.Minimum; hi = v.Props.Range.Maximum;
            if ~isempty(lo) || ~isempty(hi)
                rng = sprintf('range [%s, %s]', str(lo), str(hi));
            end
        catch
        end
        p('| %d | `%s` | %s | `%s` | %s | `%s` | %s |\n', ...
            k, v.Name, v.Scope, getp(v,'DataType'), str(getp(v,'Size')), init, rng);
    end
    p('\n');

    % ── State 계층 ────────────────────────────────────
    st = c.find('-isa','Stateflow.State');
    p('## C. State (%d개)\n\n', numel(st));

    % 계층 정렬: 경로 문자열 기준
    paths = cell(numel(st),1);
    for k = 1:numel(st), paths{k} = statePath(st(k), c); end
    [~, idx] = sort(paths);

    p('### C-1. 계층 요약\n\n');
    p('| 경로 | 깊이 | Decomposition | 실행순서 | 하위 State |\n');
    p('| --- | --- | --- | --- | --- |\n');
    for k = idx'
        s = st(k);
        depth = numel(strfind(paths{k}, '.'));
        p('| `%s` | %d | %s | %s | %d |\n', paths{k}, depth, ...
            s.Decomposition, str(getp(s,'ExecutionOrder')), ...
            numel(s.find('-isa','Stateflow.State'))-1);
    end
    p('\n');

    p('### C-2. State 별 Action\n\n');
    for k = idx'
        s = st(k);
        p('#### `%s`\n\n', paths{k});
        p('- Decomposition: `%s` / 실행순서: `%s`\n', s.Decomposition, str(getp(s,'ExecutionOrder')));
        lbl = s.LabelString;
        if isempty(strtrim(lbl))
            p('- Action: 없음\n\n');
        else
            p('\n```\n%s\n```\n\n', lbl);
        end
    end

    % ── Transition ────────────────────────────────────
    tr = c.find('-isa','Stateflow.Transition');
    p('## D. Transition (%d개)\n\n', numel(tr));
    p('| # | Source | Destination | 실행순서 | Label |\n');
    p('| --- | --- | --- | --- | --- |\n');
    for k = 1:numel(tr)
        t = tr(k);
        p('| %d | %s | %s | %s | `%s` |\n', k, ...
            endpointName(t.Source, c), endpointName(t.Destination, c), ...
            str(getp(t,'ExecutionOrder')), oneline(t.LabelString));
    end
    p('\n');

    % ── Junction ──────────────────────────────────────
    ju = c.find('-isa','Stateflow.Junction');
    p('## E. Junction (%d개)\n\n', numel(ju));
    if isempty(ju)
        p('없음\n');
    else
        p('| # | id | Type | 부모 |\n| --- | --- | --- | --- |\n');
        for k = 1:numel(ju)
            j = ju(k);
            p('| %d | %d | %s | `%s` |\n', k, j.Id, getp(j,'Type'), parentName(j, c));
        end
    end
    p('\n');
end


% ── 보조 함수 ─────────────────────────────────────────

function s = getp(o, name)
    try
        v = o.(name);
        s = str(v);
    catch
        s = '-';
    end
end

function s = str(v)
    if isempty(v),            s = '';
    elseif ischar(v),         s = v;
    elseif isstring(v),       s = char(v);
    elseif isnumeric(v) && isscalar(v), s = num2str(v);
    elseif isnumeric(v),      s = mat2str(v);
    elseif islogical(v),      s = mat2str(v);
    else
        try, s = char(string(v)); catch, s = class(v); end
    end
    s = strrep(s, sprintf('\n'), ' ');
end

function out = oneline(s)
    if isempty(s), out = ''; return; end
    out = regexprep(s, '\s*\n\s*', ' ; ');
    out = strrep(out, '|', '\|');
end

function nm = statePath(s, c)
    parts = {s.Name};
    pr = s.getParent;
    while ~isempty(pr) && ~isa(pr,'Stateflow.Chart')
        parts{end+1} = pr.Name; %#ok<AGROW>
        pr = pr.getParent;
    end
    nm = strjoin(fliplr(parts), '.');
end

function nm = endpointName(e, c)
    if isempty(e)
        nm = '**(기본 전이)**';
    elseif isa(e,'Stateflow.State')
        nm = ['`' statePath(e, c) '`'];
    elseif isa(e,'Stateflow.Junction')
        nm = sprintf('Junction %d', e.Id);
    else
        nm = class(e);
    end
end

function nm = parentName(o, c)
    pr = o.getParent;
    if isempty(pr) || isa(pr,'Stateflow.Chart')
        nm = '(Chart 최상위)';
    else
        nm = statePath(pr, c);
    end
end
