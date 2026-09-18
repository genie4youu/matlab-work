function ok = selftest_harness(vaultDir, model)
%SELFTEST_HARNESS  검사기를 검사한다. 실패를 못 내는 검사기는 검사기가 아니다.
%
%   ok = selftest_harness()              세션 맥락에서 볼트·모델을 도출한다
%   ok = selftest_harness(vaultDir, model)
%
%   왜 필요한가
%   ──────────
%   이 프로젝트에서 커버리지 감사는 **두 번 뚫렸다.** 1판은 미분석 50개를,
%   2판은 미완 16개를 「통과」로 냈다. 두 번 다 사람이 우연히 발견했다.
%
%   그리고 검사 스크립트 자체가 조용히 틀린 일도 두 번 있었다.
%     - PowerShell 경로 글로빙이 재귀를 안 해서 「이름 0회 등장」이 나왔다 (실제 7회)
%     - 정규식 `.` 이 줄바꿈을 안 잡아 「`.slx` 안에 그 이름 없음」이 나왔다 (실제 있음)
%   둘 다 **0건을 「없다」로 읽었다.** 0건은 「없다」가 아니라 「못 찾았다」다.
%
%   세 부분
%   ──────
%     A. 일반 함정 검사 — 어느 모델에나 해당한다
%          A1 주석 처리된 블록이 열거에 들어가는가        (R21)
%          A2 영역 주석 이름이 그 층 문서에 적히는가       (R22)
%     B. 회귀 고정 — 이 모델에서 **한 번 놓쳤던 것**이 지금도 열거되는가
%          `<세션폴더>\_회귀고정.txt` 에 한 줄씩 적는다. 없으면 건너뛴다
%     C. 씨앗 결함 — 판정 ①②③④⑤ 가 각각 실제로 실패를 내는가
%          볼트 **사본**에서 한다. 원본은 건드리지 않는다
%
%   🔴 A 는 모델에 무관하게 돈다. 새 모델을 가져와도 같은 종류의 함정을 잡는다.
%      B 는 그 모델에서 실제로 겪은 것만 담는다. 처음 보는 모델에서는 비어 있는 것이 정상이다.

    if nargin < 2, model = ''; end
    ctx = vault_ctx(model);
    if nargin < 1 || isempty(vaultDir), vaultDir = ctx.vault; end

    fprintf('\n=== 검사기 자가 시험 (%s / %s) ===\n\n', ctx.date, ctx.model);
    fails = {};
    U = vault_units(ctx.model);

    % ══ A. 일반 함정 검사 ══════════════════════════════
    fprintf('A. 일반 함정 — 어느 모델에나 해당한다\n');
    [fails, nCmt] = checkCommented(fails, ctx, U);
    [fails, nAr ] = checkAreas(fails, ctx, U, vaultDir);
    fprintf('   주석 처리 블록 %d개 / 영역 주석 %d개를 대조했다\n', nCmt, nAr);

    % ══ B. 회귀 고정 ═══════════════════════════════════
    fixFile = fullfile(ctx.dir, '_회귀고정.txt');
    fprintf('\nB. 회귀 고정 — `_회귀고정.txt`\n');
    if ~isfile(fixFile)
        fprintf('   (파일 없음 — 아직 고정할 회귀가 없다. 누락을 발견하면 여기에 한 줄 추가한다)\n');
    else
        rel = {U.rel};
        lines = strsplit(read_utf8(fixFile), newline);
        n = 0;
        for k = 1:numel(lines)
            L = strtrim(lines{k});
            if isempty(L) || startsWith(L,'#'), continue; end
            why = '';
            i = strfind(L, '#');
            if ~isempty(i), why = strtrim(L(i(1)+1:end)); L = strtrim(L(1:i(1)-1)); end
            n = n + 1;
            if any(strcmp(rel, L))
                fprintf('   O  %s\n', L);
            else
                fprintf('   X  %s   (%s)\n', L, why);
                fails{end+1} = sprintf('회귀: %s 가 열거에서 사라졌다 (%s)', L, why); %#ok<AGROW>
            end
        end
        fprintf('   %d건 대조\n', n);
    end

    % ══ C. 씨앗 결함 ═══════════════════════════════════
    fprintf('\nC. 씨앗 결함 — 판정이 실제로 실패를 내는가\n');
    tmp = fullfile(tempdir, 'sfx_selftest');
    if isfolder(tmp), rmdir(tmp,'s'); end
    copyfile(vaultDir, tmp);
    restore = onCleanup(@() cleanup(tmp)); %#ok<NASGU>

    victim = ''; vseg = {}; vpath = '';
    for k = 1:numel(U)
        if ~strcmp(U(k).kind,'SubSystem'), continue; end
        d = fullfile(tmp, U(k).segs{:}, [strjoin(U(k).segs,'_') '.md']);
        if ~isfile(d), continue; end
        t = read_utf8(d);
        if contains(t,'아직 채우지 않았다'), continue; end
        victim = d; vseg = U(k).segs; vpath = U(k).path; break
    end

    if isempty(victim)
        fprintf('   ?  해석이 채워진 SubSystem 문서가 없어 건너뛴다\n');
        fprintf('      (분석을 아직 시작하지 않은 세션에서는 정상이다)\n');
    else
        fprintf('   대상: %s\n', strjoin(vseg,'/'));
        base = read_utf8(victim);

        delete(victim);
        fails = expectFail(fails, '① 문서 1:1', runCov(ctx, tmp), '문서를 지웠는데 통과가 나왔다');
        writeUtf8(victim, base);

        writeUtf8(victim, setInterp(base, '> 아직 채우지 않았다. 기계 추출만 있는 상태다.'));
        fails = expectFail(fails, '② 해석 기재', runCov(ctx, tmp), '자리표시자인데 통과가 나왔다');

        filler = repmat('이 블록에 대한 일반적인 설명 문장을 길게 늘여 적는다. ', 1, 8);
        writeUtf8(victim, setInterp(base, filler));
        fails = expectFail(fails, '③ 식별자 교집합', runCov(ctx, tmp), '식별자 0개인데 통과가 나왔다');

        writeUtf8(victim, setInterp(base, [filler newline '식별자 없이 분량만 채운 상태다.']));
        fails = expectFail(fails, '④ 설명 가능성', runCov(ctx, tmp), '소절이 없는데 통과가 나왔다');

        % ⑤ 지울 이름은 **감사가 세는 것과 같은 방법**으로 뽑는다.
        %    초판은 문서에서 정규식으로 골랐다가 `BlockType` 칸의 `SubSystem` 을
        %    집어 「감사가 결함을 못 잡는다」는 오탐을 냈다. 시험이 틀린 것이었다.
        writeUtf8(victim, base);
        el0  = runElem(ctx, tmp);
        gone = '';
        kid  = find_system(vpath,'SearchDepth',1,'LookUnderMasks','all','FollowLinks','on', ...
                           'IncludeCommented','on','MatchFilter',@Simulink.match.allVariants);
        for j = 1:numel(kid)
            if strcmp(kid{j}, vpath), continue; end
            nm = strrep(strrep(kid{j},[vpath '/'],''), newline, ' ');
            if numel(nm) >= 4 && contains(base, nm), gone = nm; break; end
        end
        if isempty(gone)
            fprintf('   ?  ⑤ 원소 커버리지 — 지울 원소 이름을 찾지 못해 건너뛴다\n');
        else
            writeUtf8(victim, strrep(base, gone, 'ZZZ_삭제된_이름'));
            if runElem(ctx, tmp)
                fprintf('   X  ⑤ 원소 커버리지 — `%s` 를 지웠는데 통과가 나왔다\n', gone);
                fails{end+1} = '⑤ 원소 커버리지가 결함을 못 잡는다'; %#ok<AGROW>
            else
                fprintf('   O  ⑤ 원소 커버리지 — `%s` 제거를 잡았다\n', gone);
            end
        end
        writeUtf8(victim, base);
        if ~el0
            fprintf('   !  씨앗 전에도 원소 감사가 실패 상태다 — 이 시험 결과는 신뢰할 수 없다\n');
            fails{end+1} = '씨앗 전 원소 감사가 이미 실패 상태였다'; %#ok<AGROW>
        end
    end

    % ══ 결과 ═══════════════════════════════════════════
    ok = isempty(fails);
    fprintf('\n');
    if ok
        fprintf('통과 — 일반 함정 대조, 회귀 고정 유지, 판정 5종이 결함을 잡는다.\n\n');
    else
        fprintf('🔴 실패 %d건\n\n', numel(fails));
        for k = 1:numel(fails), fprintf('  - %s\n', fails{k}); end
        fprintf('\n검사기가 죽어 있으면 「통과」는 아무 의미가 없다. 이것부터 고친다.\n\n');
    end
end


% ══════════════════════════════════════════════════════
function [fails, n] = checkCommented(fails, ctx, U)
%CHECKCOMMENTED  주석 처리된 컨테이너가 열거에 들어갔는가 (R21).
%   모델에 주석 블록이 없으면 0건이고 그것도 정상이다.
    n = 0;
    mdls = find_mdlrefs(ctx.model);
    rel  = {U.rel};
    % find_mdlrefs 는 이름만 준다. 로드하지 않고 find_system 을 부르면 죽는다.
    for i = 1:numel(mdls)
        if ~bdIsLoaded(mdls{i})
            try, load_system(mdls{i}); catch, end
        end
    end
    for i = 1:numel(mdls)
        L = find_system(mdls{i},'LookUnderMasks','all','FollowLinks','on', ...
                        'IncludeCommented','on','MatchFilter',@Simulink.match.allVariants, ...
                        'BlockType','SubSystem');
        for k = 1:numel(L)
            cm = ''; try, cm = get_param(L{k},'Commented'); catch, end
            if isempty(cm) || strcmp(cm,'off'), continue; end
            n = n + 1;
            r = strrep(strrep(L{k}, [mdls{i} '/'], ''), newline, ' ');
            if ~strcmp(mdls{i}, ctx.model), r = sprintf('%s: %s', mdls{i}, r); end
            if ~any(strcmp(rel, r))
                fprintf('   X  주석 블록이 열거에 없다: %s\n', r);
                fails{end+1} = sprintf('R21: 주석 블록 %s 가 열거에서 빠졌다', r); %#ok<AGROW>
            end
        end
    end
end

function [fails, n] = checkAreas(fails, ctx, U, vaultDir)
%CHECKAREAS  영역 주석 이름이 그 층 문서에 적혔는가 (R22).
    n = 0;
    for k = 1:numel(U)
        u = U(k);
        if ~strcmp(u.kind,'SubSystem'), continue; end
        a = [];
        try
            a = find_system(u.path,'SearchDepth',1,'LookUnderMasks','all','FollowLinks','on', ...
                            'IncludeCommented','on','FindAll','on','Type','annotation');
        catch
            continue
        end
        doc = fullfile(vaultDir, u.segs{:}, [strjoin(u.segs,'_') '.md']);
        if ~isfile(doc), continue; end
        txt = read_utf8(doc);
        for j = 1:numel(a)
            ty = ''; try, ty = get_param(a(j),'AnnotationType'); catch, end
            if ~strcmp(ty,'area_annotation'), continue; end
            nm = ''; try, nm = get_param(a(j),'Name'); catch, end
            nm = strtrim(regexprep(strrep(strrep(nm,sprintf('\r'),' '),newline,' '), '\s+',' '));
            if isempty(nm), continue; end
            n = n + 1;
            if ~contains(txt, nm)
                fprintf('   X  영역 주석이 문서에 없다: `%s` @ %s\n', nm, u.rel);
                fails{end+1} = sprintf('R22: 영역 주석 `%s` 가 %s 문서에 없다', nm, u.rel); %#ok<AGROW>
            end
        end
    end
end

function fails = expectFail(fails, name, verdicts, why)
%EXPECTFAIL  결함을 심었으니 그 판정은 **실패**여야 한다.
    if ~isKey(verdicts, name)
        fprintf('   ?  %s — 판정을 찾지 못했다 (감사 출력 형식이 바뀌었나)\n', name);
        fails{end+1} = sprintf('%s 판정을 감사 출력에서 찾지 못했다', name);
        return
    end
    if verdicts(name)
        fprintf('   X  %s — %s\n', name, why);
        fails{end+1} = sprintf('%s 가 결함을 못 잡는다 (%s)', name, why);
    else
        fprintf('   O  %s — 결함을 잡았다\n', name);
    end
end

function v = runCov(ctx, tmp)
    out = fullfile(tempdir, 'sfx_cov.md');
    m = ctx.model; %#ok<NASGU>
    evalc('audit_coverage(m, tmp, out)');
    txt = read_utf8(out);
    v = containers.Map('KeyType','char','ValueType','logical');
    for mm = regexp(txt, '\|\s*([①②③④][^|]*?)\s*\|\s*(통과|\*\*실패\*\*)', 'tokens')
        v(strtrim(mm{1}{1})) = strcmp(mm{1}{2}, '통과');
    end
end

function ok = runElem(ctx, tmp)
    out = fullfile(tempdir, 'sfx_el.md');
    m = ctx.model; %#ok<NASGU>
    evalc('audit_elements(tmp, out, m)');
    ok = contains(read_utf8(out), '**통과.**');
end

function t = setInterp(t, body)
    i = regexp(t, '##\s*\d*\.?\s*해석', 'once');
    if isempty(i), return; end
    head = t(1:i-1);
    rest = t(i:end);
    hdr  = regexp(rest, '^##[^\n]*\n', 'match', 'once');
    tail = regexp(rest, '\n---[\s\S]*$', 'match', 'once');
    if isempty(tail), tail = ''; end
    t = [head hdr newline body newline tail];
end

function writeUtf8(f, txt)
    fid = fopen(f, 'w', 'n', 'UTF-8');
    oc  = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s', txt);
end

function cleanup(tmp)
    if isfolder(tmp), rmdir(tmp,'s'); end
end
