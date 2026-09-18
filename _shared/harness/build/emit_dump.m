function meta = emit_dump(root, outDir)
%EMIT_DUMP  모델의 Stateflow Chart 전부를 **기계가 읽는 JSON** 으로 낸다.
%
%   meta = emit_dump('ExampleModel')
%   meta = emit_dump('ExampleModel', 'C:\...\20260804\_덤프')
%
%   왜 JSON 인가
%   ───────────
%   MATLAB MCP 는 사용자가 열어둔 **세션 하나**에 붙는다. 서브에이전트를 여럿
%   띄워도 모델을 봐야 하는 순간 전부 한 줄로 서서 기다리므로 병렬의 이득이 0 이 된다.
%   → **메인 세션만 MATLAB 을 돌려 파일로 뽑고, 에이전트들은 그 파일을 병렬로 읽는다.**
%   이 함수가 그 「덤프 계층」이다.
%
%   내는 파일
%   ────────
%     charts.json   Chart 속성 (Decomposition·ActionLanguage·SampleTime …)
%     nodes.json    State + Junction — 그래프의 노드
%     edges.json    Transition — 그래프의 에지
%     meta.json     수집 맥락: 모델·시각·열거 방법·개수·경고
%
%   🔴 열거를 새로 짜지 않는다 (R19).
%      Chart 목록은 `vault_units` 하나에서만 온다. 전에는 gen_vault_tree ·
%      gen_vault_charts · audit_coverage 가 각자 열거하다 갈라졌고, `sfroot` 로
%      세던 것은 그때 열려 있는 모델에 따라 3/7/9 로 흔들렸다 (R18).
%
%   🔴 LabelString 은 원문 그대로 담는다.
%      `dump_chart` 의 oneline() 은 개행을 ' ; ' 로 압축하는데, MATLAB 의 `...` 는
%      줄이어짐이라 `[A ... \n ~= B]`(하나의 조건)가 `[A ... ; ~= B]` 가 된다.
%      실측: Example_Main_SF 의 Transition 95개 중 17개가 이 영향을 받는다.

    if nargin < 1 || isempty(root)
        error('emit_dump:noArg', '루트 모델 이름이 필요하다. 예: emit_dump(''ExampleModel'')');
    end
    root = char(root);
    if nargin < 2 || isempty(outDir)
        outDir = fullfile(pwd, '_덤프');
    end
    if ~isfolder(outDir), mkdir(outDir); end

    fprintf('\n──────── 덤프 (emit_dump) ────────\n');

    % ── 1. Chart 열거 — vault_units 단일 정의 ─────────
    U = vault_units(root);
    isChart = strcmp({U.kind}, 'Stateflow Chart');
    UC = U(isChart);
    fprintf('  분석 단위 %d개 중 Stateflow Chart %d개 (vault_units 기준)\n', numel(U), numel(UC));
    if isempty(UC)
        warning('emit_dump:noChart', 'Chart 가 하나도 없다. 모델이 로드됐는지 확인한다.');
    end

    % ── 2. 수집 ───────────────────────────────────────
    charts = {};
    nodes  = {};
    edges  = {};
    warns  = {};
    for i = 1:numel(UC)
        p = UC(i).path;
        try
            C = collect_chart(p);
        catch e
            warns{end+1} = sprintf('%s 수집 실패: %s', p, e.message); %#ok<AGROW>
            fprintf('  🔴 %s — %s\n', p, e.message);
            continue
        end

        ch = struct();
        ch.chart  = C.path;
        ch.name   = C.name;
        ch.model  = C.model;
        ch.props  = C.props;
        % 🔴 2026-09-08 결함 수정. 처음에는 `counts` 만 담아 **Data 이름·Scope 가
        %    덤프에 없었다.** 그래서 에이전트가 「이 변수가 입력인가 지역인가」를
        %    판정하지 못하고 「덤프 안에 쓰기가 없으니 입력으로 **추정**」에 머물렀다.
        %    Scope 는 손 변환에서 변수 선언을 가르는 값이므로 반드시 담는다.
        ch.data   = C.data;
        ch.events = C.events;
        ch.counts = C.counts;
        charts{end+1} = ch; %#ok<AGROW>

        for k = 1:numel(C.states)
            s = C.states(k);
            n = struct();
            n.chart          = C.path;
            n.kind           = 'State';
            n.id             = s.id;
            n.name           = s.name;
            n.path           = s.path;
            n.parent         = s.parent;
            n.decomposition  = s.decomposition;
            n.executionOrder = s.executionOrder;
            n.isSubchart     = s.isSubchart;
            n.label          = s.label;      % 원문
            nodes{end+1} = n; %#ok<AGROW>
        end
        for k = 1:numel(C.junctions)
            j = C.junctions(k);
            n = struct();
            n.chart          = C.path;
            n.kind           = 'Junction';
            n.id             = j.id;
            n.name           = sprintf('J%d', j.id);
            n.path           = sprintf('J%d', j.id);
            n.parent         = j.parent;
            n.decomposition  = '';
            n.executionOrder = NaN;
            n.isSubchart     = false;
            n.label          = j.type;
            nodes{end+1} = n; %#ok<AGROW>
        end
        for k = 1:numel(C.transitions)
            t = C.transitions(k);
            e2 = struct();
            e2.chart          = C.path;
            e2.id             = t.id;
            e2.src            = t.src;
            e2.dst            = t.dst;
            e2.srcType        = t.srcType;
            e2.dstType        = t.dstType;
            e2.isDefault      = t.isDefault;
            e2.executionOrder = t.executionOrder;
            e2.label          = t.label;     % 원문
            edges{end+1} = e2; %#ok<AGROW>
        end

        if C.counts.warnings > 0
            for w = 1:numel(C.warnings)
                warns{end+1} = sprintf('%s: %s', C.path, C.warnings{w}); %#ok<AGROW>
            end
        end
        fprintf('  %-44s State %3d · Trans %3d · Junc %2d\n', ...
            shorten(C.path, 44), C.counts.states, C.counts.transitions, C.counts.junctions);
    end

    % ── 3. meta ───────────────────────────────────────
    meta = struct();
    meta.root        = root;
    meta.collected   = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
    meta.release     = release_str();
    % 🔴 열거의 **분모**를 남긴다 (model-auditor 지적, 2026-09-08).
    %    「7개를 수집했다」만 있으면 「몇 개 중 7개인가」를 알 수 없고,
    %    빠진 것이 있어도 재구성할 수 없다. 분모 없는 수는 판정이 아니다.
    meta.enumeration = sprintf(['vault_units(root) 의 kind==''Stateflow Chart'' — ' ...
        '분석 단위 %d개 중 Chart %d개 (SubSystem·ModelReference %d개는 대상 아님)'], ...
        numel(U), numel(UC), numel(U) - numel(UC));
    meta.units_total   = numel(U);
    meta.units_chart   = numel(UC);
    meta.units_other   = numel(U) - numel(UC);
    meta.collect_failed = numel(warns);   % 수집 자체가 실패한 Chart 수와 구분되게 둔다
    meta.models      = reshape(cellstr(string(unique({UC.model}))), 1, []);
    meta.counts      = struct('charts', numel(charts), 'nodes', numel(nodes), ...
                              'edges',  numel(edges),  'warnings', numel(warns));
    meta.warnings    = reshape(warns, 1, []);
    % 🔴 개수는 스크립트가 센 값이다. 문서에 옮길 때 손으로 다시 세지 않는다.

    % ── 4. 쓰기 ───────────────────────────────────────
    files = struct();
    files.charts = write_json(fullfile(outDir,'charts.json'), charts);
    files.nodes  = write_json(fullfile(outDir,'nodes.json'),  nodes);
    files.edges  = write_json(fullfile(outDir,'edges.json'),  edges);
    files.meta   = write_json(fullfile(outDir,'meta.json'),   meta);
    meta.files = files;

    fprintf('\n  Chart %d · 노드 %d · 에지 %d · 경고 %d\n', ...
        meta.counts.charts, meta.counts.nodes, meta.counts.edges, meta.counts.warnings);
    fprintf('  → %s\n', outDir);
    if meta.counts.warnings > 0
        fprintf('  ⚠ 경고 %d건 — meta.json 의 warnings 를 본다\n', meta.counts.warnings);
    end
end


% ══════════════════════════════════════════════════════

function p = write_json(p, data)
%WRITE_JSON  UTF-8(BOM 없음)로 쓴다.
%   🔴 셀 배열을 그대로 넘기면 jsonencode 가 중첩 배열을 만든다. 요소가 struct 인
%      셀은 struct 배열로 바꿔 「객체의 배열」이 되게 한다. 빈 것은 [] 로 둔다.
    if iscell(data)
        if isempty(data)
            payload = {};
        else
            try
                payload = [data{:}];          % struct 배열로 합친다
            catch
                payload = data;               % 필드가 어긋나면 셀 그대로 (jsonencode 가 처리)
            end
        end
    else
        payload = data;
    end
    txt = jsonencode(payload, 'PrettyPrint', true);
    fid = fopen(p, 'w', 'n', 'UTF-8');
    if fid < 0
        error('emit_dump:write', '파일을 열지 못했다: %s', p);
    end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fwrite(fid, unicode2native(txt, 'UTF-8'), 'uint8');
end

function s = shorten(s, n)
    if numel(s) > n, s = ['…' s(end-n+2:end)]; end
end

function r = release_str()
    r = '';
    try
        v = ver('MATLAB');
        t = regexp(v(1).Release, 'R\d{4}[ab]', 'match', 'once');
        if ~isempty(t), r = t; end
    catch
        r = '';
    end
end
