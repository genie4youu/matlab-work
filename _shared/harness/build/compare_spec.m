function rep = compare_spec(specFile, dumpDir, outFile)
%COMPARE_SPEC  사양표 ↔ 덤프를 집합으로 대조한다. 「허점 없음」의 실체다. 모델을 열지 않는다.
%
%   rep = compare_spec('<모델>_사양.md', 'C:\...\_덤프')
%   rep = compare_spec('<모델>_사양.md', 'C:\...\_덤프', 'C:\...\_덤프\사양대조.md')
%
%   무엇을 판정하나 (2026-09-16 결정 — 사양표가 정본, 모델은 구현)
%   ─────────────────────────────────────────────────────
%     사양에 있는데 모델에 없다  → 「빠짐」   (모델이 덜 만들어졌다)
%     모델에 있는데 사양에 없다  → 「남음」   (모델이 사양 밖의 것을 가졌다 — 사양표를 고치든 모델을 고치든 사람이 정한다)
%     둘 다 있는데 값이 다르다   → 「불일치」 (분해 · 실행순서 · 라벨 · Chart 속성)
%   셋 다 0 이어야 통과다. 0 이 아니면 어느 쪽이 틀렸는지는 이 함수가 정하지 않는다 —
%   정본은 사양표이므로 기본은 「모델이 틀렸다」이나, 사용자가 모델을 직접 고친 회차는
%   덤프 diff 를 사양표에 역반영한 뒤 다시 돌린다.
%
%   대조 단위
%   ────────
%     Chart     경로로. Chart 속성은 사양표 N.1 표에 적힌 항목만(보통 Decomposition·ActionLanguage·SampleTime·StatesWhenEnabling)
%     State     경로로. 있으면 자식분해 · 실행순서 · Action 원문(정규화)을 비교
%     Transition  (출발, 도착, 실행순서, 라벨) 네 값의 다중집합으로. 이름이 없는 Junction 은 `#J` 로 익명화한다
%                 — 덤프의 `J1442` 는 id 기반 이름이라 사람이 쓴 사양표와 이름으로 맞출 수 없다.
%                 그래서 Junction 을 지나는 전이는 「어느 Junction 인지」는 보지 않고 「그런 전이가 있는지」만 본다 (알려진 한계)
%     Default   (도착, 라벨) 로. 4.1 표와 덤프의 isDefault 전이
%
%   라벨 정규화 — 양쪽에 같은 규칙: CRLF→LF, 줄 경계의 공백 제거, 양끝 trim.
%   전이표의 인라인 칸(` ⏎ `)을 되돌린 것과 원문이 이 규칙 아래서 같아진다.
%
%   왕복 시험 (이 함수가 맞게 도는지의 최소 증거)
%   ────────────────────────────────────────
%     emit_transtable 이 낸 전이표.md 를 사양표로 읽어 같은 덤프와 대조하면 **빠짐 0 · 남음 0 · 불일치 0** 이어야 한다.
%     그리고 전이표를 일부러 망가뜨리면(State 행 삭제 · 라벨 수정) 정확히 그만큼 잡혀야 한다.
%     → selftest_spec 이 둘 다 돌린다. 실패를 못 내는 검사기는 검사기가 아니다.

    if nargin < 2
        error('compare_spec:args', 'compare_spec(사양표, 덤프폴더[, 출력파일])');
    end
    if nargin < 3 || isempty(outFile)
        outFile = fullfile(dumpDir, '사양대조.md');
    end

    spec   = read_spec(specFile);
    nodes  = read_json(fullfile(dumpDir, 'nodes.json'));
    edges  = read_json(fullfile(dumpDir, 'edges.json'));
    charts = read_json(fullfile(dumpDir, 'charts.json'));
    if isempty(nodes) || isempty(charts)
        error('compare_spec:noDump', '덤프가 비었다: %s (nodes/charts)', dumpDir);
    end
    if isempty(edges), edges = struct('chart',{},'src',{},'dst',{},'srcType',{},'dstType',{},'isDefault',{},'executionOrder',{},'label',{}); end

    rep = struct('spec', specFile, 'dump', dumpDir, 'out', outFile, 'ok', false, ...
                 'missingCharts', {{}}, 'extraCharts', {{}}, 'chart', struct([]));

    specCharts = {spec.charts.chart};
    dumpCharts = {charts.chart};
    rep.missingCharts = setdiff(specCharts, dumpCharts);
    rep.extraCharts   = setdiff(dumpCharts, specCharts);

    both = intersect(specCharts, dumpCharts);
    results = {};
    for c = 1:numel(both)
        cp = both{c};
        sc = spec.charts(strcmp(specCharts, cp));
        dc = charts(strcmp(dumpCharts, cp));
        dn = nodes(strcmp({nodes.chart}, cp));
        de = edges(strcmp({edges.chart}, cp));
        r = struct('chart', cp);

        % ── Chart 속성 ────────────────────────────────
        r.propMismatch = {};
        if isstruct(sc.props)
            fn = fieldnames(sc.props);
            for k = 1:numel(fn)
                if isstruct(dc.props) && isfield(dc.props, fn{k})
                    want = char(string(sc.props.(fn{k})));
                    have = char(string(dc.props.(fn{k})));
                    if ~strcmp(want, have)
                        r.propMismatch(end+1,:) = {fn{k}, want, have};
                    end
                end
            end
        end

        % ── State ─────────────────────────────────────
        dst = dn(strcmp({dn.kind}, 'State'));
        dju = dn(strcmp({dn.kind}, 'Junction'));
        sPaths = {sc.states.path};
        dPaths = {dst.path};
        r.missingStates = setdiff(sPaths, dPaths);
        r.extraStates   = setdiff(dPaths, sPaths);
        r.stateMismatch = {};
        for k = 1:numel(sPaths)
            j = find(strcmp(dPaths, sPaths{k}), 1);
            if isempty(j), continue; end
            s = sc.states(k); d = dst(j);
            if ~strcmp(s.decomposition, d.decomposition)
                r.stateMismatch(end+1,:) = {s.path, '자식분해', s.decomposition, d.decomposition};
            end
            if ~same_num(s.executionOrder, d.executionOrder)
                r.stateMismatch(end+1,:) = {s.path, '실행순서', numstr(s.executionOrder), numstr(d.executionOrder)};
            end
            if ~strcmp(norm_label(s.label), norm_label(d.label))
                r.stateMismatch(end+1,:) = {s.path, 'Action 원문', short(s.label), short(d.label)};
            end
        end

        % ── Transition (다중집합) ─────────────────────
        juNames = {dju.name};
        isState = @(nm) any(strcmp(sPaths, nm)) || any(strcmp(dPaths, nm));
        keyOf   = @(nm) end_key(nm, isState, juNames);

        dOth = de(~[de.isDefault]);
        dDef = de([de.isDefault]);
        sKeys = cell(1, numel(sc.transitions));
        for k = 1:numel(sc.transitions)
            e = sc.transitions(k);
            sKeys{k} = sprintf('%s → %s | %s | %s', keyOf(e.src), keyOf(e.dst), numstr(e.executionOrder), norm_label(e.label));
        end
        dKeys = cell(1, numel(dOth));
        for k = 1:numel(dOth)
            e = dOth(k);
            dKeys{k} = sprintf('%s → %s | %s | %s', keyOf(e.src), keyOf(e.dst), numstr(e.executionOrder), norm_label(e.label));
        end
        [r.missingTrans, r.extraTrans] = multiset_diff(sKeys, dKeys);

        % ── Default ───────────────────────────────────
        sDef = cell(1, numel(sc.defaults));
        for k = 1:numel(sc.defaults)
            sDef{k} = sprintf('default → %s | %s', keyOf(sc.defaults(k).dst), norm_label(sc.defaults(k).label));
        end
        dDefK = cell(1, numel(dDef));
        for k = 1:numel(dDef)
            dDefK{k} = sprintf('default → %s | %s', keyOf(dDef(k).dst), norm_label(dDef(k).label));
        end
        [r.missingDefaults, r.extraDefaults] = multiset_diff(sDef, dDefK);

        % ── 정보: Junction 수 (익명 대조라 판정에는 안 쓴다) ──
        specJu = unique([{sc.transitions.src}, {sc.transitions.dst}, {sc.defaults.dst}]);
        specJu = specJu(~cellfun(@isempty, specJu));
        specJu = specJu(~cellfun(@(n) any(strcmp(sPaths, n)) || any(strcmp(dPaths, n)), specJu));
        r.junctionSpec = numel(specJu);
        r.junctionDump = numel(dju);

        r.nStateSpec = numel(sPaths); r.nStateDump = numel(dPaths);
        r.nTransSpec = numel(sKeys);  r.nTransDump = numel(dKeys);
        r.nDefSpec   = numel(sDef);   r.nDefDump   = numel(dDefK);
        r.count = numel(r.missingStates) + numel(r.extraStates) + size(r.stateMismatch,1) ...
                + numel(r.missingTrans) + numel(r.extraTrans) ...
                + numel(r.missingDefaults) + numel(r.extraDefaults) + size(r.propMismatch,1);
        results{end+1} = r; %#ok<AGROW>
    end
    if ~isempty(results), rep.chart = [results{:}]; end

    rep.total = numel(rep.missingCharts) + numel(rep.extraCharts);
    if ~isempty(results), rep.total = rep.total + sum([rep.chart.count]); end
    rep.ok = (rep.total == 0);

    write_report(rep, spec, outFile);

    fprintf('  사양 대조 → %s\n', outFile);
    fprintf('  Chart %d (빠짐 %d · 남음 %d) · 불일치 합계 %d → %s\n', numel(both), ...
        numel(rep.missingCharts), numel(rep.extraCharts), rep.total, ternary(rep.ok, '통과', '실패'));
end

% ══════════════════════════════════════════════════════

function k = end_key(nm, isState, juNames)
%END_KEY  전이 끝점의 대조 키. State 는 경로, Junction 은 익명 `#J`, 빈 문자열은 default.
    if isempty(nm),                 k = 'default';
    elseif isState(nm),             k = ['S:' nm];
    elseif any(strcmp(juNames, nm)), k = '#J';
    elseif ~isempty(regexp(nm, '^J\d+$', 'once')), k = '#J';   % 덤프 이름 형식
    else,                           k = '#J';                   % 사양표의 임의 Junction 이름
    end
end

function [missing, extra] = multiset_diff(a, b)
%MULTISET_DIFF  a 에만 있는 것(개수 포함) 과 b 에만 있는 것.
    missing = {}; extra = {};
    ua = unique([a, b]);
    for k = 1:numel(ua)
        na = sum(strcmp(a, ua{k})); nb = sum(strcmp(b, ua{k}));
        if na > nb, missing = [missing, repmat(ua(k), 1, na-nb)]; end %#ok<AGROW>
        if nb > na, extra   = [extra,   repmat(ua(k), 1, nb-na)]; end %#ok<AGROW>
    end
end

function tf = same_num(a, b)
    if (isempty(a) || isnan(a)) && (isempty(b) || isnan(b)), tf = true; return; end
    if isempty(a) || isempty(b), tf = false; return; end
    tf = isequal(a, b);
end

function s = norm_label(s)
    if isempty(s), s = ''; return; end
    s = char(string(s));
    s = strrep(s, sprintf('\r\n'), newline);
    s = regexprep(s, '\s*\n\s*', newline);
    s = strtrim(s);
end

function s = short(s)
    s = norm_label(s);
    s = strrep(s, newline, ' ⏎ ');
    if numel(s) > 80, s = [s(1:77) '...']; end
end

function s = numstr(x)
    if isnumeric(x) && isscalar(x) && ~isnan(x), s = num2str(x); else, s = '-'; end
end

function v = ternary(c, a, b)
    if c, v = a; else, v = b; end
end

function S = read_json(p)
    S = [];
    if ~isfile(p), return; end
    raw = read_utf8(p);
    if isempty(strtrim(raw)), return; end
    d = jsondecode(raw);
    if iscell(d), try, d = [d{:}]; catch, end, end
    if isstruct(d) && ~isscalar(d), S = reshape(d,1,[]); else, S = d; end
end

function write_report(rep, spec, outFile)
    d = fileparts(outFile);
    if ~isempty(d) && ~isfolder(d), mkdir(d); end
    fid = fopen(outFile, 'w', 'n', 'UTF-8');
    if fid < 0, error('compare_spec:write', '쓸 수 없다: %s', outFile); end
    oc = onCleanup(@() fclose(fid)); %#ok<NASGU>
    p = @(varargin) fprintf(fid, varargin{:});

    p('# 사양 대조 — 사양표 ↔ 덤프\n\n');
    p('- 사양표: `%s`\n- 덤프: `%s`\n- 생성: `compare_spec.m` %s\n', rep.spec, rep.dump, datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    if ~isempty(spec.model), p('- 대상: `%s`\n', spec.model); end
    p('\n> 정본은 **사양표**다. 「빠짐」= 사양에 있고 모델에 없음, 「남음」= 모델에 있고 사양에 없음, 「불일치」= 둘 다 있는데 값이 다름.\n');
    p('> Junction 은 이름으로 맞추지 않고 익명(`#J`)으로 대조한다 — 어느 Junction 인지는 보지 않는다(알려진 한계).\n\n');
    p('## 판정: **%s** — 불일치 합계 %d\n\n', ternary(rep.ok, '통과', '실패'), rep.total);

    p('| Chart | State (사양/덤프) | 빠짐 | 남음 | 불일치 | 전이 (사양/덤프) | 빠짐 | 남음 | default (사양/덤프) | 빠짐 | 남음 | 속성 불일치 | Junction (사양/덤프, 정보) |\n');
    p('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n');
    for c = 1:numel(rep.chart)
        r = rep.chart(c);
        p('| `%s` | %d/%d | %d | %d | %d | %d/%d | %d | %d | %d/%d | %d | %d | %d | %d/%d |\n', r.chart, ...
            r.nStateSpec, r.nStateDump, numel(r.missingStates), numel(r.extraStates), size(r.stateMismatch,1), ...
            r.nTransSpec, r.nTransDump, numel(r.missingTrans), numel(r.extraTrans), ...
            r.nDefSpec, r.nDefDump, numel(r.missingDefaults), numel(r.extraDefaults), ...
            size(r.propMismatch,1), r.junctionSpec, r.junctionDump);
    end
    p('\n');
    if ~isempty(rep.missingCharts), p('- 사양에만 있는 Chart: %s\n', strjoin(cellfun(@(x) ['`' x '`'], rep.missingCharts, 'UniformOutput', false), ', ')); end
    if ~isempty(rep.extraCharts),   p('- 덤프에만 있는 Chart: %s\n', strjoin(cellfun(@(x) ['`' x '`'], rep.extraCharts,   'UniformOutput', false), ', ')); end

    for c = 1:numel(rep.chart)
        r = rep.chart(c);
        if r.count == 0, continue; end
        p('\n## `%s` — %d건\n\n', r.chart, r.count);
        list(p, '사양에 있고 모델에 없는 State', r.missingStates);
        list(p, '모델에 있고 사양에 없는 State', r.extraStates);
        if ~isempty(r.stateMismatch)
            p('### State 불일치\n\n| State | 항목 | 사양 | 모델 |\n| --- | --- | --- | --- |\n');
            for k = 1:size(r.stateMismatch,1)
                p('| `%s` | %s | `%s` | `%s` |\n', r.stateMismatch{k,1}, r.stateMismatch{k,2}, md(r.stateMismatch{k,3}), md(r.stateMismatch{k,4}));
            end
            p('\n');
        end
        list(p, '사양에 있고 모델에 없는 전이 (출발 → 도착 | 순서 | 라벨)', r.missingTrans);
        list(p, '모델에 있고 사양에 없는 전이', r.extraTrans);
        list(p, '사양에 있고 모델에 없는 default', r.missingDefaults);
        list(p, '모델에 있고 사양에 없는 default', r.extraDefaults);
        if ~isempty(r.propMismatch)
            p('### Chart 속성 불일치\n\n| 항목 | 사양 | 모델 |\n| --- | --- | --- |\n');
            for k = 1:size(r.propMismatch,1)
                p('| %s | `%s` | `%s` |\n', r.propMismatch{k,1}, md(r.propMismatch{k,2}), md(r.propMismatch{k,3}));
            end
            p('\n');
        end
    end
end

function list(p, title, items)
    if isempty(items), return; end
    p('### %s (%d)\n\n', title, numel(items));
    for k = 1:numel(items), p('- `%s`\n', md(items{k})); end
    p('\n');
end

function s = md(s)
    s = char(string(s));
    s = strrep(s, newline, ' ⏎ ');
    s = strrep(s, '|', '\|');
end
