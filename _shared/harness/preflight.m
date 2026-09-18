function ok = preflight(model)
%PREFLIGHT  새 모델을 분석하기 **전에** 환경과 모델의 함정을 점검한다.
%
%   ok = preflight()            세션 맥락에서 모델을 도출한다
%   ok = preflight('모델이름')
%
%   왜 필요한가
%   ──────────
%   지금까지의 사고는 대부분 「분석이 틀렸다」가 아니라 **「분석 전제가 조용히
%   달랐다」**였다. 전제가 다르면 결과는 오류 없이 그럴듯하게 나온다.
%
%     - 라이브러리 경로가 안 잡혀 참조 모델이 안 열렸다 → 하위 블록 수가 61 vs 73
%       으로 달라졌고, 61 이 문서에 그대로 박혔다
%     - 주석 처리된 블록이 열거에서 빠졌다 → 컨테이너 9개가 통째로 안 보였다
%     - 폴더 경로가 260자에 근접했다 → 백업이 조용히 일부만 복사됐다
%
%   그래서 **분석을 시작하기 전에** 이것들을 먼저 본다.
%
%   판정
%     🔴 실패  전제가 깨져 있다. 고치기 전에 분석하지 않는다
%     🟡 주의  분석은 가능하나 함정이 있다. 무엇인지 알고 시작한다
%     🟢 정상

    if nargin < 1, model = ''; end
    ctx = vault_ctx(model);

    fprintf('\n=== 분석 전 점검 (preflight) — %s / %s ===\n\n', ctx.date, ctx.model);
    err = {}; warn = {};

    % ── 1. 모델이 열리는가 ────────────────────────────
    try
        if ~bdIsLoaded(ctx.model), load_system(ctx.model); end
        fprintf('  모델 로드          OK   %s\n', which([ctx.model '.slx']));
    catch ME
        fprintf('  모델 로드          실패 %s\n', ME.message);
        err{end+1} = sprintf('모델을 열 수 없다: %s', ME.message);
        ok = false; report(err, warn); return
    end

    % ── 2. 참조 모델이 전부 해석되는가 ────────────────
    %    여기서 실패하면 이후 열거가 통째로 틀린다. 가장 중요한 검사다.
    try
        mdls = find_mdlrefs(ctx.model);
        fprintf('  참조 모델 해석      OK   %d개 (자기 자신 포함)\n', numel(mdls));
    catch ME
        fprintf('  참조 모델 해석      실패\n    %s\n', strtrim(ME.message));
        err{end+1} = '참조 모델을 못 찾는다. 라이브러리 폴더가 경로에 없을 수 있다';
        mdls = {ctx.model};
    end

    % ── 3. Subsystem Reference 가 해석되는가 ──────────
    ss = find_system(ctx.model,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on', ...
                     'MatchFilter',@Simulink.match.allVariants,'BlockType','SubSystem');
    unres = {};
    for k = 1:numel(ss)
        rs = ''; try, rs = get_param(ss{k},'ReferencedSubsystem'); catch, end
        if isempty(rs), continue; end
        if isempty(which([rs '.slx'])) && isempty(which([rs '.mdl']))
            unres{end+1} = rs; %#ok<AGROW>
        end
    end
    if isempty(unres)
        fprintf('  Subsystem Ref      OK\n');
    else
        u = unique(unres);
        fprintf('  Subsystem Ref      실패 %d종 미해결: %s\n', numel(u), strjoin(u, ', '));
        err{end+1} = sprintf('Subsystem Reference 미해결: %s', strjoin(u, ', '));
    end

    % ── 4. 데이터 딕셔너리 ────────────────────────────
    dd = ''; try, dd = get_param(ctx.model,'DataDictionary'); catch, end
    if isempty(dd)
        fprintf('  데이터 딕셔너리     없음 (상수를 모델 워크스페이스에서 찾는다)\n');
    else
        try
            d = Simulink.data.dictionary.open(dd);
            n = numel(find(getSection(d,'Design Data'))); %#ok<NASGU>
            close(d);
            fprintf('  데이터 딕셔너리     OK   %s (Design Data %d항목)\n', dd, n);
        catch ME
            fprintf('  데이터 딕셔너리     실패 %s — %s\n', dd, strtrim(ME.message));
            err{end+1} = sprintf('데이터 딕셔너리 %s 를 열 수 없다', dd);
        end
    end

    % ── 5. 이 모델의 함정 ─────────────────────────────
    nCmt = 0; nVar = 0; nNL = 0; nAr = 0;
    % 🔴 `find_mdlrefs` 는 **이름만** 준다. 로드하지 않고 find_system 을 부르면
    %    "The system ... is not loaded" 로 죽는다. 깨끗한 세션에서 실제로 발생했다.
    for i = 1:numel(mdls)
        if ~bdIsLoaded(mdls{i})
            try, load_system(mdls{i}); catch, end
        end
    end
    for i = 1:numel(mdls)
        B = find_system(mdls{i},'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on', ...
                        'MatchFilter',@Simulink.match.allVariants,'Type','block');
        for k = 1:numel(B)
            cm = ''; try, cm = get_param(B{k},'Commented'); catch, end
            if ~isempty(cm) && ~strcmp(cm,'off'), nCmt = nCmt + 1; end
            bt = ''; try, bt = get_param(B{k},'BlockType'); catch, end
            if any(strcmp(bt, {'VariantSubsystem','VariantSource','VariantSink','ModelReference'}))
                v = ''; try, v = get_param(B{k},'Variant'); catch, end
                if strcmp(v,'on'), nVar = nVar + 1; end
            end
            if contains(B{k}, newline), nNL = nNL + 1; end
        end
        A = find_system(mdls{i},'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on', ...
                        'FindAll','on','Type','annotation');
        for k = 1:numel(A)
            ty = ''; try, ty = get_param(A(k),'AnnotationType'); catch, end
            if strcmp(ty,'area_annotation'), nAr = nAr + 1; end
        end
    end
    fprintf('\n  이 모델의 함정\n');
    fprintf('    주석 처리된 블록     %3d   기본 find_system 은 이것을 뺀다 (R21)\n', nCmt);
    fprintf('    영역 주석            %3d   블록이 아니지만 화면에서 읽히는 이름이다 (R22)\n', nAr);
    fprintf('    Variant 블록         %3d   비활성 선택지가 조용히 빠질 수 있다 (R3)\n', nVar);
    fprintf('    이름에 줄바꿈이 든 블록 %3d   경로 문자열이 깨진다\n', nNL);
    if nCmt > 0, warn{end+1} = sprintf('주석 처리된 블록 %d개 — 문서에 「주석 처리」로 표시된다', nCmt); end
    if nAr  > 0, warn{end+1} = sprintf('영역 주석 %d개 — 블록 이름과 다를 수 있다 (R22)', nAr); end

    % ── 6. 경로 길이 ──────────────────────────────────
    try
        U = vault_units(ctx.model);
        L = 0; worst = '';
        for k = 1:numel(U)
            f = fullfile(ctx.vault, U(k).segs{:}, [strjoin(U(k).segs,'_') '.md']);
            if numel(f) > L, L = numel(f); worst = f; end
        end
        fprintf('\n  분석 단위            %3d\n', numel(U));
        fprintf('  볼트 최장 경로       %3d 자 (Windows 한계 260)\n', L);
        if L > 240
            fprintf('    ⚠ %s\n', worst);
            warn{end+1} = sprintf('볼트 경로가 %d자다. 260 을 넘으면 백업이 조용히 일부만 복사된다', L);
        end
    catch ME
        fprintf('\n  분석 단위 열거      실패 %s\n', strtrim(ME.message));
        err{end+1} = sprintf('vault_units 실패: %s', strtrim(ME.message));
    end

    % ── 7. 볼트 폴더 ──────────────────────────────────
    if isfolder(ctx.vault)
        fprintf('  볼트 폴더            OK   %s\n', ctx.vault);
    else
        fprintf('  볼트 폴더            없음 (첫 생성 시 만들어진다) %s\n', ctx.vault);
        warn{end+1} = '볼트 폴더가 아직 없다. gen_vault_tree 가 만든다';
    end

    ok = isempty(err);
    report(err, warn);
end


function report(err, warn)
    fprintf('\n');
    if ~isempty(err)
        fprintf('🔴 실패 %d건 — 고치기 전에 분석하지 않는다\n', numel(err));
        for k = 1:numel(err), fprintf('   - %s\n', err{k}); end
    end
    if ~isempty(warn)
        fprintf('🟡 주의 %d건 — 분석은 가능하나 알고 시작한다\n', numel(warn));
        for k = 1:numel(warn), fprintf('   - %s\n', warn{k}); end
    end
    if isempty(err) && isempty(warn)
        fprintf('🟢 정상 — 전제가 갖춰졌다\n');
    end
    fprintf('\n');
end
