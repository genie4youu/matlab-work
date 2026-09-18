function gen_vault_tree(model, vaultRoot)
%GEN_VAULT_TREE  모델 계층을 그대로 볼트 폴더 트리로 만들고, 컨테이너마다 사실 문서를 쓴다.
%
%   규칙 R10 (2026-08-04 사용자 지시):
%     "하위 subsystem 이나 stateflow 차트가 있으면 꼭 하위폴더를 만들어서 분석한다"
%
%   생성 대상 = SubSystem + ModelReference (Stateflow Chart 는 gen_vault_charts)
%   제외      = Simulink 라이브러리 마스크 블록 (부모 문서에 표로 흡수)
%
%   문서에는 API 로 읽은 사실만 넣는다. 해석은 사람이 나중에 덧붙인다.
%   파일명은 경로를 평탄화한다 — 폴더명만으로는 위키링크가 충돌한다.
%
%   2026-08-05 (R19) — 열거를 vault_units.m 하나에 맡긴다
%   ──────────────────────────────────────────────────
%   전에는 이 파일이 직접 find_system 으로 열거했고, audit_coverage 도 따로
%   열거했다. 그래서 갈라졌다: 이 파일은 최상위 모델만 봤고 **참조 모델 내부
%   컨테이너 27개는 아무도 문서로 만들지 않았다.** 이제 열거는 vault_units 가,
%   폴더명은 vault_segs 가, 놓이는 위치는 vault_base 가 각각 하나씩 정한다.

    LIBMASK = {'Compare To Constant','Compare To Zero','Detect Change','Detect Increase'};

    % 날짜·위키링크 접두는 세션 맥락에서 받는다. 문자열로 박지 않는다 —
    % 박아두면 새 날짜 폴더의 문서가 옛 날짜를 가리키고, 오류는 나지 않는다.
    ctx = vault_ctx(model);

    U = vault_units(model);
    U = U(~strcmp({U.kind}, 'Stateflow Chart'));   % Chart 는 gen_vault_charts 가 쓴다

    fprintf('컨테이너 %d개 (라이브러리 마스크 제외)\n', numel(U));
    made = 0;
    for k = 1:numel(U)
        u = U(k);
        folder = fullfile(vaultRoot, u.segs{:});
        if ~isfolder(folder), mkdir(folder); end
        fname = [strjoin(u.segs, '_') '.md'];
        writeDoc(fullfile(folder, fname), u.path, u.kind, u.model, model, LIBMASK, ctx);
        made = made + 1;
    end
    fprintf('문서 %d개 생성 → %s\n', made, vaultRoot);
end


function writeDoc(path, b, kind, model, rootModel, LIBMASK, ctx)
%WRITEDOC  model = 이 블록이 속한 모델. rootModel = 최상위 모델.
%   둘이 다르면 참조 모델 내부다 (R19).
    % 🔴 기존 해석을 먼저 읽어둔다. 재생성이 사람이 쓴 해석을 지우면 안 된다.
    %    이 함수는 문서를 통째로 새로 쓰므로, 보존하지 않으면 모델이 하나만 바뀌어도
    %    써둔 해석 전체가 날아간다. 그리고 그 사실은 다음 커버리지 감사까지 드러나지 않는다.
    keep = read_interp(path);

    fid = fopen(path,'w','n','UTF-8');
    oc  = onCleanup(@() fclose(fid));
    p   = @(varargin) fprintf(fid, varargin{:});

    parts = strsplit(strrep(b, newline, ' '), '/');
    leaf  = parts{end};
    nAll  = numel(find_system(b,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants)) - 1;

    p('---\n분류: work\n세션: "%s"\n대상: %s\n작성일: %s\n---\n\n', ctx.date, b, ctx.iso);
    p('# `%s`\n\n', leaf);
    if ~strcmp(model, rootModel)
        p('> 참조 모델 `%s` 의 내부다 (규칙 R19). 이 모델을 가리키는 ModelReference 블록 문서는 계층 트리 쪽에 있다.\n', model);
    end
    p('> 모델 경로 `%s`\n', b);
    p('> **기계 추출 문서.** 값은 전부 `get_param` 원본이며 추론이 없다. 규칙 → [[%s/_분석규칙|분석 규칙]]\n\n', ctx.wiki);

    p('## 1. 기본\n\n| 항목 | 값 |\n| --- | --- |\n');
    p('| 종류 | `%s` |\n', kind);
    p('| 하위 블록 | %d |\n', nAll);
    if strcmp(kind,'ModelReference')
        p('| 참조 모델 | `%s` |\n', get_param(b,'ModelName'));
    else
        try
            rs = get_param(b,'ReferencedSubsystem');
            if ~isempty(rs), p('| Subsystem Reference | `%s` |\n', rs); end
        catch
        end
    end
    ph = get_param(b,'PortHandles');
    p('| 입력 포트 | %d |\n| 출력 포트 | %d |\n', numel(ph.Inport), numel(ph.Outport));
    if ~isempty(ph.Enable),  p('| Enable 포트 | 있음 |\n');  end
    if ~isempty(ph.Trigger), p('| Trigger 포트 | 있음 |\n'); end
    cm = ''; try, cm = get_param(b,'Commented'); catch, end
    if ~isempty(cm) && ~strcmp(cm,'off')
        p('| **주석 처리** | **`%s`** — 모델에 존재하나 실행되지 않는다 |\n', cm);
    end
    % 이 블록을 감싸는 영역 주석. 화면에서 사람이 읽는 이름이 이쪽인 경우가 있다 (R22).
    ar = enclosingArea(b);
    if ~isempty(ar)
        p('| 감싸는 영역 이름 | `%s` |\n', ar);
        if ~strcmp(ar, leaf)
            p('| ⚠️ 이름 불일치 | 블록은 `%s`, 화면의 영역 제목은 `%s`. **화면에서 읽히는 이름은 영역 쪽이다.** 폴더·파일명은 블록 이름을 따른다 (R13) |\n', leaf, ar);
        end
    end
    p('\n');

    if strcmp(kind,'ModelReference')
        % 참조 블록은 내부가 없다. 그래도 해석 절은 반드시 만든다 —
        % 절이 없으면 audit_coverage 가 「해석 미기재」로 잡는다 (실제로 10건 잡혔다).
        p('참조 대상 모델의 내부는 그 모델의 문서를 본다.\n\n');
        p('## 3. 포트 배선\n\n| 포트 | 방향 | 연결 |\n| --- | --- | --- |\n');
        par = get_param(b,'Parent');
        for k = 1:numel(ph.Inport),  p('| in %d | ← | %s |\n',  k, srcPort(ph.Inport(k),  par)); end
        for k = 1:numel(ph.Outport), p('| out %d | → | %s |\n', k, dstPort(ph.Outport(k), par)); end
        p('\n');
        emit_interp(p, keep, 4);   % 해석 절 구조는 emit_interp.m 하나가 정한다 (R17)
        p('---\n\n[[%s/_안내|↑ 서브시스템 지도]]\n', ctx.wiki);
        return
    end

    % ── 직속 하위 컨테이너 ────────────────────────────
    kid = find_system(b,'SearchDepth',1,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants);
    kc = {}; klib = {};
    for j = 1:numel(kid)
        if strcmp(kid{j}, b), continue; end
        t = ''; try, t = get_param(kid{j},'BlockType'); catch, end
        if ~any(strcmp(t,{'SubSystem','ModelReference'})), continue; end
        mt = ''; try, mt = get_param(kid{j},'MaskType'); catch, end
        if any(strcmp(mt, LIBMASK)), klib{end+1} = kid{j}; else, kc{end+1} = kid{j}; end %#ok<AGROW>
    end
    p('## 2. 직속 하위 컨테이너 (%d)\n\n', numel(kc));
    if isempty(kc)
        p('없음. 이 블록이 말단이다.\n\n');
    else
        p('| 이름 | 종류 | 하위 블록 | 주석 처리 |\n| --- | --- | --- | --- |\n');
        for j = 1:numel(kc)
            nm = strrep(strrep(kc{j},[b '/'],''), sprintf('\n'),' ');
            n2 = numel(find_system(kc{j},'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants)) - 1;
            p('| `%s` | %s | %d | %s |\n', nm, get_param(kc{j},'BlockType'), n2, cmt(kc{j}));
        end
        p('\n각각 하위 폴더에 문서가 있다 (규칙 R10).\n');
        p('「주석 처리」가 **예**인 블록은 모델에 존재하나 실행되지 않는다. 없는 것이 아니므로 문서화 대상이다 (규칙 R21).\n\n');
    end

    % ── 영역 주석 ─────────────────────────────────────
    %    캔버스에서 블록들을 감싸는 이름표다. 블록이 아니라서 find_system 의
    %    블록 열거에는 나오지 않지만, **사람이 화면에서 읽는 기능 이름**은 이쪽인 경우가 많다.
    %    2026-08-05: 사용자가 `Set_PC_VC_Interrupt_Fault` 를 서브시스템으로 지목했는데
    %    실제로는 이 area annotation 이었고, 볼트 어디에도 그 이름이 없었다 (규칙 R22).
    emitAreas(p, b);

    if ~isempty(klib)
        p('### 2.1 라이브러리 마스크 블록 (%d) — 폴더를 만들지 않는다\n\n', numel(klib));
        p('Simulink 표준 블록이므로 별도 폴더 없이 여기에 파라미터를 적는다 (규칙 R10). 전체 경로를 함께 적어 커버리지 검사가 인식하게 한다.\n\n');
        p('| 전체 경로 | MaskType | 파라미터 |\n| --- | --- | --- |\n');
        for j = 1:numel(klib)
            nm = strrep(strrep(klib{j},[model '/'],''), sprintf('\n'),' ');
            mt = get_param(klib{j},'MaskType');
            kv = '';
            try
                mn = get_param(klib{j},'MaskNames'); mv = get_param(klib{j},'MaskValues');
                pr = {};
                for q = 1:numel(mn)
                    if any(strcmp(mn{q},{'relop','const','vinit','OutDataTypeStr'}))
                        pr{end+1} = sprintf('`%s`=`%s`', mn{q}, mv{q}); %#ok<AGROW>
                    end
                end
                kv = strjoin(pr, ' / ');
            catch
            end
            p('| `%s` | %s | %s |\n', nm, mt, kv);
        end
        p('\n');
    end

    % ── 직속 블록 전수 ────────────────────────────────
    p('## 3. 직속 블록 전수\n\n| 블록 | 유형 | 값·연산 | 입력 소스 | 주석 처리 |\n| --- | --- | --- | --- | --- |\n');
    for j = 1:numel(kid)
        if strcmp(kid{j}, b), continue; end
        if numel(strfind(kid{j},'/')) ~= numel(strfind(b,'/'))+1, continue; end
        t = ''; try, t = get_param(kid{j},'BlockType'); catch, end
        p('| `%s` | `%s` | %s | %s | %s |\n', ...
            strrep(strrep(kid{j},[b '/'],''),sprintf('\n'),' '), t, valOf(kid{j},t), srcOf(kid{j},b), cmt(kid{j}));
    end
    p('\n');

    % ── Data Store ────────────────────────────────────
    rd = find_system(b,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants,'BlockType','DataStoreRead');
    wr = find_system(b,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants,'BlockType','DataStoreWrite');
    p('## 4. Data Store 접근 (하위 포함)\n\n');
    p('| 방향 | 스토어 | 블록 |\n| --- | --- | --- |\n');
    for j = 1:numel(wr)
        p('| **write** | `%s` | `%s` |\n', get_param(wr{j},'DataStoreName'), ...
            strrep(strrep(wr{j},[b '/'],''),sprintf('\n'),' '));
    end
    for j = 1:numel(rd)
        p('| read | `%s` | `%s` |\n', get_param(rd{j},'DataStoreName'), ...
            strrep(strrep(rd{j},[b '/'],''),sprintf('\n'),' '));
    end
    if isempty(rd) && isempty(wr), p('| — | 없음 | |\n'); end
    p('\n');

    emit_interp(p, keep, 5);   % 해석 절 구조는 emit_interp.m 하나가 정한다 (R17)
    p('---\n\n[[%s/_안내|↑ 서브시스템 지도]]\n', ctx.wiki);
end


function s = cmt(b)
%CMT  블록의 주석 처리 상태. 'off' 가 아니면 모델에 있으나 실행되지 않는 블록이다.
    s = '';
    try, s = get_param(b,'Commented'); catch, end
    if isempty(s) || strcmp(s,'off'), s = '-'; else, s = ['**예** (`' s '`)']; end
end

function nm = enclosingArea(b)
%ENCLOSINGAREA  이 블록을 화면에서 감싸고 있는 area annotation 의 이름.
%
%   왜 필요한가 (2026-08-05)
%   ──────────────────────
%   `M1/Fault_Management` 의 네 영역 중 셋은 영역 이름과 안의 블록 이름이 같다.
%   그런데 `Set_PC_VC_Interrupt_Fault` 영역 안의 블록은 `Set_PC_Interrupt_Fault` 다.
%   사용자는 화면에서 영역 제목을 읽으므로 **블록 이름이 틀렸다고 본다.**
%   둘 다 모델에 적혀 있는 이름이므로, 문서는 둘을 함께 적어야 한다.
%
%   판정은 좌표 포함 관계로 한다. Position = [left top right bottom].
    nm = '';
    par = ''; try, par = get_param(b,'Parent'); catch, end
    if isempty(par), return; end
    bp = []; try, bp = get_param(b,'Position'); catch, end
    if numel(bp) ~= 4, return; end

    a = [];
    try
        a = find_system(par,'SearchDepth',1,'LookUnderMasks','all','FollowLinks','on', ...
                        'IncludeCommented','on','MatchFilter',@Simulink.match.allVariants,'FindAll','on','Type','annotation');
    catch
        return
    end
    bestArea = inf;
    for j = 1:numel(a)
        ty = ''; try, ty = get_param(a(j),'AnnotationType'); catch, end
        if ~strcmp(ty,'area_annotation'), continue; end
        ap = []; try, ap = get_param(a(j),'Position'); catch, end
        if numel(ap) ~= 4, continue; end
        if ~(ap(1) <= bp(1) && ap(2) <= bp(2) && ap(3) >= bp(3) && ap(4) >= bp(4)), continue; end
        n2 = ''; try, n2 = get_param(a(j),'Name'); catch, end
        n2 = strtrim(regexprep(strrep(strrep(n2,sprintf('\r'),' '),sprintf('\n'),' '), '\s+',' '));
        if isempty(n2), continue; end
        % 여러 영역이 겹쳐 감쌀 수 있다. **가장 작은** 영역이 그 블록의 것이다.
        sz = (ap(3)-ap(1)) * (ap(4)-ap(2));
        if sz < bestArea, bestArea = sz; nm = n2; end
    end
end

function emitAreas(p, b)
%EMITAREAS  이 층의 area annotation (블록을 감싸는 이름표) 을 적는다.
%   블록이 아니라서 find_system 의 블록 열거에는 나오지 않는다.
    a = [];
    try
        a = find_system(b,'SearchDepth',1,'LookUnderMasks','all','FollowLinks','on', ...
                        'IncludeCommented','on','MatchFilter',@Simulink.match.allVariants,'FindAll','on','Type','annotation');
    catch
    end
    names = {};
    for j = 1:numel(a)
        ty = ''; try, ty = get_param(a(j),'AnnotationType'); catch, end
        if ~strcmp(ty,'area_annotation'), continue; end
        nm = ''; try, nm = get_param(a(j),'Name'); catch, end
        nm = strtrim(regexprep(strrep(strrep(nm, sprintf('\r'), ' '), sprintf('\n'), ' '), '\s+', ' '));
        if isempty(nm), continue; end          % 이름 없는 영역은 적을 것이 없다
        names{end+1} = nm; %#ok<AGROW>
    end
    if isempty(names), return; end
    p('### 2.2 영역 주석 (%d) — 캔버스에서 이 층을 나누는 이름표\n\n', numel(names));
    p('블록이 아니므로 폴더를 만들지 않는다. 다만 **화면에서 읽히는 기능 이름이 이쪽인 경우가 있어** 반드시 적는다 (규칙 R22).\n\n');
    p('| 영역 이름 |\n| --- |\n');
    for j = 1:numel(names), p('| `%s` |\n', names{j}); end
    p('\n');
end

function s = valOf(b, bt)
    s = '';
    try
        switch bt
            case 'Constant',           s = ['`' get_param(b,'Value') '`'];
            case 'Gain',               s = ['gain `' get_param(b,'Gain') '`'];
            case 'RelationalOperator', s = ['`' get_param(b,'Operator') '`'];
            case 'Logic',              s = ['`' get_param(b,'Operator') '` (' get_param(b,'Inputs') '입력)'];
            case 'Switch',             s = ['`' get_param(b,'Criteria') '` 임계 `' get_param(b,'Threshold') '`'];
            case 'UnitDelay',          s = ['ic `' get_param(b,'InitialCondition') '`'];
            case 'Memory',             s = ['ic `' get_param(b,'InitialCondition') '`'];
            case 'DataStoreRead',      s = ['read `' get_param(b,'DataStoreName') '`'];
            case 'DataStoreWrite',     s = ['**write** `' get_param(b,'DataStoreName') '`'];
            case 'Goto',               s = ['tag `' get_param(b,'GotoTag') '`'];
            case 'From',               s = ['tag `' get_param(b,'GotoTag') '`'];
            case 'S-Function'
                fn = get_param(b,'FunctionName');
                if strcmp(fn,'sfix_bitop')
                    s = sprintf('`%s` %s 마스크 `%s`', fn, get_param(b,'logicop'), get_param(b,'BitMask'));
                else, s = ['`' fn '`']; end
            case 'ArithShift'
                n = str2double(get_param(b,'BitShiftNumber'));
                if n>0, s = sprintf('`>> %d`', n); elseif n<0, s = sprintf('`<< %d`', -n); else, s='이동 없음'; end
            case 'ModelReference',     s = ['-> `' get_param(b,'ModelName') '`'];
            case 'DataTypeConversion', s = ['-> `' get_param(b,'OutDataTypeStr') '`'];
            case 'Sum',                s = ['부호 `' get_param(b,'Inputs') '`'];
            case 'Mux',                s = ['입력 ' get_param(b,'Inputs')];
            case 'Demux',              s = ['출력 ' get_param(b,'Outputs')];
            case 'Inport',             s = ['`' get_param(b,'OutDataTypeStr') '`'];
            case 'SubSystem'
                rs=''; try, rs = get_param(b,'ReferencedSubsystem'); catch, end
                if ~isempty(rs), s = ['ref -> `' rs '`']; end
        end
    catch
    end
    s = strrep(s,'|','\|');
end

function s = srcOf(b, root)
    s = '';
    try
        ph = get_param(b,'PortHandles');
        if isempty(ph.Inport), return; end
        parts = {};
        for k = 1:numel(ph.Inport)
            l = get_param(ph.Inport(k),'Line');
            if l <= 0, parts{end+1} = '-'; continue; end %#ok<AGROW>
            sp = get_param(l,'SrcPortHandle');
            if sp <= 0, parts{end+1} = '-'; continue; end %#ok<AGROW>
            parts{end+1} = strrep(strrep(get_param(sp,'Parent'),[root '/'],''),sprintf('\n'),' '); %#ok<AGROW>
        end
        s = strjoin(parts,' / ');
    catch
    end
    s = strrep(s,'|','\|');
end

function s = srcPort(h, root)
    s = '(미연결)';
    try
        l = get_param(h,'Line'); if l <= 0, return; end
        sp = get_param(l,'SrcPortHandle'); if sp <= 0, return; end
        sb = get_param(sp,'Parent'); bt = get_param(sb,'BlockType');
        nm = strrep(strrep(sb,[root '/'],''), sprintf('\n'),' ');
        if strcmp(bt,'DataStoreRead'), s = sprintf('`%s` read `%s`', nm, get_param(sb,'DataStoreName'));
        elseif strcmp(bt,'Constant'),  s = sprintf('`%s` = `%s`', nm, get_param(sb,'Value'));
        else,                          s = sprintf('`%s` [%s]', nm, bt); end
    catch
    end
end

function s = dstPort(h, root)
    s = '(미연결)';
    try
        l = get_param(h,'Line'); if l <= 0, return; end
        dp = get_param(l,'DstPortHandle'); if isempty(dp) || dp(1) <= 0, return; end
        parts = {};
        for k = 1:numel(dp)
            db = get_param(dp(k),'Parent'); bt = get_param(db,'BlockType');
            nm = strrep(strrep(db,[root '/'],''), sprintf('\n'),' ');
            if strcmp(bt,'DataStoreWrite')
                parts{end+1} = sprintf('`%s` **write** `%s`', nm, get_param(db,'DataStoreName')); %#ok<AGROW>
            else
                parts{end+1} = sprintf('`%s` [%s]', nm, bt); %#ok<AGROW>
            end
        end
        s = strjoin(parts, ' / ');
    catch
    end
end

function s = safeName(s)
    s = strtrim(strrep(s, sprintf('\n'), ' '));
    s = regexprep(s, '[<>:"/\\?*]', '_');
    s = regexprep(s, '\s+', '_');
end
