function ok = selftest_spec(dumpDir)
%SELFTEST_SPEC  compare_spec 이 「맞는 것을 0」으로, 「틀린 것을 정확히 그만큼」 잡는지 검사한다.
%
%   ok = selftest_spec()            현재 폴더의 _덤프
%   ok = selftest_spec(dumpDir)
%
%   왜 필요한가
%   ──────────
%   이 프로젝트에서 감사기는 두 번 뚫렸고, 검사 스크립트 자체가 조용히 틀린 일도 두 번 있었다
%   (selftest_harness 머리 참조). 대조기도 같은 종류다 — **실패를 못 내는 검사기는 검사기가 아니다.**
%   그래서 두 방향을 다 본다:
%     A. 왕복 — 덤프에서 낸 전이표.md 를 사양표로 읽어 같은 덤프와 대조하면 불일치 0
%     B. 변조 — 그 전이표를 세 군데 망가뜨리면 정확히 그만큼 잡힌다
%          B1 State 행 하나 삭제            → 남음(extraStates) +1
%          B2 전이 라벨 하나 변경            → 빠짐(missingTrans) +1, 남음(extraTrans) +1
%          B3 default 행 하나 삭제           → 남음(extraDefaults) +1
%        합계 정확히 4. 더 잡아도 덜 잡아도 실패다.
%
%   산출물은 tempdir 에 쓰고 덤프 폴더는 건드리지 않는다.

    if nargin < 1 || isempty(dumpDir), dumpDir = fullfile(pwd, '_덤프'); end
    transtab = fullfile(dumpDir, '전이표.md');
    if ~isfile(transtab)
        error('selftest_spec:noTranstable', '전이표가 없다: %s — emit_transtable 을 먼저 돌린다', transtab);
    end
    outDir = fullfile(tempdir, ['selftest_spec_' datestr(now, 'yyyymmdd_HHMMSS')]);
    mkdir(outDir);
    fprintf('\n──────── selftest_spec ────────\n');
    fails = {};

    % ── A. 왕복 ───────────────────────────────────────
    repA = compare_spec(transtab, dumpDir, fullfile(outDir, '사양대조_왕복.md'));
    nS = sum([repA.chart.nStateSpec]); nT = sum([repA.chart.nTransSpec]); nD = sum([repA.chart.nDefSpec]);
    if repA.total == 0
        fprintf('  [PASS] A 왕복 — Chart %d · State %d · 전이 %d · default %d, 불일치 0\n', numel(repA.chart), nS, nT, nD);
    else
        fails{end+1} = sprintf('A 왕복 불일치 %d (0 이어야 한다) — %s', repA.total, repA.out);
        fprintf('  [FAIL] A 왕복 — 불일치 %d\n', repA.total);
    end
    if nS == 0 || nT == 0
        fails{end+1} = sprintf('A 왕복 — State %d · 전이 %d: 0 은 「없다」가 아니라 「못 읽었다」다', nS, nT);
    end

    % ── B. 변조 ───────────────────────────────────────
    txt = read_utf8(transtab);
    txt = strrep(txt, sprintf('\r\n'), newline);

    % B1 State 표의 첫 데이터 행 삭제
    t1 = regexprep(txt, '\| `[^`\n]+` \| \d+ \| [A-Z_]+ \| [-\d]+ \| \d+ \|\n', '', 'once');
    b1 = ~strcmp(t1, txt);
    % B2 4.2 표에서 라벨이 있는 첫 전이 행의 라벨 끝에 _MUT
    [s, e] = regexp(t1, '\| `[^`\n]+` \| → \| `[^`\n]+` \| [-\d]+ \| `[^`\n]+` \|', 'start', 'end', 'once');
    b2 = ~isempty(s);
    if b2
        seg = t1(s:e);
        seg = regexprep(seg, '` \|$', '_MUT` |');
        t1 = [t1(1:s-1) seg t1(e+1:end)];
    end
    % B3 4.1 표의 첫 default 행 삭제
    t2 = regexprep(t1, '\| 1 \| `[^`\n]+` \| \w+ \| `[^`\n]*` \|[^\n]*\|\n', '', 'once');
    b3 = ~strcmp(t2, t1);
    if ~(b1 && b2 && b3)
        fails{end+1} = sprintf('B 변조를 걸지 못했다 (B1 %d · B2 %d · B3 %d) — 전이표 형식이 바뀌었나', b1, b2, b3);
    else
        mutFile = fullfile(outDir, '전이표_변조.md');
        fid = fopen(mutFile, 'w', 'n', 'UTF-8'); fprintf(fid, '%s', t2); fclose(fid);
        repB = compare_spec(mutFile, dumpDir, fullfile(outDir, '사양대조_변조.md'));
        got = struct( ...
            'extraStates',   sum(cellfun(@numel, {repB.chart.extraStates})), ...
            'missingTrans',  sum(cellfun(@numel, {repB.chart.missingTrans})), ...
            'extraTrans',    sum(cellfun(@numel, {repB.chart.extraTrans})), ...
            'extraDefaults', sum(cellfun(@numel, {repB.chart.extraDefaults})));
        want = struct('extraStates',1,'missingTrans',1,'extraTrans',1,'extraDefaults',1);
        fn = fieldnames(want);
        okB = (repB.total == 4);
        for k = 1:numel(fn)
            if got.(fn{k}) ~= want.(fn{k})
                okB = false;
                fails{end+1} = sprintf('B %s = %d (기대 %d)', fn{k}, got.(fn{k}), want.(fn{k})); %#ok<AGROW>
            end
        end
        if okB
            fprintf('  [PASS] B 변조 — 망가뜨린 4건을 정확히 4건으로 잡았다 (State 남음 1 · 전이 빠짐 1 남음 1 · default 남음 1)\n');
        else
            fprintf('  [FAIL] B 변조 — 합계 %d (기대 4)\n', repB.total);
        end
    end

    ok = isempty(fails);
    if ok
        fprintf('  selftest_spec 통과. 산출물: %s\n\n', outDir);
    else
        fprintf('\n  🔴 selftest_spec 실패 %d건:\n', numel(fails));
        for k = 1:numel(fails), fprintf('     %d) %s\n', k, fails{k}); end
        fprintf('  산출물: %s\n\n', outDir);
    end
end
