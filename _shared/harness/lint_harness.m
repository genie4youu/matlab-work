function ok = lint_harness(dirPath)
%LINT_HARNESS  하네스 스크립트 자체를 검사한다. 실패하면 분석을 시작하지 않는다.
%
%   ok = lint_harness()            % 현재 폴더
%   ok = lint_harness('C:\...\20260804')
%
%   왜 필요한가
%   ──────────
%   지금까지의 오류는 「분석 결과」가 아니라 **「분석 도구」**에서 났다.
%   도구가 조용히 틀리면 결과는 언제나 그럴듯하게 나온다.
%
%     - `find_system` 이 주석 블록을 뺐다 → 컨테이너 9개·블록 61개가 안 보였다 (R21)
%     - `fileread` 가 이모지를 지웠다 → 해석 문자가 소리 없이 사라졌다 (R20)
%     - 배치 스크립트가 해석 51개를 채워 감사를 통과시켰다 (R15)
%
%   셋 다 **코드를 읽으면 보이는 것**이었다. 사람이 매번 읽지 않을 뿐이다.
%   그래서 기계가 읽는다.
%
%   검사 항목
%   ────────
%     L1  find_system 호출에 침묵 제외 플래그가 다 있는가        (R3, R21)
%     L2  fileread 를 쓰지 않는가                                 (R20)
%     L3  해석을 배치로 채우는 스크립트가 되살아나지 않았는가      (R15)
%     L4  폴더명·열거·해석구조의 단일 정의를 우회하지 않는가       (R13, R17, R19)
%
%   면제가 필요하면 그 줄에 `% lint:ok <이유>` 를 단다. 침묵 면제는 없다.

    % 기본 대상은 **하네스가 있는 폴더**다. 세션 폴더가 아니다 —
    % 하네스를 `_shared\harness\` 로 옮긴 뒤 pwd 를 보면 아무것도 검사하지 않는다.
    if nargin < 1 || isempty(dirPath), dirPath = fileparts(mfilename('fullpath')); end
    files = dir(fullfile(dirPath, '*.m'));
    SELF  = {'lint_harness.m'};

    fprintf('\n=== 하네스 자체 검사 (lint_harness) ===\n');
    v = {};   % 위반 {규칙, 파일, 내용}

    for k = 1:numel(files)
        if any(strcmp(files(k).name, SELF)), continue; end
        f   = fullfile(files(k).folder, files(k).name);
        raw = read_utf8(f);
        % 줄 연속(...)을 이어붙여 한 호출을 한 줄로 만든다.
        % 이걸 안 하면 여러 줄에 걸친 호출을 「플래그 없음」으로 오판한다.
        cat = regexprep(raw, '\.\.\.\s*\r?\n\s*', ' ');
        lines = strsplit(cat, newline);

        for j = 1:numel(lines)
            L = lines{j};
            if contains(L, 'lint:ok'), continue; end
            if ~isempty(regexp(L, '^\s*%', 'once')), continue; end   % 주석 줄

            % ── L1. find_system 침묵 제외 ─────────────
            if contains(L, 'find_system(')
                need = {'LookUnderMasks','IncludeCommented'};
                if ~contains(L,'''Type''') && ~contains(L,'FindAll')
                    need = [need {'FollowLinks','MatchFilter'}]; %#ok<AGROW>
                end
                miss = need(~cellfun(@(n) contains(L,n), need));
                if ~isempty(miss)
                    v(end+1,:) = {'L1', files(k).name, ...
                        sprintf('find_system 에 %s 없음 — %s', strjoin(miss,', '), trim(L))}; %#ok<AGROW>
                end
            end

            % ── L2. fileread ──────────────────────────
            if ~isempty(regexp(L, '(?<![\w.])fileread\s*\(', 'once'))
                v(end+1,:) = {'L2', files(k).name, ...
                    sprintf('fileread 사용 — read_utf8 을 쓴다 (R20). %s', trim(L))}; %#ok<AGROW>
            end

            % ── L4. 단일 정의 우회 ────────────────────
            %   폴더명을 vault_segs 밖에서 직접 조립하면 감사와 갈라진다 (R13).
            if contains(L,'strjoin(') && contains(L,'''_''') && contains(L,'.md') ...
               && ~contains(files(k).name,'vault_') && ~contains(L,'u.segs') && ~contains(L,'segs{:}')
                v(end+1,:) = {'L4', files(k).name, ...
                    sprintf('문서 파일명을 직접 조립 — vault_segs 를 쓴다 (R13). %s', trim(L))}; %#ok<AGROW>
            end
        end
    end

    % ── L3. 배치 해석 채우기 부활 ─────────────────────
    for k = 1:numel(files)
        n = files(k).name;
        if ~isempty(regexp(lower(n), '^fill_', 'once'))
            v(end+1,:) = {'L3', n, '해석을 배치로 채우는 스크립트다. `_폐기\` 로 옮긴다 (R15)'}; %#ok<AGROW>
        end
    end

    % ── 보고 ──────────────────────────────────────────
    ok = isempty(v);
    if ok
        fprintf('통과 — 검사 파일 %d개, 위반 0건\n\n', numel(files));
    else
        fprintf('🔴 실패 — 위반 %d건\n\n', size(v,1));
        for k = 1:size(v,1)
            fprintf('  [%s] %-24s %s\n', v{k,1}, v{k,2}, v{k,3});
        end
        fprintf('\n고치기 전에는 분석을 시작하지 않는다. 도구가 틀리면 결과는 언제나 그럴듯하다.\n\n');
    end
end

function s = trim(s)
    s = strtrim(regexprep(s, '\s+', ' '));
    if numel(s) > 110, s = [s(1:110) ' ...']; end
end
