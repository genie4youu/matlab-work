function C = collect_chart(chartPath)
%COLLECT_CHART  Stateflow Chart 하나를 **가공하지 않은 구조체**로 수집한다.
%
%   C = collect_chart('Example_Main_SF/SF')
%
%   왜 dump_chart 와 따로 만드나
%   ──────────────────────────
%   `dump_chart` 는 사람이 읽는 마크다운을 낸다. 이 함수는 **기계가 읽는 구조체**를
%   낸다. 둘의 용도가 다르고, 그래서 dump_chart 를 고치지 않는다.
%   - dump_chart 를 고치면 `/analyze` 의 기존 산출물 수치가 바뀐다 (R14·R16)
%   - 그리고 **열거원이 둘이 되는 편이 낫다.** 같은 Chart 를 두 경로로 세서
%     어긋나면 잡는다 (R26). 열거가 하나뿐이라 비교 대상이 없었던 것이
%     이 프로젝트의 반복 실패 모드였다.
%
%   dump_chart 가 잃는 것을 여기서는 보존한다
%   ────────────────────────────────────────
%   `dump_chart` 의 `oneline()` 은 Transition LabelString 의 개행을 ` ; ` 로
%   압축한다. State 는 코드블록으로 원문을 보존하는데 Transition 은 눌린다.
%   손 변환용 전이표에는 `[condition]{action}` 의 원문 줄바꿈이 필요하므로
%   **여기서는 LabelString 을 한 글자도 바꾸지 않는다.**
%
%   반환 구조
%   ────────
%     C.path, C.name, C.model         Chart 식별
%     C.props                         Chart 속성 (Decomposition·ActionLanguage 등)
%     C.states(k)                     id · name · path · parent · decomposition
%                                     · executionOrder · isSubchart · label · position
%     C.transitions(k)                id · src · dst · srcType · dstType
%                                     · isDefault · executionOrder · label
%     C.junctions(k)                  id · type · parent · position
%     C.data(k)                       name · scope · dataType · size · initialValue · min · max
%     C.events(k)                     name · scope · trigger
%     C.counts                        각 항목 개수 (감사가 대조한다)
%
%   🔴 해석하지 않는다. 객체 속성에서 읽은 값만 담는다.
%   🔴 「없다」와 「못 읽었다」를 구분한다 — 속성 접근이 실패하면 필드에
%      '<읽기실패>' 를 넣고 C.warnings 에 남긴다. 조용히 빈 값으로 두지 않는다.

    if nargin < 1 || isempty(chartPath)
        error('collect_chart:noArg', 'Chart 경로가 필요하다. 예: collect_chart(''Example_Main_SF/SF'')');
    end
    chartPath = char(chartPath);

    r  = sfroot;
    ch = r.find('-isa','Stateflow.Chart','-and','Path',chartPath);
    if isempty(ch)
        error('collect_chart:notFound', ...
            ['Chart 를 찾지 못했다: %s\n' ...
             '  sfroot 는 **그때 로드된 모델만** 준다 (R18). 모델을 먼저 로드했는가?'], chartPath);
    end
    c = ch(1);

    C = struct();
    C.path      = char(c.Path);
    C.name      = char(c.Name);
    C.model     = firstSeg(C.path);
    C.collected = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
    C.warnings  = {};

    % ── Chart 속성 ────────────────────────────────────
    %    저작 시 반드시 지정해야 하는 것들이다. 기본값 ActionLanguage='MATLAB' 은
    %    손 변환 난이도를 올리므로 회차 문서에 남는 값이어야 한다.
    %    🔴 2026-09-08: `UserSpecifiedStateTransitionExecutionOrder` 는 R2025b 에
    %       **존재하지 않는다.** Chart 속성 68개 중 이름에 Order·Execution 이 든
    %       것이 0개다. 기존 `dump_chart.m:39` 도 이 값을 못 읽고 조용히 '-' 로
    %       표시해 왔다 — 「없다」를 「-」로 적으면 결함이 드러나지 않는다.
    %       전이 실행 순서는 Transition 의 ExecutionOrder 로 수집한다.
    pnames = {'Decomposition','ActionLanguage','ChartUpdate','SampleTime', ...
              'ExecuteAtInitialization','StatesWhenEnabling', ...
              'EnableZeroCrossings','SupportVariableSizing'};
    C.props = struct();
    for i = 1:numel(pnames)
        [v, okv] = prop(c, pnames{i});
        C.props.(pnames{i}) = v;
        if ~okv
            C.warnings{end+1} = sprintf('Chart 속성 %s 를 읽지 못했다', pnames{i});        end
    end

    % ── State ─────────────────────────────────────────
    st = c.find('-isa','Stateflow.State');
    C.states = emptyStruct({'id','name','path','parent','decomposition', ...
                            'executionOrder','isSubchart','label','position'});
    for k = 1:numel(st)
        s = st(k);
        e = struct();
        e.id             = num(prop(s,'Id'));
        e.name           = charOf(prop(s,'Name'));
        e.path           = statePath(s);
        e.parent         = parentPath(s);
        e.decomposition  = charOf(prop(s,'Decomposition'));
        e.executionOrder = num(prop(s,'ExecutionOrder'));
        e.isSubchart     = logi(prop(s,'IsSubchart'));
        e.label          = rawLabel(s);      % 🔴 원문 그대로. 개행을 바꾸지 않는다
        e.position       = vec(prop(s,'Position'));
        C.states(end+1) = e;    end

    % ── Transition ────────────────────────────────────
    tr = c.find('-isa','Stateflow.Transition');
    C.transitions = emptyStruct({'id','src','dst','srcType','dstType', ...
                                 'isDefault','executionOrder','label'});
    for k = 1:numel(tr)
        t = tr(k);
        e = struct();
        e.id             = num(prop(t,'Id'));
        [e.src, e.srcType] = endpoint(t, 'Source');
        [e.dst, e.dstType] = endpoint(t, 'Destination');
        e.isDefault      = isempty(e.src);   % Source 가 없으면 default transition
        e.executionOrder = num(prop(t,'ExecutionOrder'));
        e.label          = rawLabel(t);      % 🔴 원문 그대로
        C.transitions(end+1) = e;    end

    % ── Junction ──────────────────────────────────────
    ju = c.find('-isa','Stateflow.Junction');
    C.junctions = emptyStruct({'id','type','parent','position'});
    for k = 1:numel(ju)
        j = ju(k);
        e = struct();
        e.id       = num(prop(j,'Id'));
        e.type     = charOf(prop(j,'Type'));
        e.parent   = parentPath(j);
        e.position = junctionPos(j);
        C.junctions(end+1) = e;    end

    % ── Data ──────────────────────────────────────────
    dt = c.find('-isa','Stateflow.Data');
    C.data = emptyStruct({'name','scope','dataType','size','initialValue','min','max'});
    for k = 1:numel(dt)
        d = dt(k);
        e = struct();
        e.name         = charOf(prop(d,'Name'));
        e.scope        = charOf(prop(d,'Scope'));
        e.dataType     = charOf(prop(d,'DataType'));
        e.size         = charOf(propsField(d,'Array','Size'));
        e.initialValue = charOf(propsField(d,'InitialValue'));
        e.min          = charOf(rangeField(d,'Minimum'));
        e.max          = charOf(rangeField(d,'Maximum'));
        C.data(end+1) = e;    end

    % ── Event ─────────────────────────────────────────
    ev = c.find('-isa','Stateflow.Event');
    C.events = emptyStruct({'name','scope','trigger'});
    for k = 1:numel(ev)
        v = ev(k);
        e = struct();
        e.name    = charOf(prop(v,'Name'));
        e.scope   = charOf(prop(v,'Scope'));
        e.trigger = charOf(prop(v,'Trigger'));
        C.events(end+1) = e;    end

    % ── 개수 (감사가 이것을 dump_chart 와 대조한다) ────
    C.counts = struct( ...
        'states',      numel(C.states), ...
        'transitions', numel(C.transitions), ...
        'junctions',   numel(C.junctions), ...
        'data',        numel(C.data), ...
        'events',      numel(C.events), ...
        'defaults',    sum([C.transitions.isDefault]), ...
        'warnings',    numel(C.warnings));
end


% ══════════════════════════════════════════════════════
% 보조 — 전부 「못 읽었다」를 값으로 남긴다

function [v, ok] = prop(o, name)
%PROP  속성을 읽는다. 실패를 빈 값으로 감추지 않고 ok=false 로 알린다.
    ok = true;
    try
        v = o.(name);
    catch
        v = '<읽기실패>';
        ok = false;
    end
end

function v = propsField(o, varargin)
%PROPSFIELD  o.Props.<a>.<b> 처럼 중첩된 것을 읽는다.
    try
        v = o.Props;
        for i = 1:numel(varargin)
            v = v.(varargin{i});
        end
    catch
        v = '';
    end
end

function v = rangeField(o, which)
    try
        v = o.Props.Range.(which);
    catch
        v = '';
    end
end

function s = rawLabel(o)
%RAWLABEL  LabelString 을 **원문 그대로** 준다.
%   🔴 개행을 바꾸지 않는다. dump_chart 의 oneline() 이 Transition 라벨의
%      개행을 ' ; ' 로 압축해 원문을 잃는 것이 이 함수를 만든 이유다.
    try
        s = o.LabelString;
        if isstring(s), s = char(s); end
        if ~ischar(s), s = ''; end
    catch
        s = '<읽기실패>';
    end
end

function [nm, ty] = endpoint(t, which)
%ENDPOINT  Transition 의 끝점 이름과 종류. 비어 있으면 '' (default transition).
    nm = ''; ty = '';
    try
        e = t.(which);
    catch
        nm = '<읽기실패>'; ty = '<읽기실패>'; return
    end
    if isempty(e), return; end
    if isa(e, 'Stateflow.State')
        ty = 'State';    nm = statePath(e);
    elseif isa(e, 'Stateflow.Junction')
        ty = 'Junction'; nm = sprintf('J%d', numOr(e, 'Id'));
    else
        ty = class(e);
        try, nm = char(e.Name); catch, nm = ''; end
    end
end

function p = statePath(s)
%STATEPATH  Chart 안에서의 점 구분 경로. Chart 자신은 포함하지 않는다.
    try
        parts = {char(s.Name)};
    catch
        parts = {'<이름없음>'};
    end
    o = s;
    for k = 1:64          % 상한. 계층이 64를 넘으면 그 자체가 이상하다
        try
            pr = o.getParent;
        catch
            break
        end
        if isempty(pr) || isa(pr, 'Stateflow.Chart')
            break
        end
        try
            parts{end+1} = char(pr.Name);
        catch
            break
        end
        o = pr;
    end
    p = strjoin(fliplr(parts), '.');
end

function p = parentPath(o)
    try
        pr = o.getParent;
        if isempty(pr) || isa(pr, 'Stateflow.Chart')
            p = '';                 % Chart 최상위
        else
            p = statePath(pr);
        end
    catch
        p = '<읽기실패>';
    end
end

function v = junctionPos(j)
%JUNCTIONPOS  Position 이 struct(Center/Radius)인 릴리스와 벡터인 릴리스가 있다.
    try
        v = [j.Position.Center(:)', j.Position.Radius];
        return
    catch
        % struct 가 아니면 아래에서 벡터로 시도한다
    end
    try
        v = double(j.Position(:)');
    catch
        v = [];
    end
end

function s = firstSeg(p)
    i = strfind(p, '/');
    if isempty(i), s = p; else, s = p(1:i(1)-1); end
end

function S = emptyStruct(fields)
    args = cell(1, 2*numel(fields));
    args(1:2:end) = fields;
    args(2:2:end) = {{}};
    S = struct(args{:});
end

function v = num(x)
    if isnumeric(x) && isscalar(x), v = double(x);
    elseif isnumeric(x),            v = double(x);
    else,                           v = NaN;
    end
end

function v = numOr(o, name)
    v = NaN;
    try, v = double(o.(name)); catch, end
end

function v = logi(x)
    if islogical(x) || isnumeric(x), v = logical(x); else, v = false; end
end

function v = vec(x)
    if isnumeric(x), v = double(x(:)'); else, v = []; end
end

function s = charOf(x)
%CHAROF  표시용 문자열. **여기서 개행을 바꾸지 않는다** — 원문 보존이 목적이다.
    if ischar(x),            s = x;
    elseif isstring(x),      s = char(x);
    elseif isempty(x),       s = '';
    elseif isnumeric(x) && isscalar(x), s = num2str(x);
    elseif isnumeric(x),     s = mat2str(x);
    elseif islogical(x),     s = mat2str(x);
    else
        try, s = char(string(x)); catch, s = class(x); end
    end
end
