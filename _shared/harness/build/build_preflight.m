function [ok, rep] = build_preflight(model, opts)
%BUILD_PREFLIGHT  모델을 **저작하기 전에** 전제와 함정을 점검한다.
%
%   [ok, rep] = build_preflight('ExampleModel')
%   ok = build_preflight()              모델 없이 환경만 점검한다
%
%   왜 저작용이 따로 있나
%   ────────────────────
%   분석용 `preflight` 는 「이 모델을 읽어도 되는가」를 본다. 저작은 「이 환경에서
%   모델을 **바꿔도** 되는가」를 봐야 하고, 그 항목이 겹치지 않는다.
%   사고는 대부분 「저작이 틀렸다」가 아니라 「전제가 조용히 달랐다」였다.
%
%   점검 항목 (2026-09-07 전부 이 PC 에서 실측한 값이 기준이다)
%   ──────────────────────────────────────────────────────
%     P1  라이선스        Simulink · Stateflow 체크아웃 가능한가
%     P2  없는 제품 확인   상용 검증 도구가 0 이라는 전제가 여전한가
%     P3  SATK 버전       기록값과 같은가 (다르면 같은 스크립트가 다른 배치를 낸다)
%     P4  SATK 도구       model_edit 등 7종이 경로에 있는가
%     P5  .satk 정책      3파일이 있는가. 없으면 **무차단 상태**임을 알린다
%     P6  진단 기본값     미연결 3종이 `none` 인가 (기본값이면 아무 경고도 안 난다)
%     P7  세션 동일성     MCP 가 붙은 MATLAB 세션이 회차 내내 같은가
%     P8  작업본 보호     git 저장소가 있고 작업트리가 깨끗한가
%     P9  모델 상태       (모델을 준 경우) 로드·참조·라이브러리 링크
%
%   🔴 ok=false 면 저작을 시작하지 않는다. 전제가 틀린 채 만든 모델은
%      오류 없이 그럴듯하게 틀리고, 나중에 어느 회차의 것인지 구분할 수 없다.
%
%   반환 rep 는 struct 이며 `build` 가 회차 로그에 그대로 적는다.

    if nargin < 1, model = ''; end
    if nargin < 2 || isempty(opts), opts = struct(); end
    % 🔴 「모델을 줬는가」가 아니라 「저작할 것인가」가 P5 의 판정 조건이다
    %    (2026-09-08 2차 정정). 읽기만 하는 회차를 block-policy 로 막으면 오탐이고,
    %    오탐이 잦으면 이 검사 전체를 무시하게 된다 — 미탐보다 위험하다.
    authoring = isfield(opts,'Authoring') && opts.Authoring;

    % 기록값 — 바뀌면 회차를 열지 않는다.
    EXPECT_SATK    = '2026.07.15';
    EXPECT_RELEASE = 'R2025b';

    rep = struct();
    rep.time    = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1,DATST>
    rep.model   = model;
    rep.fail    = {};
    rep.warn    = {};

    hdr('저작 전제 점검 (build_preflight)');

    % ── P1. 라이선스 ──────────────────────────────────
    sec('P1  라이선스');
    need = {'Simulink','Stateflow'};
    for i = 1:numel(need)
        v = licTest(need{i});
        item(v == 1, sprintf('%s 체크아웃 가능', need{i}), sprintf('= %d', v));
        if v ~= 1, rep.fail{end+1} = sprintf('P1 %s 라이선스 없음', need{i}); end %#ok<AGROW>
    end
    rep.release = ver_release();
    item(strcmp(rep.release, EXPECT_RELEASE), ...
        sprintf('MATLAB 릴리스 = %s', rep.release), sprintf('기록값 %s', EXPECT_RELEASE));
    if ~strcmp(rep.release, EXPECT_RELEASE)
        rep.fail{end+1} = sprintf('P1 릴리스가 %s 다 (기록값 %s). .slx 호환이 깨질 수 있다', ...
            rep.release, EXPECT_RELEASE);
    end

    % ── P2. 없는 제품 ─────────────────────────────────
    %     「있는데 안 쓴다」와 「없다」는 다르다. 관문 설계가 이 전제 위에 서 있으므로
    %     하나라도 생겼으면 관문을 다시 정해야 한다.
    sec('P2  상용 검증 도구 (없는 것이 전제다)');
    absent = {'Simulink_Test','Simulink_Coverage','Simulink_Check', ...
              'SIMULINK_Design_Verifier','RTW_Embedded_Coder','Simulink_Requirements'};
    appeared = {};
    for i = 1:numel(absent)
        v = licTest(absent{i});
        if v == 1, appeared{end+1} = absent{i}; end %#ok<AGROW>
    end
    if isempty(appeared)
        item(true, '상용 검증 도구 여전히 0', '관문 설계 전제 유지');
    else
        item(false, '없던 제품이 생겼다', strjoin(appeared, ', '));
        rep.warn{end+1} = sprintf('P2 라이선스가 생겼다: %s — 관문을 다시 정해야 한다', ...
            strjoin(appeared, ', '));
    end
    rep.appeared = appeared;

    % ── P3. SATK 버전 ─────────────────────────────────
    %     상류에서 07-08 에 Stateflow 자동배치 기본값이, 08-05 에 라이브러리 KG
    %     포맷이 바뀌었다. 업그레이드하면 **같은 스크립트가 다른 모델을 낸다.**
    %     재현성은 의료기기 요구의 일부다.
    sec('P3  SATK 버전');
    [satkDir, satkVer] = satk_version();
    rep.satk_dir = satkDir;
    rep.satk_ver = satkVer;
    if isempty(satkVer)
        item(false, 'SATK VERSION 을 읽지 못했다', satkDir);
        rep.fail{end+1} = 'P3 SATK VERSION 없음';
    else
        same = strcmp(satkVer, EXPECT_SATK);
        item(same, sprintf('SATK = %s', satkVer), sprintf('기록값 %s', EXPECT_SATK));
        if ~same
            rep.fail{end+1} = sprintf(['P3 SATK 가 %s 로 바뀌었다 (기록값 %s). ' ...
                '자동배치·KG 포맷이 달라 같은 스크립트가 다른 결과를 낸다'], satkVer, EXPECT_SATK);
        end
    end

    % ── P4. SATK 도구 ─────────────────────────────────
    sec('P4  SATK 도구 진입점');
    tools = {'model_edit','model_read','model_check','model_overview', ...
             'model_test','model_query_params','model_resolve_params'};
    missing = {};
    for i = 1:numel(tools)
        if isempty(which(tools{i})), missing{end+1} = tools{i}; end %#ok<AGROW>
    end
    item(isempty(missing), sprintf('도구 %d/%d 경로에 있음', numel(tools)-numel(missing), numel(tools)), ...
        ternary(isempty(missing), '', ['없음: ' strjoin(missing, ', ')]));
    if ~isempty(missing)
        rep.fail{end+1} = sprintf('P4 SATK 도구 없음: %s', strjoin(missing, ', '));
    end
    rep.tools_missing = missing;

    % ── P5. .satk 정책 ────────────────────────────────
    %     🚨 기본값은 「막힌다」가 아니라 「제약 없이 돈다」다.
    %     reuse-libraries.json 에 confirmedNone:true 만 넣으면 게이트 2·3 이
    %     건너뛰어져 block-policy 도 KG 도 안 만들어지고, model_edit 은 출하
    %     기본값(accessControl:"none" = 무차단) 위에서 아무 블록이나 배치한다.
    sec('P5  .satk 블록 정책');
    % 🔴 projectRoot 를 pwd 로 잡으면 안 된다 (2026-09-08 검증에서 드러남).
    %    session('20260804') 이 날짜 폴더로 cd 하므로 pwd 를 쓰면 `20260804\.satk`
    %    를 찾게 되고, 날짜 폴더마다 정책이 따로 있어야 하는 것처럼 된다.
    %    SATK 의 projectRoot 는 `.satk` 를 담는 디렉터리 하나여야 하므로
    %    저장소 루트를 쓴다.
    projRoot = repo_root(pwd);
    satkLocal = fullfile(projRoot, '.satk');
    f_reuse  = fullfile(satkLocal, 'reuse-libraries.json');
    f_policy = fullfile(satkLocal, 'block-policy.json');
    f_kg     = fullfile(satkLocal, 'library-kg', 'index.md');
    rep.satk_local = satkLocal;
    rep.has_reuse  = isfile(f_reuse);
    rep.has_policy = isfile(f_policy);
    rep.has_kg     = isfile(f_kg);

    item(rep.has_reuse,  'reuse-libraries.json', satkLocal);
    item(rep.has_policy, 'block-policy.json',    '');
    item(rep.has_kg,     'library-kg/index.md',  '');

    if ~rep.has_policy
        note(['block-policy 가 없다 → model_edit 이 **무차단**으로 돈다. ' ...
              'protectedParams 로 잠근 파라미터가 하나도 없다는 뜻이다.']);
        note('실측 근거: library.BlockPolicy.defaults() 가 blockedBlocks=[] · blockRules=[] 를 준다.');
        rep.warn{end+1} = 'P5 block-policy 없음 — 무차단 상태';
    end
    % 🔴 회사 모델을 **저작할 때만** 막는다.
    %    모델 없이 부르는 것은 환경 점검이지 저작이 아니다. 그때도 fail 을 내면
    %    오탐이 되고, 경고가 잦으면 이 검사 전체를 무시하게 된다 — 미탐보다 위험하다.
    if ~rep.has_policy && is_company_root(projRoot) && authoring
        rep.fail{end+1} = ['P5 회사 모델을 저작하려는데 block-policy 가 없다. ' ...
            '무차단 상태로 회사 모델을 편집하지 않는다'];
    elseif ~rep.has_policy && is_company_root(projRoot)
        note('이번 회차는 저작하지 않으므로 막지 않는다 (읽기·감사 전용).');
    end

    % ── P6. 진단 기본값 ───────────────────────────────
    %     🔴 2026-09-08 전제 정정. 9/7 에 잰 `none`/`warning` 은 `new_system` 으로
    %        만든 **빈 모델의 출하 기본값**이었다. 실제 ExampleModel 은 5종이 전부
    %        `error` 다 — **팀이 이미 올려놨다.** 「관문의 첫 일은 진단을 올리는 것」
    %        이라는 전제가 이 모델에는 성립하지 않는다.
    %        → 올리는 것이 아니라 **이미 올라가 있는지 확인**하는 것이 먼저다.
    %     실측(2026-09-07): 진단을 error 로 올리면 `SimulationCommand='update'`
    %        만으로 발화한다 (입력 자극이 필요 없다).
    sec('P6  진단 설정 (기본값이 아니라 이 모델의 현재 값)');
    if isempty(model)
        note('모델을 주지 않아 건너뛴다. build 는 항상 모델과 함께 부른다.');
    else
        if ~bdIsLoaded(model), load_system(model); end
        cs = getActiveConfigSet(model);
        watch = {'UnconnectedInputMsg','UnconnectedOutputMsg','UnconnectedLineMsg', ...
                 'SFUnreachableExecutionPathDiag','SFNoUnconditionalDefaultTransitionDiag', ...
                 'AlgebraicLoopMsg'};
        rep.diag = struct();
        nErr = 0;
        for i = 1:numel(watch)
            nm = watch{i};
            v  = getp(cs, nm);
            rep.diag.(nm) = v;
            isErr = strcmp(v, 'error');
            nErr = nErr + isErr;
            fprintf('     %-42s = %-8s %s\n', nm, v, ternary(isErr, '(강화됨)', ''));
        end
        rep.diag_hardened = nErr;
        rep.diag_total    = numel(watch);
        if nErr == numel(watch)
            note(sprintf('%d/%d 이 이미 error 다 — 이 모델은 진단이 강화된 상태로 쓰이고 있다.', ...
                nErr, numel(watch)));
        else
            note(sprintf('%d/%d 만 error 다. 관문(audit_build)이 회차 중에 나머지를 올리고 끝나면 원복한다.', ...
                nErr, numel(watch)));
        end
    end

    % ── P7. 세션 동일성 ───────────────────────────────
    %     R2025b 는 UI 셸과 계산 엔진을 2프로세스로 띄운다. `feature('getpid')` 는
    %     엔진(자식)을 준다. 회차 중 사용자가 MATLAB 을 재시작하면 세션이 바뀌는데,
    %     PID 만으로는 그것을 못 잡으므로 세션 키를 함께 남긴다.
    sec('P7  MATLAB 세션');
    rep.pid = feature('getpid');
    rep.pwd = pwd;
    fprintf('     엔진 PID = %d\n', rep.pid);
    fprintf('     PWD      = %s\n', rep.pwd);
    note('build 가 회차 시작·마감에 이 PID 를 대조한다. 달라졌으면 회차를 무효로 한다.');

    % ── P8. 작업본 보호 ───────────────────────────────
    %     .slx 는 바이너리라 되돌리기 수단이 커밋과 zip 뿐이다.
    sec('P8  작업본 보호');
    [hasGit, gitRoot, dirty] = git_state(projRoot);
    rep.git_root = gitRoot;
    rep.git      = hasGit;
    rep.git_dirty = dirty;
    item(hasGit, 'git 저장소', ternary(hasGit, gitRoot, '없음 — 되돌릴 수단이 zip 뿐이다'));
    if ~hasGit
        rep.fail{end+1} = ['P8 git 저장소가 없다. .slx 는 바이너리라 편집을 되돌릴 ' ...
            '수단이 커밋뿐이다. 저작을 시작하기 전에 만든다'];
    else
        item(~dirty, '작업트리 깨끗', ternary(dirty, '커밋 안 된 변경이 있다', ''));
        if dirty
            rep.fail{end+1} = ['P8 작업트리가 더럽다. 편집 전 상태를 커밋해 두지 않으면 ' ...
                '무엇이 이번 회차의 변경인지 구분할 수 없다'];
        end
    end

    % ── P9. 모델 상태 ─────────────────────────────────
    sec('P9  모델');
    if isempty(model)
        note('모델을 주지 않아 건너뛴다.');
    else
        try
            mdls = find_mdlrefs(model);
            rep.mdlrefs = mdls;
            item(true, sprintf('참조 트리 %d개 모델', numel(mdls)), strjoin(mdls, ', '));
        catch e
            item(false, '참조 해석 실패', e.message);
            rep.fail{end+1} = ['P9 참조 모델을 해석하지 못했다: ' e.message];
        end

        % LinkStatus 가 'inactive' 가 아니면 라이브러리 링크가 살아 있고,
        % 그 아래를 편집하면 링크가 끊기거나 원본이 바뀐다.
        [bad, tally] = link_issues(model);
        rep.link_issues = bad;
        rep.link_tally  = tally;
        % 「0건」이 「없다」인지 「못 찾았다」인지 구분하려면 **평가 대상 수**가 함께 있어야 한다.
        tk = fieldnames(tally);
        nAll = 0; parts = cell(1,numel(tk));
        for i = 1:numel(tk)
            nAll = nAll + tally.(tk{i});
            parts{i} = sprintf('%s %d', tk{i}, tally.(tk{i}));
        end
        item(isempty(bad), sprintf('라이브러리 링크 (블록 %d개 검사)', nAll), ...
            ternary(isempty(bad), strjoin(parts, ' · '), sprintf('깨진 링크 %d건', numel(bad))));
        if ~isempty(bad)
            for i = 1:min(5, numel(bad)), fprintf('       - %s\n', bad{i}); end
            rep.fail{end+1} = sprintf(['P9 라이브러리 링크가 깨졌다 %d건 (unresolved/broken). ' ...
                '이 상태로 편집하면 모델이 제대로 안 열린다'], numel(bad));
        end
    end

    % ── 결과 ──────────────────────────────────────────
    ok = isempty(rep.fail);
    rep.ok = ok;
    fprintf('\n');
    if ok
        fprintf('  ✅ 전제 점검 통과');
        if ~isempty(rep.warn)
            fprintf('  (경고 %d건)\n', numel(rep.warn));
            for i = 1:numel(rep.warn), fprintf('     ⚠ %s\n', rep.warn{i}); end
        else
            fprintf('\n');
        end
    else
        fprintf('  🔴 전제가 깨져 있다 — 저작을 시작하지 않는다.\n\n');
        for i = 1:numel(rep.fail), fprintf('     %d) %s\n', i, rep.fail{i}); end
        fprintf('\n     전제가 틀린 채 만든 모델은 오류 없이 그럴듯하게 틀린다.\n');
    end
    fprintf('\n');
end


% ══════════════════════════════════════════════════════
% 보조

function hdr(t)
    fprintf('\n════════ %s ════════\n', t);
end

function sec(t)
    fprintf('\n  ── %s\n', t);
end

function item(pass, label, extra)
    if pass, mark = '✅'; else, mark = '🔴'; end
    if isempty(extra)
        fprintf('     %s %s\n', mark, label);
    else
        fprintf('     %s %-38s %s\n', mark, label, extra);
    end
end

function note(t)
    fprintf('     · %s\n', t);
end

function out = ternary(c, a, b)
    if c, out = a; else, out = b; end
end

function v = licTest(name)
%LICTEST  license('test') 는 「설치+가용」을 본다. 실제 체크아웃과 다를 수 있으므로
%         P2 는 이 값만으로 「생겼다」고 단정하지 않고 경고로만 낸다.
    v = -1;
    try, v = license('test', name); catch, end
end

function r = ver_release()
    r = '';
    try
        v = ver('MATLAB');
        t = regexp(v(1).Release, 'R\d{4}[ab]', 'match', 'once');
        if ~isempty(t), r = t; end
    catch
    end
end

function [d, v] = satk_version()
    d = fullfile(getenv('USERPROFILE'), '.matlab', 'agentic-toolkits', 'simulink');
    v = '';
    f = fullfile(d, 'VERSION');
    if isfile(f)
        try, v = strtrim(read_text(f)); catch, end
    end
end

function s = read_text(f)
%READ_TEXT  fileread 는 BMP 밖 문자를 조용히 지운다 (R20). 하네스에 read_utf8 이
%           있으면 그것을 쓰고, 없으면 바이트로 직접 읽는다.
    if ~isempty(which('read_utf8'))
        s = read_utf8(f);
        return
    end
    fid = fopen(f, 'r', 'n', 'UTF-8');
    oc  = onCleanup(@() fclose(fid)); %#ok<NASGU>
    s = fread(fid, '*char')';
end

function v = getp(cs, name)
    v = '<없음>';
    try, v = get_param(cs, name); catch, end
end

function tf = is_company_root(p)
%IS_COMPANY_ROOT  회사 작업 폴더인가. 연습 폴더와 구분한다.
%   🔴 판정을 넓히지 않는다 — 과잉 차단은 규칙 자체를 무시하게 만든다.
    tf = contains(lower(p), lower(fullfile(getenv('USERPROFILE'), 'matlab-work')));
end

function [hasGit, root, dirty] = git_state(p)
    hasGit = false; root = ''; dirty = false;
    d = p;
    for k = 1:8
        if isfolder(fullfile(d, '.git')), hasGit = true; root = d; break; end
        up = fileparts(d);
        if strcmp(up, d), break; end
        d = up;
    end
    if ~hasGit, return; end
    try
        [st, out] = system(sprintf('git -C "%s" status --porcelain', root));
        dirty = (st == 0) && ~isempty(strtrim(out));
    catch
    end
end

function [bad, tally] = link_issues(model)
%LINK_ISSUES  라이브러리 링크가 **깨진** 블록을 찾는다.
%
%   🔴 2026-09-08 오탐 수정. 처음에는 `none`·`inactive` 만 정상으로 보고
%      나머지를 전부 잡았는데, ExampleModel 에서 **84건**이 나왔고 전부 정상이었다:
%        resolved  라이브러리 링크가 정상 해결된 상태
%        implicit  링크된 서브시스템 **안쪽** 블록 (자동으로 붙는 값)
%      경고가 잦으면 검사 전체를 무시하게 되므로 오탐은 미탐만큼 위험하다.
%
%   실제로 문제인 것만 남긴다.
%     unresolved  라이브러리를 찾지 못했다 — 모델이 제대로 안 열린다
%     broken      링크가 끊어졌다
%
%   find_system 은 침묵 제외 플래그 4종을 항상 명시한다 (R3).
%   tally 는 LinkStatus 값별 개수다. 「0건」이 「없다」인지 「못 찾았다」인지
%   구분하려면 무엇을 몇 개 봤는지가 함께 있어야 한다.

    BROKEN = {'unresolved','broken'};
    bad = {};
    tally = struct();
    try
        blks = find_system(model, 'LookUnderMasks','all', 'FollowLinks','on', ...
            'IncludeCommented','on', 'MatchFilter',@Simulink.match.allVariants, ...
            'Type','block');
        for i = 1:numel(blks)
            ls = '';
            try, ls = get_param(blks{i}, 'LinkStatus'); catch, continue; end
            if isempty(ls), ls = '<empty>'; end
            key = matlab.lang.makeValidName(ls);
            if isfield(tally, key), tally.(key) = tally.(key) + 1; else, tally.(key) = 1; end
            if any(strcmp(ls, BROKEN))
                bad{end+1} = sprintf('%s  (LinkStatus=%s)', ...
                    strrep(blks{i}, newline, ' '), ls); %#ok<AGROW>
            end
        end
    catch
    end
end


function root = repo_root(startDir)
%REPO_ROOT  `.git` 를 담은 상위 폴더를 찾는다. 없으면 startDir 을 그대로 준다.
%   projectRoot 를 pwd 로 잡으면 session() 이 날짜 폴더로 cd 한 뒤 `.satk` 를
%   엉뚱한 곳에서 찾는다 (2026-09-08 검증에서 드러남).
    root = startDir;
    d = startDir;
    for k = 1:10
        if isfolder(fullfile(d, '.git')), root = d; return; end
        up = fileparts(d);
        if isempty(up) || strcmp(up, d), break; end
        d = up;
    end
end
