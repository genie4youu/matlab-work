function outFile = emit_transtable(dumpDir, outFile)
%EMIT_TRANSTABLE  덤프에서 **손 변환용 전이표**를 만든다.
%
%   emit_transtable('C:\...\20260804\_덤프')
%   emit_transtable(dumpDir, 'C:\...\_덤프\전이표.md')
%
%   왜 만드나 (사용자 확정, 2026-09-07)
%   ──────────────────────────────────
%   이 PC 는 Embedded Coder 라이선스가 0 이라 **C 로 가는 경로가 손 변환뿐**이다.
%   (`ExampleLib_ert_rtw` 의 생성 코드는 다른 PC 에서 온 것이다.)
%   그런데 저작 체계가 「모델을 잘 만드는가」만 보고 「그 다음 C 로 어떻게 가는가」를
%   안 보면 업무 ②와 끊긴다. 덤프 4종이 이미 손 변환 사양의 8할이므로
%   그것을 옮겨 적을 수 있는 형태로 낸다.
%
%   무엇을 담나
%   ──────────
%     1. Chart 요약      Decomposition · ActionLanguage · SampleTime
%                        → 병렬이면 C 에서 「순서대로 다 실행」, 배타면 「하나만」
%     2. State 계층      깊이 · 부모 · 병렬 여부 · entry/during/exit **원문**
%                        → enum 과 함수 본문의 재료
%     3. 전이표          Source → Destination · 실행순서 · 조건/액션 **원문**
%                        → if / switch 의 순서와 조건
%     4. Junction 경유   default → Junction → State 를 펼쳐 초기 상태를 보여준다
%     5. Data            이름 · Scope · 타입 · 초기값 · 범위 → 변수 선언
%
%   🔴 LabelString 은 원문 그대로 코드블록에 넣는다.
%      MATLAB 의 `...` 는 줄이어짐이므로 개행을 ' ; ' 로 바꾸면 조건식의 뜻이 달라진다.
%      실측(2026-09-08): Example_Main_SF 의 Transition 95개 중 17개가 개행을 포함한다.
%
%   🔴 C 코드를 만들어 주지 않는다.
%      이 표는 **사람이 옮겨 적을 때 보는 사양**이다. 변환 자체를 자동화하면
%      「모델과 같은가」를 판정할 수단이 없는 채로 코드가 생긴다.

    if nargin < 1 || isempty(dumpDir)
        dumpDir = fullfile(pwd, '_덤프');
    end
    if nargin < 2 || isempty(outFile)
        outFile = fullfile(dumpDir, '전이표.md');
    end

    charts = read_json(fullfile(dumpDir,'charts.json'));
    nodes  = read_json(fullfile(dumpDir,'nodes.json'));
    edges  = read_json(fullfile(dumpDir,'edges.json'));
    meta   = read_json(fullfile(dumpDir,'meta.json'));
    if isempty(charts)
        error('emit_transtable:noDump', ...
            'charts.json 이 없거나 비었다: %s\n  emit_dump 를 먼저 돌린다.', dumpDir);
    end

    fid = fopen(outFile, 'w', 'n', 'UTF-8');
    if fid < 0, error('emit_transtable:write','파일을 열지 못했다: %s', outFile); end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    p = @(varargin) fprintf(fid, varargin{:});

    p('# 전이표 — 손 변환 사양\n\n');
    if ~isempty(meta) && isfield(meta,'root')
        p('- 대상: `%s`\n', meta.root);
    end
    p('- 생성: `emit_transtable.m` — 덤프(JSON)에서 기계가 옮긴 것이며 해석이 없다\n');
    p('- 원본 수집: %s\n', getfielddef(meta, 'collected', '(미상)'));
    p('- 열거: %s\n\n', getfielddef(meta, 'enumeration', '(미상)'));
    p(['> 🔴 이 표는 **사양**이지 코드가 아니다. Action 과 조건은 모델의 원문을 그대로 옮겼다.\n' ...
       '> MATLAB 의 `...` 는 줄이어짐이므로 개행을 살려서 읽는다.\n\n']);
    p('---\n\n');

    for c = 1:numel(charts)
        ch = charts(c);
        cp = ch.chart;
        nSel = nodes(strcmp({nodes.chart}, cp));
        if isempty(edges), eSel = edges; else, eSel = edges(strcmp({edges.chart}, cp)); end
        st = nSel(strcmp({nSel.kind}, 'State'));
        ju = nSel(strcmp({nSel.kind}, 'Junction'));

        p('## %d. `%s`\n\n', c, cp);

        % ── 1. Chart 요약 ─────────────────────────────
        d = getfielddef(ch.props, 'Decomposition', '(미상)');
        p('### %d.1 Chart\n\n', c);
        p('| 항목 | 값 | C 로 옮길 때 |\n| --- | --- | --- |\n');
        if strcmp(d,'PARALLEL_AND')
            note = '병렬 — 최상위 State 를 **매 스텝 전부** 실행순서대로 호출한다';
        else
            note = '배타 — 활성 State **하나만** 실행한다 (enum + switch)';
        end
        p('| Decomposition | `%s` | %s |\n', d, note);
        p('| ActionLanguage | `%s` | %s |\n', getfielddef(ch.props,'ActionLanguage','(미상)'), ...
            '`MATLAB` 이면 벡터·행렬 연산이 섞일 수 있어 손 변환 비용이 오른다');
        p('| SampleTime | `%s` | `-1` 은 상속 — 호출 주기는 부모가 정한다 |\n', ...
            getfielddef(ch.props,'SampleTime','(미상)'));
        p('| StatesWhenEnabling | `%s` | 재진입 시 상태 유지 여부 |\n', ...
            getfielddef(ch.props,'StatesWhenEnabling','(미상)'));
        p('| State / Transition / Junction | %d / %d / %d | |\n\n', numel(st), numel(eSel), numel(ju));

        % ── 2. State 계층 ─────────────────────────────
        p('### %d.2 State 계층\n\n', c);
        [~, ord] = sort({st.path});
        p('| 경로 | 깊이 | 자식분해 | 실행순서 | 하위 |\n| --- | --- | --- | --- | --- |\n');
        for i = ord
            s = st(i);
            depth = numel(strfind(s.path,'.'));
            nKid = sum(startsWith({st.path}, [s.path '.']));
            p('| `%s` | %d | %s | %s | %d |\n', s.path, depth, s.decomposition, ...
                numstr(s.executionOrder), nKid);
        end
        p('\n');

        % ── 3. State Action 원문 ──────────────────────
        p('### %d.3 State Action (원문)\n\n', c);
        any3 = false;
        for i = ord
            s = st(i);
            if isempty(strtrim(s.label)), continue; end
            any3 = true;
            p('**`%s`**\n\n```\n%s\n```\n\n', s.path, s.label);
        end
        if ~any3, p('(Action 이 있는 State 없음)\n\n'); end

        % ── 4. 전이표 ─────────────────────────────────
        p('### %d.4 전이표\n\n', c);
        if isempty(eSel)
            p('전이가 없다. Chart 가 `PARALLEL_AND` 이면 정상이다 — State 들이 동시에 활성화된다.\n\n');
        else
            defIdx = find([eSel.isDefault]);
            othIdx = find(~[eSel.isDefault]);

            p('#### %d.4.1 초기 진입 (default transition %d개)\n\n', c, numel(defIdx));
            p('| # | 목적지 | 종류 | 도달하는 State | 조건/액션 |\n| --- | --- | --- | --- | --- |\n');
            for k = 1:numel(defIdx)
                e = eSel(defIdx(k));
                if strcmp(e.dstType,'Junction')
                    reach = strjoin(viaJunction(e.dst, eSel, {ju.name}), ', ');
                    if isempty(reach), reach = '(추적 실패)'; end
                else
                    reach = e.dst;
                end
                p('| %d | `%s` | %s | `%s` | %s |\n', k, e.dst, e.dstType, reach, inline_md(e.label));
            end
            p('\n');

            p('#### %d.4.2 전이 (%d개) — 실행순서가 곧 if 의 순서다\n\n', c, numel(othIdx));
            src = {eSel(othIdx).src};
            [~, so] = sort(src);
            p('| Source | → | Destination | 순서 | 조건/액션 |\n| --- | --- | --- | --- | --- |\n');
            for k = so
                e = eSel(othIdx(k));
                p('| `%s` | → | `%s` | %s | %s |\n', e.src, e.dst, ...
                    numstr(e.executionOrder), inline_md(e.label));
            end
            p('\n');

            % 개행이 든 라벨은 표에서 읽을 수 없으므로 원문을 따로 낸다
            multi = othIdx(cellfun(@(x) contains(x, newline), {eSel(othIdx).label}));
            if ~isempty(multi)
                p('#### %d.4.3 여러 줄 조건 (원문 — `...` 는 줄이어짐이다)\n\n', c);
                for k = 1:numel(multi)
                    e = eSel(multi(k));
                    p('**`%s` → `%s`**\n\n```\n%s\n```\n\n', e.src, e.dst, e.label);
                end
            end
        end

        % ── 5. Data ───────────────────────────────────
        p('### %d.5 Data — 변수 선언의 재료\n\n', c);
        p('> Data 상세는 `types.json`(collect_types) 이 정본이다. 여기서는 개수만 적는다.\n\n');
        p('Chart Data %d개.\n\n', getfielddef(ch.counts, 'data', 0));

        p('---\n\n');
    end

    fprintf('  전이표 → %s\n', outFile);
end


% ══════════════════════════════════════════════════════

function names = viaJunction(startDst, eSel, juNames)
%VIAJUNCTION  default 가 Junction 을 거쳐 닿는 State 들을 모은다.
%   `default → Junction → [조건] → State` 가 정상 패턴이므로 펼쳐서 보여준다.
    names = {};
    queue = {startDst};
    seen  = {};
    for guard = 1:1000
        if isempty(queue), break; end
        cur = queue{1}; queue(1) = [];
        if any(strcmp(seen, cur)), continue; end
        seen{end+1} = cur; %#ok<AGROW>
        if any(strcmp(juNames, cur))
            nxt = {eSel(strcmp({eSel.src}, cur)).dst};
            if ~isempty(nxt), queue = [queue, reshape(nxt,1,[])]; end %#ok<AGROW>
        else
            names{end+1} = cur; %#ok<AGROW>
        end
    end
    names = unique(names);
end

function s = inline_md(s)
%INLINE_MD  표 한 칸에 넣기 위한 형태. **원문은 4.3 절에 따로 낸다.**
    if isempty(s), s = ''; return; end
    s = strrep(s, '|', '\|');
    s = regexprep(s, '\s*\n\s*', ' ⏎ ');   % 개행이 있었다는 사실을 남긴다
    s = ['`' s '`'];
end

function v = getfielddef(S, f, d)
    v = d;
    if isstruct(S) && isfield(S, f)
        v = S.(f);
    end
end

function s = numstr(x)
    if isnumeric(x) && isscalar(x) && ~isnan(x), s = num2str(x); else, s = '-'; end
end

function S = read_json(p)
    S = [];
    if ~isfile(p), return; end
    fid = fopen(p, 'r', 'n', 'UTF-8');
    if fid < 0, return; end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    raw = fread(fid, '*char')';
    if isempty(strtrim(raw)), return; end
    try
        d = jsondecode(raw);
    catch
        return
    end
    if iscell(d)
        try, d = [d{:}]; catch, end
    end
    if isstruct(d) && ~isscalar(d), S = reshape(d,1,[]); else, S = d; end
end
