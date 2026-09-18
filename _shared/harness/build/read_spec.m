function spec = read_spec(specFile)
%READ_SPEC  사양표(markdown)를 읽어 struct 로 만든다. 모델을 열지 않는다.
%
%   spec = read_spec('C:\...\<모델>_사양.md')
%   spec = read_spec('C:\...\_덤프\전이표.md')     ← 전이표도 같은 형식이라 그대로 읽힌다
%
%   왜 전이표 형식을 사양표로 쓰나 (2026-09-16 결정 — 결정이력 「저작 파이프라인」)
%   ─────────────────────────────────────────────────────────────────────
%   사양표가 **정본**이고 모델은 구현이다. 「사양에 있는 것이 모델에 있고 모델에 있는 것이
%   사양에 있다」를 기계로 대조하려면 사양표와 덤프가 **같은 표**여야 한다.
%   `emit_transtable` 이 덤프에서 내는 전이표가 이미 그 표이므로, 사양표는 그 형식에
%   사양에만 있는 절(인터페이스 · 금지 조건 · 수용 시험) 셋을 더한 것이다.
%   → 덤프 → 전이표 → read_spec → compare_spec(같은 덤프) 가 **불일치 0** 이어야 한다(왕복 시험).
%
%   읽는 절 (Chart 마다, 전이표와 동일)
%   ─────────────────────────────────
%     ## N. `<chart path>`
%     ### N.1 Chart            | 항목 | 값 | ... |        → props.(항목) = 값
%     ### N.2 State 계층       | 경로 | 깊이 | 자식분해 | 실행순서 | 하위 |
%     ### N.3 State Action     **`경로`** + ``` 원문 ```   → states(k).label
%     #### N.4.1 초기 진입     | # | 목적지 | 종류 | 도달하는 State | 조건/액션 |
%     #### N.4.2 전이          | Source | → | Destination | 순서 | 조건/액션 |
%     #### N.4.3 여러 줄 조건  **`src` → `dst`** + ``` 원문 ```  → 그 전이의 label 을 원문으로 덮는다
%
%   사양에만 있는 절 (있으면 표 행을 그대로 담는다 — lint_spec · equiv_test 가 쓴다)
%   ───────────────────────────────────────────────────────────────
%     제목에 「인터페이스」 → spec.interface   (| 이름 | 방향 | 타입 | 범위/단위 | 설명 |)
%     제목에 「금지」       → spec.forbidden    (| # | 문장 | 검사 방법 |)
%     제목에 「수용」       → spec.acceptance   (| # | 입력 시퀀스 | 기대 출력/State |)
%
%   내는 것
%   ──────
%     spec.file, spec.model(전이표 머리의 「대상」이 있으면)
%     spec.charts(c).chart · .props · .states(path, decomposition, executionOrder, label)
%                  .defaults(dst, dstType, label) · .transitions(src, dst, executionOrder, label)
%     spec.interface / spec.forbidden / spec.acceptance — cell 표(헤더 포함), 없으면 {}
%
%   ⚠️ 표 한 칸의 라벨은 `inline_md` 형식(`백틱`, `\|`, ` ⏎ `)이다. 여기서 되돌린다.
%      되돌린 라벨은 줄 경계의 공백이 없으므로 compare_spec 은 양쪽을 같은 규칙으로 정규화한다.
%   ⚠️ Junction 은 State 표에 없다. 전이의 끝점 이름으로만 나타난다(덤프의 `J<id>`).

    if nargin < 1 || ~isfile(specFile)
        error('read_spec:noFile', '사양표 파일이 없다: %s', char(string(specFile)));
    end
    txt   = read_utf8(specFile);
    txt   = strrep(txt, sprintf('\r\n'), newline);
    lines = strsplit(txt, newline, 'CollapseDelimiters', false);

    spec = struct('file', specFile, 'model', '', 'charts', struct([]), ...
                  'interface', {{}}, 'forbidden', {{}}, 'acceptance', {{}});

    m = regexp(txt, '^- 대상: `([^`]+)`', 'tokens', 'once', 'lineanchors');
    if ~isempty(m), spec.model = m{1}; end

    sect  = '';         % 지금 어느 절인가
    cIdx  = 0;          % 현재 Chart 인덱스
    i     = 1;
    while i <= numel(lines)
        L = lines{i};

        % ── Chart 머리 ────────────────────────────────
        t = regexp(L, '^## \d+\. `([^`]+)`', 'tokens', 'once');
        if ~isempty(t)
            cIdx = cIdx + 1;
            spec.charts(cIdx).chart       = t{1};
            spec.charts(cIdx).props       = struct();
            spec.charts(cIdx).states      = empty_states();
            spec.charts(cIdx).defaults    = empty_defaults();
            spec.charts(cIdx).transitions = empty_trans();
            sect = '';
            i = i + 1; continue
        end

        % ── 절 판정 ───────────────────────────────────
        if startsWith(L, '#')
            h = lower(L);
            if     contains(h, '초기 진입'),      sect = 'defaults';
            elseif contains(h, '여러 줄'),        sect = 'multi';
            elseif contains(h, '전이'),           sect = 'trans';
            elseif contains(h, 'state action'),   sect = 'action';
            elseif contains(h, 'state 계층'),     sect = 'states';
            elseif contains(h, 'chart'),          sect = 'props';
            elseif contains(h, '인터페이스'),     sect = 'interface';
            elseif contains(h, '금지'),           sect = 'forbidden';
            elseif contains(h, '수용'),           sect = 'acceptance';
            else,                                 sect = '';
            end
            i = i + 1; continue
        end

        % ── 표 행 ─────────────────────────────────────
        if startsWith(strtrim(L), '|')
            cells = split_row(L);
            if isempty(cells) || all(cellfun(@(c) ~isempty(regexp(c, '^-+$', 'once')), cells))
                i = i + 1; continue                     % | --- | 구분선
            end
            switch sect
                case 'props'
                    if cIdx > 0 && numel(cells) >= 2 && ~strcmp(cells{1}, '항목')
                        key = regexprep(cells{1}, '[^A-Za-z0-9_]', '');
                        if ~isempty(key) && ~isempty(regexp(key, '^[A-Za-z]', 'once'))
                            spec.charts(cIdx).props.(key) = unbt(cells{2});
                        end
                    end
                case 'states'
                    if cIdx > 0 && numel(cells) >= 4 && ~strcmp(cells{1}, '경로')
                        s = struct('path', unbt(cells{1}), 'decomposition', cells{3}, ...
                                   'executionOrder', tonum(cells{4}), 'label', '');
                        spec.charts(cIdx).states(end+1) = s;
                    end
                case 'defaults'
                    if cIdx > 0 && numel(cells) >= 5 && ~strcmp(cells{1}, '#')
                        d = struct('dst', unbt(cells{2}), 'dstType', cells{3}, ...
                                   'label', decode_inline(cells{5}));
                        spec.charts(cIdx).defaults(end+1) = d;
                    end
                case 'trans'
                    if cIdx > 0 && numel(cells) >= 5 && ~strcmp(cells{1}, 'Source')
                        e = struct('src', unbt(cells{1}), 'dst', unbt(cells{3}), ...
                                   'executionOrder', tonum(cells{4}), ...
                                   'label', decode_inline(cells{5}));
                        spec.charts(cIdx).transitions(end+1) = e;
                    end
                case {'interface', 'forbidden', 'acceptance'}
                    spec.(sect)(end+1, 1:numel(cells)) = cells;
            end
            i = i + 1; continue
        end

        % ── 원문 코드블록 (State Action · 여러 줄 조건) ───
        if cIdx > 0 && any(strcmp(sect, {'action', 'multi'})) && startsWith(L, '**`')
            head = L;
            % 다음 ``` 블록을 읽는다
            j = i + 1;
            while j <= numel(lines) && ~startsWith(strtrim(lines{j}), '```'), j = j + 1; end
            body = '';
            if j <= numel(lines)
                k = j + 1;
                while k <= numel(lines) && ~startsWith(strtrim(lines{k}), '```')
                    body = [body, lines{k}, newline]; %#ok<AGROW>
                    k = k + 1;
                end
                body = regexprep(body, '\n$', '');
                i = k + 1;
            else
                i = i + 1;
            end
            if strcmp(sect, 'action')
                t = regexp(head, '^\*\*`([^`]+)`\*\*', 'tokens', 'once');
                if ~isempty(t)
                    idx = find(strcmp({spec.charts(cIdx).states.path}, t{1}), 1);
                    if ~isempty(idx), spec.charts(cIdx).states(idx).label = body; end
                end
            else
                t = regexp(head, '^\*\*`([^`]*)` → `([^`]+)`\*\*', 'tokens', 'once');
                if ~isempty(t)
                    tr = spec.charts(cIdx).transitions;
                    cand = find(strcmp({tr.src}, t{1}) & strcmp({tr.dst}, t{2}));
                    % 같은 src→dst 가 여럿이면 인라인 라벨이 같은 것을 고른다
                    pick = [];
                    for q = cand
                        if strcmp(norm_label(tr(q).label), norm_label(body)), pick = q; break; end
                    end
                    if isempty(pick) && ~isempty(cand), pick = cand(1); end
                    if ~isempty(pick), spec.charts(cIdx).transitions(pick).label = body; end
                end
            end
            continue
        end

        i = i + 1;
    end
end

% ══════════════════════════════════════════════════════

function cells = split_row(L)
%SPLIT_ROW  `| a | b |` 를 칸으로. `\|` 는 칸 구분자가 아니다.
    L = strtrim(L);
    L = regexprep(L, '^\|', '');
    L = regexprep(L, '\|$', '');
    parts = regexp(L, '(?<!\\)\|', 'split');
    cells = cellfun(@strtrim, parts, 'UniformOutput', false);
end

function s = unbt(s)
%UNBT  양끝 백틱 제거
    s = strtrim(s);
    s = regexprep(s, '^`', '');
    s = regexprep(s, '`$', '');
end

function s = decode_inline(s)
%DECODE_INLINE  emit_transtable 의 inline_md 를 되돌린다.
    s = strtrim(s);
    if isempty(s), return; end
    s = regexprep(s, '^`', '');
    s = regexprep(s, '`$', '');
    s = strrep(s, ' ⏎ ', newline);
    s = strrep(s, '⏎', newline);
    s = strrep(s, '\|', '|');
end

function v = tonum(s)
    v = str2double(strtrim(s));      % '-' 는 NaN
end

function s = norm_label(s)
%NORM_LABEL  compare_spec 과 같은 규칙 — 줄 경계 공백 제거, CRLF→LF
    s = strrep(s, sprintf('\r\n'), newline);
    s = regexprep(s, '\s*\n\s*', newline);
    s = strtrim(s);
end

function s = empty_states()
    s = struct('path', {}, 'decomposition', {}, 'executionOrder', {}, 'label', {});
end
function s = empty_defaults()
    s = struct('dst', {}, 'dstType', {}, 'label', {});
end
function s = empty_trans()
    s = struct('src', {}, 'dst', {}, 'executionOrder', {}, 'label', {});
end
