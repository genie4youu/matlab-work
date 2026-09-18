function rep = apply_ops(opsFile, varargin)
%APPLY_OPS  `emit_ops` 가 낸 계획을 모델에 적용한다. **여기만 모델을 바꾼다.**
%
%   apply_ops('...\_덤프\ops.json', 'Dry', true)    모의 — 아무것도 바꾸지 않는다
%   apply_ops('...\_덤프\ops.json')                 실제 적용
%
%   왜 이 함수가 따로 있나
%   ────────────────────
%   `emit_ops` 는 계획만 내고 멈춘다. 사람이 `ops.json` 을 읽고 **따로 이 함수를
%   불러야** 모델이 바뀐다. 승인을 부탁이 아니라 **구조**로 만든 것이다
%   (확정사항 2·5). 「부탁이 아니라 도구를 안 주는 것으로 막는다」와 같은 기제다.
%
%   🔴 이 함수는 저작 하네스에서 **유일하게 되돌릴 수 없는 일을 하는 자리**다.
%      그래서 방어를 앞에 몰아 둔다. 아래 관문을 하나라도 못 넘으면 시작하지 않는다.
%
%   적용 전 관문
%   ───────────
%     G1  Dry 가 아니면 **작업트리가 깨끗해야** 한다 — 편집 전 상태가 커밋에 있어야
%         무엇이 이번 회차의 변경인지 구분된다. `.slx` 는 바이너리라 되돌릴 수단이
%         커밋과 zip 뿐이다
%     G2  **zip 백업**을 먼저 뜬다. `Copy-Item -Recurse` 는 260자 경로에서 일부만
%         복사되고 에러만 낸다(실측 75개 중 66개) → `Compress-Archive` 를 쓴다
%     G3  `.satk/block-policy.json` 이 있어야 한다 — 없으면 `model_edit` 이
%         **무차단**으로 돈다(`accessControl:"none"`). 회사 모델에서는 정지 관문이다
%     G4  계획이 **아직 적용되지 않았어야** 한다 (`applied:false`). 같은 계획을
%         두 번 적용하면 State 가 중복 생성된다
%     G5  MATLAB **세션이 계획을 만들 때와 같아야** 한다
%
%   🚫 이 함수는 `model_edit` 을 직접 호출하지 않는다.
%      SATK 도구는 MCP 를 통해 Claude 가 부르는 것이고, MATLAB 함수에서
%      부를 수 있는 진입점이 확인되지 않았다(미확인). 그래서 이 함수는
%      **관문을 통과시키고 op 를 MCP 가 쓸 형태로 내놓는 데까지** 한다.
%      실제 편집은 메인 세션이 `mcp__matlab__model_edit` 으로 수행한다.
%      → 이 경계를 지우면 「누가 모델을 바꿨는지」가 불분명해진다.

    p = inputParser;
    p.addParameter('Dry',    false, @islogical);
    p.addParameter('Backup', true,  @islogical);
    p.parse(varargin{:});
    dry    = p.Results.Dry;
    doBack = p.Results.Backup;

    if nargin < 1 || isempty(opsFile) || ~isfile(opsFile)
        error('apply_ops:noFile', ...
            ['계획 파일이 필요하다: %s\n' ...
             '  emit_ops 를 먼저 돌린다.'], char(string(opsFile)));
    end

    plan = read_json(opsFile);
    rep = struct('file', opsFile, 'dry', dry, 'ok', false, 'blocked', {{}}, ...
                 'ops', numel(plan.ops), 'backup', '', 'ready', {{}});

    fprintf('\n──────── 저작 적용 (apply_ops) ────────\n');
    if dry
        fprintf('  🧪 Dry 모드 — 아무것도 바꾸지 않는다. 관문만 확인한다.\n');
    else
        fprintf('  🔴 실제 적용 모드 — 관문을 전부 통과하면 모델이 바뀐다.\n');
    end
    fprintf('  계획   : %s\n', opsFile);
    fprintf('  Chart  : %s\n', getf(plan,'chart','(미상)'));
    fprintf('  목적   : %s\n', getf(plan,'note','(적지 않음)'));
    fprintf('  op     : %d개\n\n', numel(plan.ops));

    % ── G4. 이미 적용된 계획인가 ──────────────────────
    if isfield(plan,'applied') && islogical(plan.applied) && plan.applied
        rep.blocked{end+1} = ['G4 이 계획은 이미 적용됐다(applied:true). ' ...
            '두 번 적용하면 State 가 중복 생성된다. 새 계획을 만든다'];
    end

    % ── G1. 작업트리 ──────────────────────────────────
    [hasGit, gitRoot, dirty] = git_state(pwd);
    if ~hasGit
        rep.blocked{end+1} = 'G1 git 저장소가 없다. .slx 는 바이너리라 되돌릴 수단이 커밋뿐이다';
    elseif dirty && ~dry
        rep.blocked{end+1} = ['G1 작업트리가 더럽다. 편집 전 상태를 커밋해 두지 않으면 ' ...
            '무엇이 이번 회차의 변경인지 구분할 수 없다'];
    end
    gate('G1 작업본 보호', hasGit && (~dirty || dry), ternary(hasGit, gitRoot, '없음'));

    % ── G3. 블록 정책 ─────────────────────────────────
    projRoot = ternary(hasGit, gitRoot, pwd);
    hasPolicy = isfile(fullfile(projRoot, '.satk', 'block-policy.json'));
    if ~hasPolicy && is_company_root(projRoot)
        rep.blocked{end+1} = ['G3 회사 모델인데 .satk\block-policy.json 이 없다. ' ...
            'model_edit 이 무차단으로 돈다 — protectedParams 로 잠근 것이 하나도 없다'];
    end
    gate('G3 블록 정책', hasPolicy || ~is_company_root(projRoot), ...
        ternary(hasPolicy, fullfile(projRoot,'.satk','block-policy.json'), '없음 — 무차단'));

    % ── G5. 세션 동일성 ───────────────────────────────
    pidNow = feature('getpid');
    gate('G5 MATLAB 세션', true, sprintf('엔진 PID %d', pidNow));

    % ── 막혔으면 ──────────────────────────────────────
    %    🔴 실제 모드는 여기서 끝낸다.
    %    🧪 Dry 는 계속한다. Dry 의 목적은 「적용하면 무엇이 막히고 무엇이 적용되는지」를
    %       **함께** 보는 것이다. 관문에서 끊으면 계획을 미리 검토할 수 없어
    %       Dry 가 있으나 마나가 된다. 모델을 바꾸지 않으므로 위험도 없다.
    if ~isempty(rep.blocked)
        if dry
            fprintf('\n  ⚠ 지금 실제로 적용하면 아래에서 막힌다 (%d건):\n', numel(rep.blocked));
            for i = 1:numel(rep.blocked), fprintf('     %d) %s\n', i, rep.blocked{i}); end
            fprintf('\n  계획 검토는 계속한다 — Dry 는 모델을 바꾸지 않는다.\n');
        else
            fprintf('\n  🔴 관문을 넘지 못했다. 모델을 바꾸지 않는다.\n\n');
            for i = 1:numel(rep.blocked), fprintf('     %d) %s\n', i, rep.blocked{i}); end
            fprintf('\n');
            return
        end
    end

    % ── G2. 백업 ──────────────────────────────────────
    if ~dry && doBack
        rep.backup = make_backup(pwd);
        gate('G2 zip 백업', ~isempty(rep.backup), rep.backup);
        if isempty(rep.backup)
            fprintf('\n  🔴 백업을 만들지 못했다. 되돌릴 수단 없이 편집하지 않는다.\n\n');
            rep.blocked{end+1} = 'G2 백업 실패';
            return
        end
    else
        gate('G2 zip 백업', true, ternary(dry, '(Dry — 건너뜀)', '(Backup=false)'));
    end

    % ── op 를 MCP 가 쓸 형태로 내놓는다 ───────────────
    fprintf('\n  ── 적용할 op (메인 세션이 mcp__matlab__model_edit 으로 수행한다) ──\n\n');
    for i = 1:numel(plan.ops)
        o = plan.ops(i);
        fprintf('  [%d] %s / scope=%s\n', i, o.op, o.scope);
        fprintf('      args : %s\n', jsonencode(o.args));
        fprintf('      왜   : %s\n', o.why);
        rep.ready{end+1} = struct('op', o.op, 'scope', o.scope, 'args', o.args);
    end

    if dry
        fprintf('\n  🧪 Dry 모드였다. 모델은 그대로다.\n');
        if isempty(rep.blocked)
            fprintf('     관문도 전부 통과했다. 실제로 적용하려면 Dry 없이 다시 부른다.\n\n');
            rep.ok = true;
        else
            fprintf('     🔴 다만 관문 %d건이 막고 있다 — 그것부터 푼다.\n\n', numel(rep.blocked));
            rep.ok = false;
        end
        return
    end

    fprintf('\n  ✅ 관문을 전부 통과했다.\n');
    % ── model_edit 이 그대로 받는 한 줄 JSON 을 낸다 (2026-09-16 실습 dock_ops 회차에서 확인한 형식) ──
    %    add_block → {op,type,name,ref,params.LabelString} · connect → {op,target,params.LabelString/ExecutionOrder}
    %    scope 는 Chart 블록의 blk_N — model_overview(model,'root','tree') 로 먼저 찾는다. 빈 Chart 면 layout_mode 'full'.
    me = cell(1, numel(plan.ops));
    for i = 1:numel(plan.ops)
        o = plan.ops(i); a = o.args; prm = struct();
        if isfield(a,'LabelString') && ~isempty(a.LabelString), prm.LabelString = a.LabelString; end
        if strcmp(o.op, 'add_block')
            me{i} = struct('op','add_block','type',a.type,'name',a.name,'ref',a.name);
        else
            if isfield(a,'ExecutionOrder') && ~isempty(a.ExecutionOrder), prm.ExecutionOrder = num2str(a.ExecutionOrder); end
            me{i} = struct('op','connect','target',a.expr);
        end
        if ~isempty(fieldnames(prm)), me{i}.params = prm; end   % 빈 params 는 내지 않는다
    end
    meFile = fullfile(fileparts(opsFile), 'model_edit_ops.json');
    fidm = fopen(meFile, 'w', 'n', 'UTF-8');
    if fidm >= 0
        fwrite(fidm, unicode2native(jsonencode(me), 'UTF-8'), 'uint8'); fclose(fidm);
        rep.model_edit_file = meFile;
    end
    fprintf('     이제 메인 세션이 위 op 를 `model_edit` 으로 적용한다:\n');
    fprintf('        model_overview(model,''root'',''tree'') 로 Chart 의 blk_N 을 찾고\n');
    fprintf('        model_edit(model, blk_N, <%s 내용 그대로>, layout_mode)\n', meFile);
    fprintf('        evaluate: save_system(''<모델>'')\n');
    fprintf('     🔴 적용 뒤에는 반드시:\n');
    fprintf('        1) build(''<날짜>'') 를 다시 돌려 감사한다\n');
    fprintf('        2) 결과를 확인하고 커밋한다\n');
    fprintf('        3) 이 계획 파일의 applied 를 true 로 바꾼다 (재적용 방지)\n\n');
    rep.ok = true;
end


% ══════════════════════════════════════════════════════

function gate(name, pass, extra)
    if pass, m = '✅'; else, m = '🔴'; end
    if isempty(extra)
        fprintf('  %s %s\n', m, name);
    else
        fprintf('  %s %-20s %s\n', m, name, extra);
    end
end

function z = make_backup(root)
%MAKE_BACKUP  🔴 Copy-Item -Recurse 를 쓰지 않는다.
%   260자를 넘는 경로에서 **일부만 복사되고 에러만 낸다**(실측 75개 중 66개).
%   Compress-Archive 를 쓴다.
    stamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));
    outDir = fullfile(root, '_백업');
    if ~isfolder(outDir), mkdir(outDir); end
    z = fullfile(outDir, sprintf('저작전_%s.zip', stamp));
    cmd = sprintf(['powershell -NoProfile -Command ' ...
        '"Compress-Archive -Path ''%s\\*.slx'',''%s\\*.sldd'' -DestinationPath ''%s'' -Force"'], ...
        root, root, z);
    [st, out] = system(cmd);
    if st ~= 0 || ~isfile(z)
        fprintf('     백업 실패: %s\n', strtrim(out));
        z = '';
    end
end

function S = read_json(p)
    fid = fopen(p, 'r', 'n', 'UTF-8');
    if fid < 0, error('apply_ops:read', '계획 파일을 열지 못했다: %s', p); end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    raw = fread(fid, '*char')';
    S = jsondecode(raw);
end

function [hasGit, root, dirty] = git_state(p)
    hasGit = false; root = ''; dirty = false;
    d = p;
    for k = 1:10
        if isfolder(fullfile(d, '.git')), hasGit = true; root = d; break; end
        up = fileparts(d);
        if isempty(up) || strcmp(up, d), break; end
        d = up;
    end
    if ~hasGit, return; end
    try
        [st, out] = system(sprintf('git -C "%s" status --porcelain', root));
        dirty = (st == 0) && ~isempty(strtrim(out));
    catch
    end
end

function tf = is_company_root(p)
    tf = contains(lower(p), lower(fullfile(getenv('USERPROFILE'), 'matlab-work')));
end

function v = getf(S, f, d)
    v = d;
    if isstruct(S) && isfield(S, f) && ~isempty(S.(f))
        v = S.(f);
    end
end

function o = ternary(c, a, b)
    if c, o = a; else, o = b; end
end
