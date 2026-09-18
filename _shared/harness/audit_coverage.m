function audit_coverage(model, vaultDir, outFile)
%AUDIT_COVERAGE  모델의 모든 분석 단위를 열거하고, 볼트 문서와 1:1 로 대조한다.
%
%   audit_coverage('ExampleModel', 'C:\Users\leeyj\Documents\yj.lee\work\sessions\20260804\서브시스템', ...
%                  '_분석출력\coverage.md')
%
%   왜 만들었나
%   ──────────
%   2026-08-04 분석에서 「Fault_Management 하위 컨테이너 3개」로 적었으나 실제는 4개였다.
%   BlockType='SubSystem' 으로만 셌고 ModelReference 를 빠뜨렸기 때문이다.
%   사람이 「빠짐없이」 확인하는 것은 반복 실패한다. 기계가 목록을 만들고 대조한다.
%
%   2026-08-04 개정 — 초판이 통과시킨 것이 실제로는 통과가 아니었다
%   ────────────────────────────────────────────────────────────
%   초판은 73/73 통과 · 해석 미기재 0 을 냈으나 분석은 부실했다. 구멍이 셋이었다.
%
%     (1) 경로 문자열을 볼트 문서 **전체**에서 찾았다. `_안내.md` 가 목차라서
%         경로 27개를 담고 있었고, 그 27개는 개별 문서가 없어도 통과했다.
%         하위 블록 119개짜리 Make_PDO_Outputs 가 「목차에 이름이 있다」로 통과했다.
%         → 개정: 경로에서 기대 파일 경로를 **결정론적으로 계산**하고 그 파일 안에서만 찾는다.
%           목차·교차표는 근거가 될 수 없다. 대조 대상에서 제외한다.
%
%     (2) `## 해석` 절이 없는 문서를 continue 로 건너뛰었다. 절을 안 만들면 통과였다.
%         → 개정: 해석 절 없음 = 실패.
%
%     (3) 해석 판정이 「120자 이상」뿐이라 배치 스크립트로 뚫렸다.
%         실제로 fill_interpretations.m 이 51개 문서를 한 번에 채워 통과시켰다.
%         → 개정: 그 블록 **고유의 식별자**(하위 컨테이너·Data Store·Goto 태그·
%           State·Data·Event 이름)가 해석 절 본문에 몇 개 등장하는지 센다.
%           글자수는 배치로 뚫리지만 블록 고유 식별자는 뚫리지 않는다.
%
%   ⚠️ 식별자 검사는 **문서 전체가 아니라 `## 해석` 절 본문에서만** 한다.
%      기계 추출 표에는 그 블록의 이름이 전부 들어 있으므로,
%      문서 전체를 대상으로 하면 이 검사는 자동으로 통과해 버린다.
%
%   2026-08-05 4판 — 판정 ④ 「설명 가능성」 추가
%   ────────────────────────────────────────
%   3판까지의 판정 3개는 **누락**과 **배치 채우기**를 막는다. 그러나 셋 다 통과한
%   문서를 사용자가 읽고 이해하지 못하는 상태가 발생했다. 내용이 틀린 것이 아니라
%   **쓰는 쪽이 이미 아는 것을 생략**했고, 생략을 잡는 판정이 없었다.
%
%     예: "Memory(ic 0) 자기 루프가 0과 1을 번갈아 내고 ... 정렬 순서 133"
%         → 사실은 맞다. 그러나 Memory 가 무엇인지, 자기 루프가 왜 토글이 되는지,
%           133 이 무슨 숫자인지가 문서 어디에도 없다.
%
%   판정 ④ 는 해석 절이 **정해진 소절 5개**를 갖추었는지 본다. 소절 구조의 단일
%   정의는 emit_interp.m 이다 (vault_segs.m 이 폴더명 규칙의 단일 정의인 것과 같다).
%
%     ④-a 소절 5개가 모두 있고 각각 내용이 있다 (주석만 남은 뼈대는 실패)
%     ④-b 「일어나는 일」 소절에 번호 단계가 2개 이상 있다
%     ④-c 「이 문서에 나온 용어」 소절에 용어 사전 위키링크가 1개 이상 있다
%
%   ⚠️ 용어 미설명은 **경고이지 실패가 아니다.** 오탐이 잦으면 사람이 감사 전체를
%      무시하게 되고, 그러면 마지막 방어선인 사람이 죽는다.
%
%   세는 규칙
%   ────────
%   분석 단위 = 하위를 갖거나 다른 파일을 참조하는 모든 블록
%     - SubSystem            (Simulink 라이브러리 마스크는 부모 문서에 흡수)
%     - ModelReference       ← 초판 사고의 원인
%     - Stateflow Chart
%
%   find_system 호출은 항상 아래 3개를 명시한다. 기본값에 맡기지 않는다.
%     'LookUnderMasks','all'      마스크 아래까지
%     'FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants          라이브러리 링크 따라감
%        비활성 Variant 포함

    if ~bdIsLoaded(model), load_system(model); end
    d = fileparts(outFile);
    if ~isempty(d) && ~isfolder(d), mkdir(d); end
    fid = fopen(outFile,'w','n','UTF-8');
    oc  = onCleanup(@() fclose(fid));
    p = @(varargin) fprintf(fid, varargin{:});

    LIBMASK     = {'Compare To Constant','Compare To Zero','Detect Change','Detect Increase'};
    PLACEHOLDER = '아직 채우지 않았다';
    MINCHARS    = 120;   % 해석 절 본문 최소 길이 (필요조건일 뿐 충분조건이 아니다)
    MINIDENT    = 3;     % 해석 절에 등장해야 하는 그 블록 고유 식별자 최소 개수
    MINSTEPS    = 2;     % 「일어나는 일」 소절의 최소 번호 단계 수
    MINSUBCHARS = 20;    % 소절 하나의 최소 길이 (HTML 주석 제거 후)

    % 판정 ④ 가 요구하는 소절 제목. emit_interp.m 이 쓰는 제목과 **같아야 한다.**
    SUBSECS = {'한 줄로','일어나는 일','숫자의 근거','이 문서에 나온 용어','근거와 미확인'};
    DICTS   = {'Simulink_모델읽는법','Stateflow_읽는법'};

    % 본문에 나오면 용어 소절에서 설명되어야 하는 말. **경고 전용이다.**
    % 오탐이 잦으면 사람이 감사를 무시하게 되므로 목록을 함부로 넓히지 않는다.
    TERMS = {'정렬 순서','Data Store','Enable','Trigger','포화','자기 루프', ...
             'Goto','Bus','Variant','대수 루프','during','Junction','병렬'};

    p('# 커버리지 감사 — `%s`\n\n', model);
    p('분석 단위를 기계가 열거하고 **1:1 로 대응하는 볼트 문서**를 대조한다.\n');
    p('**「빠짐없이」를 사람이 판단하지 않는다.**\n\n');
    p('판정 4개가 **모두** 통과해야 「분석 완료」다.\n\n');
    p('| 판정 | 무엇을 보는가 | 무엇을 막는가 |\n| --- | --- | --- |\n');
    p('| ① 문서 1:1 | 경로에서 계산한 **그 파일**이 있고 본문에 전체 경로가 있는가 | 목차·교차표에 이름만 스치고 넘어가는 것 |\n');
    p('| ② 해석 기재 | `## 해석` 절이 **있고** 자리표시자가 아니며 %d자 이상인가 | 절을 지워 검사를 피하는 것 |\n', MINCHARS);
    p('| ③ 식별자 교집합 | 그 블록 **고유 식별자**가 해석 절 본문에 %d개 이상 있는가 | 배치 스크립트로 분량만 채우는 것 |\n', MINIDENT);
    p('| ④ 설명 가능성 | 소절 5개(`%s`)가 채워졌고, 단계가 %d개 이상이며, 용어 사전 링크가 있는가 | 쓰는 쪽이 이미 아는 것을 생략해 읽는 쪽이 못 따라오는 것 |\n\n', ...
        strjoin(SUBSECS, ' / '), MINSTEPS);

    % ── 1. 분석 단위 열거 ─────────────────────────────
    % 🔴 **열거는 vault_units.m 하나가 한다** (R19). 여기서 다시 세지 않는다.
    %    전에는 이 파일과 gen_vault_tree 가 각자 열거했고 실제로 갈라졌다:
    %    Chart 는 sfroot 의 로드 상태에 따라 3/7/9 로 흔들렸고(R18), 참조 모델
    %    내부 컨테이너 27개는 어느 쪽도 세지 않아 아무 판정에도 걸리지 않았다.
    V    = vault_units(model);
    mdls = find_mdlrefs(model);

    % 라이브러리 마스크는 vault_units 가 이미 제외했다. 개수만 따로 센다.
    nLib = 0;
    for i = 1:numel(mdls)
        L = find_system(mdls{i},'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants, ...
                        'BlockType','SubSystem');
        for k = 1:numel(L)
            mt = ''; try, mt = get_param(L{k},'MaskType'); catch, end %#ok<CTCH>
            if any(strcmp(mt, LIBMASK)), nLib = nLib + 1; end
        end
    end

    kinds = {V.kind};
    nSS = sum(strcmp(kinds,'SubSystem'));
    nMR = sum(strcmp(kinds,'ModelReference'));
    nCH = sum(strcmp(kinds,'Stateflow Chart'));
    nRoot = sum(strcmp({V.model}, model));

    p('## 1. 분석 단위 집계\n\n');
    p('**대상 범위.** `find_mdlrefs` 가 연 모델 %d개 **전부**다 (규칙 R19). 최상위 모델뿐 아니라 **참조 모델 내부까지** 분석 단위로 센다.\n\n', numel(mdls));
    p('> %s\n\n', strjoin(cellfun(@(s) ['`' s '`'], mdls(:)', 'uni', 0), ' · '));
    p('열거는 `vault_units.m` 하나가 한다. 열려 있는 모델이 달라져도 결과가 같아야 한다.\n');
    p('참조 모델은 여러 곳에서 참조돼도 **한 번만** 문서화하며, `_참조모델\\<모델명>\\` 아래에 둔다.\n\n');
    p('| 종류 | 개수 |\n| --- | --- |\n');
    p('| SubSystem | %d |\n', nSS);
    p('| SubSystem (라이브러리 마스크, 부모 문서에 흡수) | %d |\n', nLib);
    p('| ModelReference | %d |\n', nMR);
    p('| Stateflow Chart | %d |\n', nCH);
    p('| **개별 문서 대상 합계** | **%d** |\n', numel(V));
    p('| ↳ 최상위 `%s` 소속 | %d |\n', model, nRoot);
    p('| ↳ 참조 모델 내부 | %d |\n\n', numel(V) - nRoot);

    % ── 2. 기대 문서 경로 계산 ────────────────────────
    %    폴더 세그먼트는 vault_units 가 이미 계산했다 (vault_base + vault_segs).
    %    감사가 별도 규칙을 갖지 않는 것이 핵심이다.
    U = struct('path',{},'kind',{},'rel',{},'exp',{},'ids',{},'minid',{});
    for k = 1:numel(V)
        v = V(k);
        e = fullfile(vaultDir, v.segs{:}, [strjoin(v.segs,'_') '.md']);
        switch v.kind
            case 'ModelReference'
                % 참조 블록은 내부가 없다. 참조 대상 모델 이름 하나면 「다뤘다」고 본다.
                U(end+1) = mkUnit(v.path, v.kind, v.rel, e, {get_param(v.path,'ModelName')}, 1); %#ok<AGROW>
            case 'Stateflow Chart'
                U(end+1) = mkUnit(v.path, v.kind, v.rel, e, idsOfChart(v.chart), MINIDENT); %#ok<AGROW>
            otherwise
                U(end+1) = mkUnit(v.path, v.kind, v.rel, e, idsOfBlock(v.path), MINIDENT); %#ok<AGROW>
        end
    end

    % ── 3. 대조 ───────────────────────────────────────
    p('## 2. 대조표\n\n');
    p('`문서` = 계산된 기대 경로에 파일이 있고 본문에 전체 경로가 있다. **다른 문서에 있는 것은 인정하지 않는다.**\n');
    p('`해석` = `## 해석` 절이 있고 자리표시자가 아니며 %d자 이상.\n', MINCHARS);
    p('`식별자` = 그 블록 고유 식별자가 **해석 절 본문에** 몇 개 있는가 (기대 %d 이상).\n', MINIDENT);
    p('`설명` = 소절 5개가 채워졌고 단계 %d개 이상 + 용어 사전 링크가 있는가.\n\n', MINSTEPS);
    p('| # | 분석 단위 | 종류 | 문서 | 해석 | 식별자 | 설명 | 기대 파일 |\n');
    p('| --- | --- | --- | --- | --- | --- | --- | --- |\n');

    missDoc = {}; missInt = {}; missId = {}; missExp = {}; warnTerm = {}; used = {};
    for k = 1:numel(U)
        u = U(k);
        txt = '';
        okDoc = false;
        if isfile(u.exp)
            txt = read_utf8(u.exp);   % fileread 는 BMP 밖 문자를 지운다
            okDoc = contains(txt, u.path);
            used{end+1} = lower(u.exp); %#ok<AGROW>
        end

        [body, hasSec] = interpBody(txt);
        okInt = hasSec && ~contains(body, PLACEHOLDER) && numel(body) >= MINCHARS;

        nid = 0;
        for j = 1:numel(u.ids)
            if ~isempty(u.ids{j}) && contains(body, u.ids{j}), nid = nid + 1; end
        end
        need  = min(u.minid, numel(u.ids));
        okId  = okInt && nid >= need;

        % ④ 설명 가능성 — 해석이 있을 때만 의미가 있다.
        [okExp, why, wt] = checkExplain(body, SUBSECS, DICTS, TERMS, MINSTEPS, MINSUBCHARS);
        okExp = okInt && okExp;

        if ~okDoc, missDoc{end+1} = u.rel; end %#ok<AGROW>
        if ~okInt, missInt{end+1} = u.rel; end %#ok<AGROW>
        if okInt && ~okId,  missId{end+1}  = sprintf('%s (%d/%d)', u.rel, nid, need); end %#ok<AGROW>
        if okInt && ~okExp, missExp{end+1} = sprintf('%s — %s', u.rel, strjoin(why, ', ')); end %#ok<AGROW>
        if okExp && ~isempty(wt)
            warnTerm{end+1} = sprintf('%s — %s', u.rel, strjoin(wt, ', ')); %#ok<AGROW>
        end

        p('| %d | `%s` | %s | %s | %s | %s | %s | `%s` |\n', k, u.rel, u.kind, ...
            mark(okDoc), mark(okInt), sprintf('%s %d/%d', mark(okId), nid, need), ...
            mark(okExp), relOf(u.exp, vaultDir));
    end

    % ── 4. 비대조 문서 ────────────────────────────────
    p('\n## 3. 비대조 문서 — 근거로 쓰지 않는다\n\n');
    p('아래는 분석 단위와 1:1 대응하지 않는 문서다. 목차·교차표·규칙 문서이므로 **커버리지 근거가 될 수 없다.**\n');
    p('초판은 이것들을 근거로 인정해서 미분석을 가렸다.\n\n');
    extra = {};
    if isfolder(vaultDir)
        fl = dir(fullfile(vaultDir,'**','*.md'));
        for k = 1:numel(fl)
            f = lower(fullfile(fl(k).folder, fl(k).name));
            if ~any(strcmp(used, f)), extra{end+1} = relOf(fullfile(fl(k).folder, fl(k).name), vaultDir); end %#ok<AGROW>
        end
    end
    if isempty(extra)
        p('없음.\n\n');
    else
        for k = 1:numel(extra), p('- `%s`\n', extra{k}); end
        p('\n');
    end

    % ── 5. 결론 ───────────────────────────────────────
    n = numel(U);
    p('## 4. 결과\n\n');
    p('| 판정 | 결과 |\n| --- | --- |\n');
    p('| ① 문서 1:1 | %s (%d/%d) |\n', tf(isempty(missDoc)), n-numel(missDoc), n);
    p('| ② 해석 기재 | %s (미기재 %d) |\n', tf(isempty(missInt)), numel(missInt));
    p('| ③ 식별자 교집합 | %s (부족 %d) |\n', tf(isempty(missId)), numel(missId));
    p('| ④ 설명 가능성 | %s (미달 %d) |\n\n', tf(isempty(missExp)), numel(missExp));

    dump(p, '① 문서 없음 / 경로 불일치', missDoc);
    dump(p, '② 해석 미기재 (절 없음 포함)', missInt);
    dump(p, '③ 식별자 부족 — 분량은 있으나 그 블록 이야기가 아니다', missId);
    dump(p, '④ 설명 미달 — 읽는 사람이 따라올 수 없다', missExp);

    if ~isempty(warnTerm)
        p('### ⚠️ 용어 미설명 — 경고이며 실패가 아니다\n\n');
        p('본문에 나왔으나 「이 문서에 나온 용어」 소절에 없는 말이다. 설명이 필요 없다고 판단되면 그대로 둔다.\n');
        p('**오탐이 잦으면 이 목록의 `TERMS` 에서 그 항목을 지운다.** 경고가 시끄러우면 감사 전체를 무시하게 된다.\n\n');
        for k = 1:numel(warnTerm), p('- `%s`\n', warnTerm{k}); end
        p('\n');
    end

    if isempty(missDoc) && isempty(missInt) && isempty(missId) && isempty(missExp)
        p('**분석 완료.** 분석 단위 %d개가 모두 1:1 문서화되었고, 해석이 그 블록의 실제 식별자를 다루며, 읽는 사람이 따라올 수 있는 형태다.\n', n);
    else
        p('🔴 **분석은 끝나지 않았다.** 네 판정이 모두 통과해야 「분석 완료」라고 쓸 수 있다.\n\n');
        p('남은 일은 위 목록이 전부다. 목록 순서대로 컨테이너 하나씩 처리한다 (규칙 R14).\n');
    end
end


% ══════════════════════════════════════════════════════
function u = mkUnit(path, kind, rel, expFile, ids, minid)
%MKUNIT  필드 대입으로 만든다.
%   struct('ids',{ids}) 로 쓰면 ids 가 셀 배열일 때 구조체 **배열**로 펼쳐진다.
    u.path  = path;
    u.kind  = kind;
    u.rel   = rel;
    u.exp   = expFile;
    u.ids   = ids;
    u.minid = minid;
end

function s = flat(b, model)
    s = strrep(strrep(b, [model '/'], ''), sprintf('\n'), ' ');
end

function e = expPath(vaultDir, b, model)
%EXPPATH  gen_vault_tree.m 과 **동일한 함수**로 기대 문서 경로를 만든다.
%   규칙을 여기에 옮겨 적지 않는다. 옮겨 적으면 언젠가 갈라지고,
%   갈라지면 감사가 영원히 실패하거나 영원히 통과한다.
    segs = vault_segs(b, model);
    e = fullfile(vaultDir, segs{:}, [strjoin(segs,'_') '.md']);
end

function [body, hasSec] = interpBody(txt)
%INTERPBODY  `## N. 해석` 절 본문만 떼어낸다.
%   절이 없으면 hasSec=false. 초판은 이 경우 검사를 건너뛰어 23개를 놓쳤다.
    body = ''; hasSec = false;
    if isempty(txt), return; end
    i = regexp(txt, '##\s*\d*\.?\s*해석', 'once');
    if isempty(i), return; end
    hasSec = true;
    body = txt(i:end);
    body = regexprep(body, '^##[^\n]*\n', '');
    body = regexprep(body, '\n---[\s\S]*$', '');
    body = strtrim(body);
end

function [ok, why, warnTerms] = checkExplain(body, SUBSECS, DICTS, TERMS, MINSTEPS, MINSUBCHARS)
%CHECKEXPLAIN  판정 ④ — 해석을 읽는 사람이 따라올 수 있는가.
%
%   내용의 「정확성」은 검사하지 않는다. 기계가 볼 수 있는 것은 **형태**뿐이다.
%   그러나 형태만으로도 가장 흔한 실패는 잡힌다: 쓰는 쪽이 이미 아는 것을 생략하는 것.
%
%   why       : 실패 사유 (대조표 아래 목록에 그대로 나간다)
%   warnTerms : 본문에 나왔으나 용어 소절에 없는 말. **경고 전용이다.**

    ok = true; why = {}; warnTerms = {};
    sub = cell(1, numel(SUBSECS));

    % ④-a 소절 5개가 있고 각각 내용이 있는가
    for k = 1:numel(SUBSECS)
        [s, has] = subsecBody(body, SUBSECS{k});
        sub{k} = s;
        if ~has
            ok = false; why{end+1} = sprintf('`%s` 소절 없음', SUBSECS{k}); %#ok<AGROW>
        elseif numel(s) < MINSUBCHARS
            % 뼈대의 HTML 주석은 subsecBody 가 이미 걷어냈다. 즉 「제목만 있는 상태」다.
            ok = false; why{end+1} = sprintf('`%s` 비어 있음', SUBSECS{k}); %#ok<AGROW>
        end
    end
    if ~ok, return; end   % 소절이 없으면 아래 검사는 의미가 없다

    % ④-b 「일어나는 일」에 번호 단계가 몇 개인가
    nStep = numel(regexp(sub{2}, '(^|\n)\s*\d+\.\s', 'start'));
    if nStep < MINSTEPS
        ok = false; why{end+1} = sprintf('단계 %d개 (기대 %d 이상)', nStep, MINSTEPS); %#ok<AGROW>
    end

    % ④-c 용어 소절에 사전 링크가 있는가
    hasDict = false;
    for k = 1:numel(DICTS)
        if contains(sub{4}, DICTS{k}), hasDict = true; break; end
    end
    if ~hasDict
        ok = false; why{end+1} = '용어 사전 링크 없음'; %#ok<AGROW>
    end

    % 경고 — 본문에 나왔는데 용어 소절에서 다루지 않은 말
    prose = [sub{1} ' ' sub{2} ' ' sub{3}];
    for k = 1:numel(TERMS)
        if contains(prose, TERMS{k}) && ~contains(sub{4}, TERMS{k})
            warnTerms{end+1} = TERMS{k}; %#ok<AGROW>
        end
    end
end

function [s, has] = subsecBody(body, title)
%SUBSECBODY  해석 절 안에서 `### ... <제목>` 소절의 본문만 떼어낸다.
%   HTML 주석(뼈대의 안내문)은 내용으로 세지 않는다. 그래야 뼈대가 그대로 통과하지 못한다.
    s = ''; has = false;
    if isempty(body), return; end
    i = regexp(body, ['###[^\n]*' regexptranslate('escape', title)], 'once');
    if isempty(i), return; end
    has = true;
    t = body(i:end);
    t = regexprep(t, '^###[^\n]*\n', '');    % 소절 제목 줄 제거
    j = regexp(t, '\n\s*###', 'once');       % 다음 소절 전까지
    if ~isempty(j), t = t(1:j-1); end
    t = regexprep(t, '<!--[\s\S]*?-->', ''); % 뼈대 안내 주석 제거
    s = strtrim(t);
end

function ids = idsOfBlock(b)
%IDSOFBLOCK  그 SubSystem 고유의 식별자를 모은다.
%   해석 문장이 이 블록을 실제로 다뤘다면 이 이름들이 나올 수밖에 없다.
    ids = {};
    kid = find_system(b,'SearchDepth',1,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants);
    for j = 1:numel(kid)
        if strcmp(kid{j}, b), continue; end
        nm = strrep(strrep(kid{j},[b '/'],''), sprintf('\n'), ' ');
        if numel(nm) >= 3, ids{end+1} = nm; end %#ok<AGROW>
    end
    for bt = {'DataStoreRead','DataStoreWrite'}
        L = find_system(b,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants, ...
                        'BlockType',bt{1});
        for j = 1:numel(L), ids{end+1} = get_param(L{j},'DataStoreName'); end %#ok<AGROW>
    end
    for bt = {'Goto','From'}
        L = find_system(b,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants, ...
                        'BlockType',bt{1});
        for j = 1:numel(L), ids{end+1} = get_param(L{j},'GotoTag'); end %#ok<AGROW>
    end
    ids = unique(ids(~cellfun(@isempty, ids)));
end

function ids = idsOfChart(c)
%IDSOFCHART  그 Chart 고유의 식별자 — State · Data · Event 이름.
    ids = {};
    for cls = {'Stateflow.State','Stateflow.Data','Stateflow.Event'}
        o = c.find('-isa', cls{1});
        for j = 1:numel(o)
            nm = char(o(j).Name);
            if numel(nm) >= 3, ids{end+1} = nm; end %#ok<AGROW>
        end
    end
    ids = unique(ids(~cellfun(@isempty, ids)));
end

function r = relOf(f, root)
    r = strrep(f, [root filesep], '');
    r = strrep(r, '\', '/');
end

function dump(p, title, list)
    if isempty(list), return; end
    p('**%s — %d건**\n\n', title, numel(list));
    for k = 1:numel(list), p('- `%s`\n', list{k}); end
    p('\n');
end

function s = mark(b)
    if b, s = 'O'; else, s = '**X**'; end
end

function s = tf(b)
    if b, s = '통과'; else, s = '**실패**'; end
end

function s = safeName(s)
    s = strtrim(strrep(s, sprintf('\n'), ' '));
    s = regexprep(s, '[<>:"/\\?*]', '_');
    s = regexprep(s, '\s+', '_');
end
