function ok = audit_crosscheck(root)
%AUDIT_CROSSCHECK  열거를 **두 번째 경로로** 다시 세서 대조한다 (규칙 R26, 2026-08-06)
%
%   ok = audit_crosscheck('ExampleModel')
%
%   왜 필요한가
%   ──────────
%   이 프로젝트의 반복 실패 모드는 「분석이 틀렸다」가 아니라
%   **「목록에 안 나오는 것을 없는 것으로 취급했다」** 였다.
%
%     R18  Chart 를 sfroot 로 세서 로드 상태에 따라 3 / 7 / 9 로 흔들렸다
%     R19  참조 모델 내부 27개가 아무 판정에도 걸리지 않았다
%     R21  주석 블록 하나를 빼먹어 하위 컨테이너 9개·블록 61개가 통째로 안 보였다
%
%   셋 다 열거원이 `find_system` 하나뿐이라 **비교 대상이 없어서** 늦게 발견됐다.
%   감사 기준을 조이는 것으로는 못 막는다. 조여도 세는 것 자체가 적으면 통과한다.
%
%   무엇을 하나
%   ──────────
%   ① 플래그 민감도 — 침묵 제외 플래그를 하나씩 빼고 다시 세서, 이 모델에서
%      **그 플래그가 실제로 몇 개를 숨기는지** 숫자로 낸다. 61 vs 73 사고는
%      이 숫자가 0 이 아니라는 사실을 아무도 몰라서 났다.
%   ② XML 직접 열거 — `.slx` 는 zip 이다. 압축을 풀어 blockdiagram.xml 에서
%      BlockType 을 직접 센다. Simulink API 를 **한 번도 거치지 않는** 열거다.
%      API 가 조용히 빼면 이쪽 수가 더 크게 나온다.
%   ③ vault_units 대조 — 정본 열거(R19)의 분해가 ①의 수와 맞는지 본다.
%      총계만 맞고 분해가 틀린 사고가 있었으므로 **분해를 각각** 대조한다.
%
%   판정
%   ────
%     🔴 XML 수 > find_system 수      → API 가 무언가를 조용히 뺐다. 중단.
%     🟡 플래그를 빼면 수가 줄어든다    → 정상이다. 다만 **몇 개인지 문서에 적는다.**
%
%   ⚠️ 이 함수는 「모델이 무엇을 하는가」를 보지 않는다. 「몇 개가 있는가」만 본다.

    if nargin < 1 || isempty(root)
        c = vault_ctx(); root = c.model;
    end
    root = char(root);

    ensure_path();
    if ~bdIsLoaded(root), load_system(root); end
    mdls = find_mdlrefs(root);
    for i = 1:numel(mdls)
        if ~bdIsLoaded(mdls{i}), load_system(mdls{i}); end
    end

    fprintf('\n=== 열거 교차검증 (audit_crosscheck) ===\n');
    fprintf('루트 모델: %s · 참조 트리 %d개 모델\n\n', root, numel(mdls));

    KINDS = {'SubSystem','ModelReference'};
    fail  = {};

    % ── ① 플래그 민감도 + ② XML 대조 ─────────────────────
    fprintf('%-26s %6s %6s %6s %6s %6s %8s\n', ...
            '모델', '정본', '-Mask', '-Link', '-Comm', '-Vari', 'XML');
    fprintf('%s\n', repmat('-', 1, 74));

    totFull = 0; totXml = 0;
    for i = 1:numel(mdls)
        M = mdls{i};

        nFull = countFlags(M, KINDS, 'full');
        nMask = countFlags(M, KINDS, 'noMask');
        nLink = countFlags(M, KINDS, 'noLink');
        nComm = countFlags(M, KINDS, 'noComm');
        nVari = countFlags(M, KINDS, 'noVari');
        [nXml, xmlNote] = countXml(M, KINDS);

        totFull = totFull + nFull;
        if nXml >= 0, totXml = totXml + nXml; end

        fprintf('%-26s %6d %6d %6d %6d %6d %8s\n', trunc(M,26), ...
                nFull, nMask, nLink, nComm, nVari, xmlStr(nXml, xmlNote));

        % 🔴 API 가 XML 보다 적게 봤다면 무언가를 조용히 뺐다는 뜻이다.
        if nXml > nFull
            fail{end+1} = sprintf(['%s: XML 에 %d개인데 find_system 은 %d개만 봤다. ' ...
                                   'API 가 %d개를 조용히 뺐다.'], M, nXml, nFull, nXml - nFull); %#ok<AGROW>
        end
    end

    fprintf('%s\n', repmat('-', 1, 74));
    fprintf('%-26s %6d %6s %6s %6s %6s %8d\n\n', '합계', totFull, '', '', '', '', totXml);

    fprintf(['  열 읽는 법: `-Mask` 는 LookUnderMasks 를 뺐을 때의 수다.\n' ...
             '  정본보다 작으면 그 플래그가 이 모델에서 실제로 블록을 숨긴다는 뜻이고,\n' ...
             '  그 차이가 곧 「빼먹으면 사라지는 개수」다. 0 이 아니면 문서에 적는다.\n\n']);

    % ── ③ vault_units 분해 대조 ──────────────────────────
    U = vault_units(root);
    nSS = sum(strcmp({U.kind}, 'SubSystem'));
    nMR = sum(strcmp({U.kind}, 'ModelReference'));
    nCH = sum(strcmp({U.kind}, 'Stateflow Chart'));

    fprintf('분석 단위 (vault_units, 정본 열거 R19)\n');
    fprintf('  SubSystem        %4d   (라이브러리 마스크·Chart-SubSystem 제외 후)\n', nSS);
    fprintf('  ModelReference   %4d   (중복 참조는 한 번만)\n', nMR);
    fprintf('  Stateflow Chart  %4d\n', nCH);
    fprintf('  ──────────────────────\n');
    fprintf('  합계             %4d\n\n', numel(U));

    % 정본 열거는 제외 규칙 때문에 ①보다 **작아야** 한다. 크면 이중 계수다.
    if (nSS + nMR) > totFull
        fail{end+1} = sprintf(['vault_units 의 SubSystem+ModelReference 가 %d개인데 ' ...
                               '원시 열거는 %d개다. 같은 것을 두 번 세고 있다.'], nSS + nMR, totFull); %#ok<AGROW>
    end

    % ── 판정 ─────────────────────────────────────────────
    ok = isempty(fail);
    if ok
        fprintf('통과 — 두 열거원이 어긋나지 않는다.\n');
        fprintf('🔴 단, 「통과」는 「빠진 것이 없다」가 아니라 「두 방법이 같은 답을 냈다」이다.\n\n');
    else
        fprintf('🔴 실패 — %d건\n\n', numel(fail));
        for k = 1:numel(fail), fprintf('  %s\n', fail{k}); end
        fprintf(['\n무엇을 세고 있는지부터 의심한다. 감사 기준을 조이는 것으로는\n' ...
                 '열거에서 빠진 것을 되찾지 못한다.\n\n']);
    end
end


% ══════════════════════════════════════════════════════════
function n = countFlags(M, kinds, mode)
%COUNTFLAGS  침묵 제외 플래그를 하나씩 빼고 센다.
%
%   🔴 아래 find_system 호출들은 플래그를 **일부러** 뺀다. 그것이 이 함수의
%      목적이다 — 빼면 몇 개가 사라지는지 측정한다. 측정하지 않으면
%      「기본값이 조용히 뺀다」는 사실이 문서에 숫자로 남지 않는다.
    args = {'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on', ...
            'MatchFilter',@Simulink.match.allVariants};
    switch mode
        case 'full'
        case 'noMask', args = drop(args, 'LookUnderMasks');
        case 'noLink', args = drop(args, 'FollowLinks');
        case 'noComm', args = drop(args, 'IncludeCommented');
        case 'noVari', args = drop(args, 'MatchFilter');
    end
    n = 0;
    for k = 1:numel(kinds)
        b = find_system(M, args{:}, 'BlockType', kinds{k});   % lint:ok R26 민감도 측정 — 플래그 제거가 이 함수의 목적이다
        n = n + numel(b);
    end
end

function args = drop(args, name)
    i = find(strcmp(args, name), 1);
    if ~isempty(i), args([i i+1]) = []; end
end


% ══════════════════════════════════════════════════════════
function [n, note] = countXml(M, kinds)
%COUNTXML  .slx(zip) 안의 blockdiagram.xml 에서 BlockType 을 직접 센다.
%
%   Simulink API 를 거치지 않는 유일한 열거원이다. API 가 조용히 빼는 것을
%   여기서만 볼 수 있다. 라이브러리 내부는 모델 XML 에 없으므로 이 수가
%   API 보다 **작을 수는 있다.** 반대로 크면 API 가 뺐다는 뜻이다.
    n = -1; note = '';
    f = which(M);
    if isempty(f) || ~endsWith(lower(f), '.slx')
        note = 'n/a';   % .mdl 이거나 경로에 없다
        return
    end
    tmp = fullfile(tempdir, ['xcheck_' M '_' char(java.util.UUID.randomUUID)]);
    try
        unzip(f, tmp);
        xf = fullfile(tmp, 'simulink', 'blockdiagram.xml');
        if ~isfile(xf)
            d = dir(fullfile(tmp, '**', 'blockdiagram.xml'));
            if isempty(d), note = 'xml?'; cleanup(tmp); return; end
            xf = fullfile(d(1).folder, d(1).name);
        end
        txt = read_utf8(xf);
        n = 0;
        for k = 1:numel(kinds)
            n = n + numel(regexp(txt, ['BlockType="' kinds{k} '"'], 'start'));
        end
    catch ME
        note = 'err';
        fprintf('  (XML 열거 실패 %s: %s)\n', M, ME.message);
    end
    cleanup(tmp);
end

function cleanup(tmp)
    if isfolder(tmp)
        try, rmdir(tmp, 's'); catch, end %#ok<CTCH>
    end
end

function s = xmlStr(n, note)
    if n < 0, s = note; else, s = sprintf('%d', n); end
end

function s = trunc(s, n)
    s = char(s);
    if numel(s) > n, s = [s(1:n-1) '~']; end
end
