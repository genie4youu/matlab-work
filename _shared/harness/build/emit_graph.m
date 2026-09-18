function G = emit_graph(dumpDir, outFile)
%EMIT_GRAPH  덤프(JSON)를 읽어 그래프를 만들고 ⓐ영향범위·ⓑ구조검증을 낸다.
%
%   G = emit_graph('C:\...\20260804\_덤프')
%   G = emit_graph(dumpDir, fullfile(dumpDir,'graph.json'))
%
%   왜 자체 그래프인가
%   ─────────────────
%   graphify 는 `.slx` 를 지원하지 않는다(`.m` 도 건너뛴다). 그래서 그래프 기질을
%   사갈 수 없고 덤프에서 직접 만든다. 다행히 재료는 이미 있다 —
%   State/Junction 이 노드, Transition 이 에지다.
%
%   용도는 둘로 고정했다 (사용자 확정, 2026-09-07)
%     ⓐ 변경 영향 분석  이 State 를 고치면 어디가 흔들리나
%     ⓑ 구조 검증      도달 불가 · 나가는 전이 없음 · default 없음 · 고아 Junction
%   ⓒ 시각화는 목적으로 두지 않는다. 앞의 둘이 서면 부산물로 나온다.
%
%   🔴 판정마다 「대상 N / 위반 M」을 낸다.
%      「0건」이 「없다」인지 「0건을 검사했다」인지 구분되지 않으면 판정이 아니다.
%      이 볼트는 「73/73 통과·미기재 0」이 실제로는 16개 미완이었던 적이 있다.
%
%   ⚠️ 진단이 이미 잡는 것과 겹친다. 실측(2026-09-08)으로 ExampleModel 은
%      `SFUnreachableExecutionPathDiag` 를 포함해 6/6 이 `error` 다. 즉 도달 불가는
%      컴파일이 이미 막는다. 이 함수의 값은 **Chart 별로 어디가 왜 그런지 목록으로
%      보여주는 것**이지 「우리가 처음 잡았다」가 아니다.

    if nargin < 1 || isempty(dumpDir)
        dumpDir = fullfile(pwd, '_덤프');
    end
    if nargin < 2 || isempty(outFile)
        outFile = fullfile(dumpDir, 'graph.json');
    end

    nodes   = read_json(fullfile(dumpDir, 'nodes.json'));
    edges   = read_json(fullfile(dumpDir, 'edges.json'));
    chartsJ = read_json(fullfile(dumpDir, 'charts.json'));
    if isempty(nodes)
        error('emit_graph:noNodes', ...
            'nodes.json 이 비었거나 없다: %s\n  emit_dump 를 먼저 돌린다.', dumpDir);
    end

    fprintf('\n──────── 그래프 (emit_graph) ────────\n');
    fprintf('  노드 %d · 에지 %d\n', numel(nodes), numel(edges));

    charts = unique({nodes.chart});
    G = struct();
    G.dumpDir  = dumpDir;
    G.built    = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
    G.counts   = struct('nodes', numel(nodes), 'edges', numel(edges), 'charts', numel(charts));
    G.findings = emptyFinding();
    G.perChart = struct('chart',{},'states',{},'transitions',{},'junctions',{}, ...
                        'decomposition',{},'checked',{},'skipped',{},'violations',{});

    for c = 1:numel(charts)
        cp = charts{c};
        nSel = nodes(strcmp({nodes.chart}, cp));
        if isempty(edges), eSel = edges; else, eSel = edges(strcmp({edges.chart}, cp)); end

        stMask = strcmp({nSel.kind}, 'State');
        st = nSel(stMask);
        ju = nSel(~stMask);

        stPaths = {st.path};
        if isempty(eSel)
            srcs = {}; dsts = {}; isDef = logical([]);
        else
            srcs  = {eSel.src};
            dsts  = {eSel.dst};
            isDef = logical([eSel.isDefault]);
        end

        nCheck = 0; viol = 0; nSkip = 0;

        % 🔴 병렬(AND) 분해를 빼놓으면 검사가 통째로 오탐이 된다 (2026-09-08 실측).
        %    State 의 `decomposition` 필드는 **그 State 의 자식들**이 어떻게 분해되는지를
        %    말한다. 그 State 자신이 병렬인지는 **부모**가 정하고, 부모가 없으면
        %    **Chart 의 Decomposition** 이 정한다.
        %    처음 판에서 Example_Fault(Chart=PARALLEL_AND, State 7·Transition 0)가
        %    검사 14건 중 14건 지적으로 나왔다. 병렬 상태는 동시에 활성화되므로
        %    전이가 없는 것이 정상이다. 오탐은 미탐만큼 위험하다.
        cDec  = chartDecomp(chartsJ, cp);
        stDec = containers.Map('KeyType','char','ValueType','char');
        for i = 1:numel(st), stDec(st(i).path) = st(i).decomposition; end

        % ── ⓑ-1. 도달 불가 State ─────────────────────
        %    들어오는 Transition 도 없고 default 대상도 아닌 State.
        for i = 1:numel(st)
            p = st(i).path;
            if isParallelMember(p, stDec, cDec), nSkip = nSkip + 1; continue; end
            nCheck = nCheck + 1;
            if any(strcmp(dsts, p)), continue; end
            sibDefault = false;
            for k = 1:numel(dsts)
                if isDef(k) && strcmp(dsts{k}, p), sibDefault = true; break; end
            end
            if sibDefault, continue; end
            viol = viol + 1;
            G.findings(end+1) = mkFinding(cp, 'unreachable_state', p, ...
                '들어오는 Transition 도 default 대상도 아니다');
        end

        % ── ⓑ-2. 나가는 전이가 없는 State ────────────
        %    최종 상태로 의도했을 수 있으므로 **경고**다.
        %
        %    🔴 2026-09-08 결함 2건 수정 (model-auditor·graph-analyst 가 독립으로 찾음)
        %    ① 복합 State 를 `continue` 로 건너뛰면서 **nSkip 을 안 올렸다.**
        %       검사도 안 하고 제외에도 안 잡혀 **분모에서 조용히 사라졌다.**
        %       「말없이 줄어든 대상은 사라진 대상이다」를 내 코드가 어겼다.
        %    ② **부모 계층의 탈출을 안 따라갔다.** 자기 경로에서 출발하는 전이만
        %       봐서, 부모가 나가는 전이를 가진 State 를 「갇혔다」고 잡았다
        %       (PC·VC 의 S_Run.S_Gen_Trajectory.S_Set_Reference — 부모 edge 1702/1787).
        %       병렬 분해를 몰랐던 것과 같은 계열이다: **계층을 안 따라간다.**
        for i = 1:numel(st)
            p = st(i).path;
            if any(startsWith(stPaths, [p '.']))
                nSkip = nSkip + 1;      % 복합 State — 안에서 도는 것이 정상
                continue
            end
            if isParallelMember(p, stDec, cDec), nSkip = nSkip + 1; continue; end
            if ancestorHasExit(p, srcs)
                nSkip = nSkip + 1;      % 조상이 나가므로 갇힌 것이 아니다
                continue
            end
            nCheck = nCheck + 1;
            if ~any(strcmp(srcs, p))
                viol = viol + 1;
                G.findings(end+1) = mkFinding(cp, 'no_outgoing', p, ...
                    '나가는 Transition 이 없고 조상에도 탈출 전이가 없다 (최종 상태로 의도한 것인지 확인)');
            end
        end

        % ── ⓑ-3. 하위 State 를 가진 부모에 default 가 있는가 ──
        %    부모가 자식을 **병렬**로 분해하면 default 가 필요 없다.
        parents = unique(parentOf(stPaths));
        for i = 1:numel(parents)
            pr = parents{i};
            if isempty(pr), continue; end
            if isKey(stDec, pr) && strcmp(stDec(pr), 'PARALLEL_AND')
                nSkip = nSkip + 1; continue
            end
            nCheck = nCheck + 1;
            kids = stPaths(strcmp(parentOf(stPaths), pr));
            % 🔴 default 가 **Junction 을 경유**하는 것이 정상이고 흔하다 (2026-09-08 실측).
            %    `default → Junction → [조건] → State` 로 초기 상태를 조건으로 고른다.
            %    처음 판은 default 의 목적지만 보고 Junction 을 따라가지 않아
            %    Debounce/S_Enabled(default→J1457·J1442)와
            %    Example_Main_SF/S_PC_Mode_Brake_Control.S_Run(default→J1631)을 오탐했다.
            %    진단이 `SFNoUnconditionalDefaultTransitionDiag=error` 인데 이 모델이
            %    통과한다는 사실이 내 판정이 틀렸다는 반증이었다.
            juNames = {ju.name};
            hasDef = false;
            for k = 1:numel(dsts)
                if ~isDef(k), continue; end
                if reachesVia(dsts{k}, kids, srcs, dsts, juNames)
                    hasDef = true; break
                end
            end
            if ~hasDef
                viol = viol + 1;
                G.findings(end+1) = mkFinding(cp, 'no_default_transition', pr, ...
                    sprintf('하위 State %d개인데 default transition 이 없다', numel(kids)));
            end
        end

        % ── ⓑ-4. 고아 Junction ───────────────────────
        for i = 1:numel(ju)
            nCheck = nCheck + 1;
            nm = ju(i).name;
            if ~any(strcmp(srcs, nm)) && ~any(strcmp(dsts, nm))
                viol = viol + 1;
                G.findings(end+1) = mkFinding(cp, 'orphan_junction', nm, ...
                    '연결된 Transition 이 없다');
            end
        end

        % ── ⓑ-5. 끝점을 못 읽은 에지 ─────────────────
        for k = 1:numel(eSel)
            nCheck = nCheck + 1;
            if strcmp(eSel(k).srcType,'<읽기실패>') || strcmp(eSel(k).dstType,'<읽기실패>')
                viol = viol + 1;
                G.findings(end+1) = mkFinding(cp, 'unreadable_endpoint', ...
                    sprintf('T%d', eSel(k).id), '끝점을 읽지 못했다 — 「없다」가 아니라 「못 읽었다」');
            end
        end

        G.perChart(end+1) = struct('chart', cp, 'states', numel(st), ...
            'transitions', numel(eSel), 'junctions', numel(ju), ...
            'decomposition', cDec, ...
            'checked', nCheck, 'skipped', nSkip, 'violations', viol);

        fprintf('  %-42s %-13s 검사 %3d · 제외 %2d · 지적 %2d\n', ...
            shorten(cp,42), cDec, nCheck, nSkip, viol);
    end

    % ── 요약 ──────────────────────────────────────────
    G.summary = struct();
    kinds = {'unreachable_state','no_outgoing','no_default_transition', ...
             'orphan_junction','unreadable_endpoint'};
    for i = 1:numel(kinds)
        if isempty(G.findings)
            G.summary.(kinds{i}) = 0;
        else
            G.summary.(kinds{i}) = sum(strcmp({G.findings.kind}, kinds{i}));
        end
    end
    G.checked    = sum([G.perChart.checked]);
    G.skipped    = sum([G.perChart.skipped]);
    G.violations = numel(G.findings);

    fprintf('\n  ── 판정 (대상 N / 위반 M) ──\n');
    for i = 1:numel(kinds)
        fprintf('     %-24s %d\n', kinds{i}, G.summary.(kinds{i}));
    end
    fprintf('     %-24s %d 검사 / %d 지적 (병렬이라 제외 %d)\n', ...
        '합계', G.checked, G.violations, G.skipped);
    if G.checked == 0
        fprintf('  🔴 검사 대상이 0 이다. 「지적 0건」은 「깨끗하다」가 아니라 「아무것도 안 봤다」다.\n');
    end

    txt = jsonencode(G, 'PrettyPrint', true);
    fid = fopen(outFile, 'w', 'n', 'UTF-8');
    if fid < 0, error('emit_graph:write', '파일을 열지 못했다: %s', outFile); end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fwrite(fid, unicode2native(txt,'UTF-8'), 'uint8');
    fprintf('  → %s\n', outFile);
end


% ══════════════════════════════════════════════════════

function S = read_json(p)
    S = [];
    if ~isfile(p), return; end
    fid = fopen(p, 'r', 'n', 'UTF-8');
    if fid < 0, return; end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    raw = fread(fid, '*char')';
    if isempty(strtrim(raw)), return; end
    try
        d = jsondecode(raw);
    catch
        return
    end
    if iscell(d)
        try, d = [d{:}]; catch, end
    end
    S = reshape(d, 1, []);
end

function F = emptyFinding()
    F = struct('chart', {}, 'kind', {}, 'target', {}, 'why', {});
end

function f = mkFinding(chart, kind, target, why)
    f = struct('chart', chart, 'kind', kind, 'target', target, 'why', why);
end

function tf = reachesVia(startDst, targets, srcs, dsts, juNames)
%REACHESVIA  startDst 에서 출발해 **Junction 만 거쳐** targets 중 하나에 닿는가.
%
%   Stateflow 의 `default → Junction → [조건] → State` 를 따라가기 위한 것이다.
%   Junction 이 아닌 노드에 닿으면 거기서 멈춘다 — State 를 지나 계속 가면
%   「초기 진입」이 아니라 그냥 도달 가능성이 되어 판정의 뜻이 달라진다.
    tf = false;
    queue = {startDst};
    seen  = {};
    for guard = 1:1000                     % 순환이 있어도 멈춘다
        if isempty(queue), return; end
        cur = queue{1};
        queue(1) = [];
        if any(strcmp(targets, cur)), tf = true; return; end
        if any(strcmp(seen, cur)), continue; end
        seen{end+1} = cur; %#ok<AGROW>
        if ~any(strcmp(juNames, cur)), continue; end   % Junction 일 때만 더 간다
        nxt = dsts(strcmp(srcs, cur));
        if ~isempty(nxt), queue = [queue, reshape(nxt,1,[])]; end %#ok<AGROW>
    end
end

function d = chartDecomp(chartsJ, chartPath)
%CHARTDECOMP  charts.json 에서 그 Chart 의 Decomposition 을 찾는다.
%   못 찾으면 '<미확인>' 을 준다. 「없다」로 두면 병렬 판정이 조용히 틀린다.
    d = '<미확인>';
    if isempty(chartsJ), return; end
    for i = 1:numel(chartsJ)
        if strcmp(chartsJ(i).chart, chartPath)
            try
                d = chartsJ(i).props.Decomposition;
            catch
                d = '<미확인>';
            end
            return
        end
    end
end

function tf = ancestorHasExit(p, srcs)
%ANCESTORHASEXIT  조상 중 하나라도 나가는 전이를 갖는가.
%   Stateflow 에서 부모가 나가면 **자식도 함께 빠진다.** 그러므로 자기 경로에서
%   출발하는 전이만 보고 「갇혔다」고 하면 오탐이다 (2026-09-08 실측:
%   PC·VC 의 S_Run.S_Gen_Trajectory.S_Set_Reference — 부모 edge 1702/1787 이 탈출).
    tf = false;
    d = strfind(p, '.');
    for k = numel(d):-1:1
        anc = p(1:d(k)-1);
        if any(strcmp(srcs, anc)), tf = true; return; end
    end
end

function tf = isParallelMember(p, stDec, chartDec)
%ISPARALLELMEMBER  이 State 가 **병렬로 동시 활성화되는가**.
%   판정은 자기 자신이 아니라 **부모**가 한다. 부모가 없으면 Chart 가 한다.
%   State 의 decomposition 필드는 「내 자식들이 어떻게 분해되는가」이므로
%   자기 자신의 병렬 여부와 무관하다 — 이것을 혼동해 처음 판이 오탐투성이였다.
    d = strfind(p, '.');
    if isempty(d)
        tf = strcmp(chartDec, 'PARALLEL_AND');       % 최상위 → Chart 가 정한다
        return
    end
    parent = p(1:d(end)-1);
    if isKey(stDec, parent)
        tf = strcmp(stDec(parent), 'PARALLEL_AND');
    else
        tf = false;      % 부모를 못 찾으면 병렬이라고 단정하지 않는다
    end
end

function P = parentOf(paths)
%PARENTOF  'A.B.C' -> 'A.B'. 최상위면 ''.
    P = cell(size(paths));
    for i = 1:numel(paths)
        d = strfind(paths{i}, '.');
        if isempty(d), P{i} = ''; else, P{i} = paths{i}(1:d(end)-1); end
    end
end

function s = shorten(s, n)
    if numel(s) > n, s = ['…' s(end-n+2:end)]; end
end
