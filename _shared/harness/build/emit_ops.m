function opsFile = emit_ops(spec, outFile)
%EMIT_OPS  저작 **계획**을 낸다. 모델을 바꾸지 않는다.
%
%   emit_ops(spec)
%   emit_ops(spec, 'C:\...\_덤프\ops.json')
%
%   왜 생성과 적용을 나누나
%   ─────────────────────
%   확정사항 2 는 「골격은 Claude, 세부와 최종 판단은 사용자」다. 그런데 계획과
%   적용이 같은 흐름 안에 있으면 승인이 형식이 되고 곧바로 편집으로 이어진다.
%   **파일을 사이에 두면 승인이 구조가 된다** — 사람이 `ops.json` 을 읽고,
%   따로 `apply_ops` 를 불러야 모델이 바뀐다.
%   이 볼트의 원칙과 같은 기제다: 「부탁이 아니라 도구를 안 주는 것으로 막는다.」
%
%   🔴 이 함수는 MATLAB 모델을 열지도 바꾸지도 않는다.
%      계획을 세우는 데 모델 정보가 필요하면 **덤프(JSON)를 읽는다.**
%
%   spec — 무엇을 만들 것인가 (struct)
%   ─────────────────────────────────
%     spec.chart      대상 Chart 경로            'Example_Main_SF/SF'
%     spec.scope      편집 범위                  Chart · State · Box 중 하나의 경로
%     spec.states     추가할 State  {name, label, parent}
%     spec.transitions 추가할 Transition {src, dst, label}   src 가 '' 이면 default
%     spec.note       이 회차에서 무엇을 왜 하는가 (사람이 읽는다)
%
%   내는 것 — ops.json
%   ─────────────────
%     ops(k).op        'add_block' | 'connect' | 'configure'
%     ops(k).domain    'SF'  (Stateflow. Simulink 는 아직 다루지 않는다)
%     ops(k).scope     적용 범위
%     ops(k).args      model_edit 에 넘길 인자
%     ops(k).why       왜 이 op 이 필요한가 — **사람이 승인할 때 읽는 칸**
%     ops(k).reversible 되돌릴 수 있는가
%
%   🔴 저작의 정규 경로는 `model_edit` 이다.
%      `Stateflow.State(ch)` 직접 호출은 되기는 하지만 `building-simulink-models`
%      스킬이 **명시적으로 금지**한다 — autolayout · undo tracking · error recovery 를
%      건너뛰기 때문이다. 이 함수가 내는 op 는 `model_edit` 인자 형태다.
%
%   ⚠️ 알려진 제약 (조사 결과, 2026-09-07)
%      - SF scope 가 될 수 있는 것은 **Chart · State · Box 셋뿐**이다
%      - Chart 블록 추가와 내부 채우기는 **반드시 2회 호출**이다
%      - **subchart 경계를 넘는 super transition 은 지원하지 않는다** →
%        composite state 를 기본으로 하고 subchart 승격은 사람이 GUI 에서 한다
%      - 액션은 `LabelString` 이 **유일한 쓰기 경로**다.
%        `EntryAction`·`Condition` 등은 READ-ONLY 다

    if nargin < 1 || isempty(spec)
        error('emit_ops:noSpec', ...
            ['무엇을 만들지(spec)가 필요하다.\n' ...
             '  예: s.chart=''Example_Main_SF/SF''; s.scope=''Example_Main_SF/SF'';\n' ...
             '      s.states = struct(''name'',''S_New'',''label'',''en: x=1;'',''parent'','''');\n' ...
             '      emit_ops(s)']);
    end
    if nargin < 2 || isempty(outFile)
        outFile = fullfile(pwd, '_덤프', 'ops.json');
    end
    d = fileparts(outFile);
    if ~isempty(d) && ~isfolder(d), mkdir(d); end

    fprintf('\n──────── 저작 계획 (emit_ops) ────────\n');
    fprintf('  🔴 이 단계는 모델을 바꾸지 않는다. 계획만 낸다.\n');

    req = {'chart','scope'};
    for i = 1:numel(req)
        if ~isfield(spec, req{i}) || isempty(spec.(req{i}))
            error('emit_ops:missing', 'spec.%s 가 필요하다.', req{i});
        end
    end

    ops = struct('op',{},'domain',{},'scope',{},'args',{},'why',{},'reversible',{});
    warns = {};

    % ── State 추가 ────────────────────────────────────
    if isfield(spec,'states') && ~isempty(spec.states)
        S = spec.states;
        for k = 1:numel(S)
            s = S(k);
            nm = getf(s,'name','');
            if isempty(nm)
                warns{end+1} = sprintf('%d번째 State 에 name 이 없다 — 건너뛴다', k); %#ok<AGROW>
                continue
            end
            parent = getf(s,'parent','');
            if isempty(parent), sc = spec.scope; else, sc = parent; end
            a = struct();
            a.type = 'State';
            a.name = nm;
            lbl = getf(s,'label','');
            if ~isempty(lbl)
                % 🔴 LabelString 이 액션의 유일한 쓰기 경로다.
                %    State 라벨 형식: 이름\n en: … \n du: … \n ex: …
                a.LabelString = ensureLabelHasName(lbl, nm);
            end
            ops(end+1) = mkOp('add_block','SF', sc, a, ...
                sprintf('State %s 를 %s 아래에 만든다', nm, shortScope(sc)), true); %#ok<AGROW>
        end
    end

    % ── Transition 추가 ───────────────────────────────
    if isfield(spec,'transitions') && ~isempty(spec.transitions)
        Tr = spec.transitions;
        for k = 1:numel(Tr)
            t = Tr(k);
            dst = getf(t,'dst','');
            if isempty(dst)
                warns{end+1} = sprintf('%d번째 Transition 에 dst 가 없다 — 건너뛴다', k); %#ok<AGROW>
                continue
            end
            src = getf(t,'src','');
            % model_edit 의 portless 문법. src 가 비면 default transition 이다.
            if isempty(src)
                expr = sprintf('? -> #%s', dst);
                why  = sprintf('%s 를 초기 상태로 삼는 default transition', dst);
            else
                expr = sprintf('#%s -> #%s', src, dst);
                why  = sprintf('%s 에서 %s 로 가는 전이', src, dst);
            end
            a = struct('expr', expr);
            lbl = getf(t,'label','');
            if ~isempty(lbl), a.LabelString = lbl; end
            % 실행순서가 곧 if 의 순서다 — 사양표(read_spec)에 있으면 계획에 싣는다 (2026-09-16)
            eo = getf(t,'executionOrder',[]);
            if isnumeric(eo) && isscalar(eo) && ~isnan(eo), a.ExecutionOrder = eo; end
            ops(end+1) = mkOp('connect','SF', spec.scope, a, why, true); %#ok<AGROW>
        end
    end

    if isempty(ops)
        error('emit_ops:emptyPlan', ...
            '계획이 비었다. 만들 State 도 Transition 도 없다면 이 회차는 저작 회차가 아니다.');
    end

    % ── 회차 상한 ─────────────────────────────────────
    %    🔴 `model_edit` 한 호출의 op 개수 상한은 **문서에 없고 실측되지 않았다.**
    %       그래서 숫자를 단정하지 않고, 넘으면 「나눠서 하라」고 알리기만 한다.
    %       R14(한 번에 하나)의 취지는 「뒤로 갈수록 부실해지는 것」을 막는 것이다.
    SOFT_LIMIT = 12;
    if numel(ops) > SOFT_LIMIT
        warns{end+1} = sprintf(['op 이 %d개다. 한 회차 권장 상한 %d개를 넘는다 — ' ...
            '나눠서 도는 편이 낫다. (상한 근거는 R14 이고, model_edit 자체의 ' ...
            '기술적 한계는 미확인이다)'], numel(ops), SOFT_LIMIT); %#ok<AGROW>
    end

    % ── 계획 파일 ─────────────────────────────────────
    plan = struct();
    plan.created    = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
    plan.chart      = spec.chart;
    plan.scope      = spec.scope;
    plan.note       = getf(spec,'note','(적지 않음)');
    plan.applied    = false;      % apply_ops 가 true 로 바꾼다
    plan.ops        = ops;
    plan.warnings   = reshape(warns,1,[]);
    plan.counts     = struct('ops', numel(ops), 'warnings', numel(warns));

    txt = jsonencode(plan, 'PrettyPrint', true);
    fid = fopen(outFile, 'w', 'n', 'UTF-8');
    if fid < 0, error('emit_ops:write','파일을 열지 못했다: %s', outFile); end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fwrite(fid, unicode2native(txt,'UTF-8'), 'uint8');
    opsFile = outFile;

    % ── 사람이 읽을 요약 ──────────────────────────────
    fprintf('\n  대상 Chart : %s\n', plan.chart);
    fprintf('  편집 범위  : %s\n', plan.scope);
    fprintf('  회차 목적  : %s\n\n', plan.note);
    fprintf('  %-4s %-12s %-28s %s\n', '#', 'op', '무엇을', '왜');
    fprintf('  %s\n', repmat('-', 1, 96));
    for i = 1:numel(ops)
        fprintf('  %-4d %-12s %-28s %s\n', i, ops(i).op, opTarget(ops(i)), ops(i).why);
    end
    if ~isempty(warns)
        fprintf('\n  ⚠ 경고 %d건\n', numel(warns));
        for i = 1:numel(warns), fprintf('     %s\n', warns{i}); end
    end
    fprintf('\n  → %s\n', outFile);
    fprintf('\n  🔴 여기서 멈춘다. 모델은 아직 바뀌지 않았다.\n');
    fprintf('     위 계획을 사람이 읽고, 맞으면 다음을 부른다:\n');
    fprintf('        apply_ops(''%s'', ''Dry'', true)    ← 먼저 모의 적용으로 확인\n', outFile);
    fprintf('        apply_ops(''%s'')                   ← 실제 적용\n\n', outFile);
end


% ══════════════════════════════════════════════════════

function o = mkOp(op, domain, scope, args, why, reversible)
    o = struct('op', op, 'domain', domain, 'scope', scope, ...
               'args', args, 'why', why, 'reversible', reversible);
end

function v = getf(S, f, d)
    v = d;
    if isstruct(S) && isfield(S, f) && ~isempty(S.(f))
        v = S.(f);
    end
end

function s = ensureLabelHasName(lbl, nm)
%ENSURELABELHASNAME  State 의 LabelString 은 **첫 줄이 이름**이다.
%   이름 없이 액션만 주면 State 이름이 사라지거나 액션이 이름으로 해석된다.
    lbl = char(lbl);
    first = strtok(lbl, newline);
    first = strtrim(first);
    if strcmp(first, nm) || startsWith(first, [nm ' ']) || startsWith(first, [nm newline])
        s = lbl;
    else
        s = [nm newline lbl];
    end
end

function t = opTarget(o)
    t = '';
    try
        if isfield(o.args,'name'), t = o.args.name;
        elseif isfield(o.args,'expr'), t = o.args.expr;
        end
    catch
        t = '';
    end
    if numel(t) > 27, t = ['…' t(end-25:end)]; end
end

function s = shortScope(s)
    i = strfind(s, '/');
    if ~isempty(i) && numel(s) > 24, s = ['…' s(i(end):end)]; end
end
