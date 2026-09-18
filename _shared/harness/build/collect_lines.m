function L = collect_lines(root)
%COLLECT_LINES  Simulink 신호선과 **Chart 경계 매핑**을 수집한다.
%
%   L = collect_lines('ExampleModel')
%
%   왜 필요한가 (2026-09-08, 에이전트 3종이 각자 지적)
%   ────────────────────────────────────────────────
%   지금까지의 덤프는 **Stateflow 안쪽만** 담았다. 그래서 모델 사이가 끊긴다.
%   `graph-analyst` 는 `Fault_State_Change`(Example_Main_SF 출력) → `State_Change_Fault`
%   (Example_Fault 입력) 의 연결을 **비트마스크 일치(0x1000)로 추정**할 수밖에
%   없었고, 그것을 「미확인」으로 남겼다.
%
%   실측으로 드러난 두 사실이 이 함수의 근거다:
%     ① **Chart 포트 수 = Data 의 Scope 수**다 (Example_Main_SF/SF: In 17=17, Out 11=11).
%        포트 순서와 Data 순서가 대응하므로 **포트 ↔ Chart 안 이름**을 이을 수 있다.
%     ② `Fault_State_Change` 라는 **이름의 라인·Goto 는 0개**다.
%        이름으로는 못 잇는다 — 포트를 따라가야 한다.
%
%   반환 구조
%   ────────
%     L.lines(k)      src/dst 블록·포트, 신호 이름
%     L.gotos(k)      Goto 태그 ↔ From 블록들 (가상 연결)
%     L.chartPorts(k) Chart 블록 포트 ↔ Chart Data 이름   ← ①의 산물
%     L.refPorts(k)   ModelReference 포트 ↔ 참조 모델의 Inport/Outport
%     L.counts        각 항목 수
%     L.warnings      매핑이 어긋난 곳 — **조용히 넘기지 않는다**
%
%   🔴 포트 수와 Data 수가 안 맞으면 매핑을 **만들지 않고** 경고에 남긴다.
%      순서 가정이 깨진 채 이름을 붙이면 **틀린 연결이 그럴듯하게 생긴다.**

    if nargin < 1 || isempty(root)
        error('collect_lines:noArg', '루트 모델 이름이 필요하다.');
    end
    root = char(root);

    FF = {'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on', ...
          'MatchFilter',@Simulink.match.allVariants};   % 침묵 제외 4종 (R3)

    if ~bdIsLoaded(root), load_system(root); end
    mdls = find_mdlrefs(root);
    for i = 1:numel(mdls)
        if ~bdIsLoaded(mdls{i}), load_system(mdls{i}); end
    end

    L = struct();
    L.root      = root;
    L.collected = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
    L.models    = reshape(mdls,1,[]);
    L.warnings  = {};

    fprintf('\n──────── 신호선 수집 (collect_lines) ────────\n');

    % ── A. 신호선 ─────────────────────────────────────
    L.lines = struct('model',{},'name',{},'src',{},'srcPort',{},'dst',{},'dstPort',{});
    nUnnamed = 0;
    for m = 1:numel(mdls)
        M = mdls{m};
        lh = find_system(M, 'FindAll','on', FF{:}, 'Type','line');
        for i = 1:numel(lh)
            l = lh(i);
            sb = geth(l,'SrcBlockHandle');
            db = geth(l,'DstBlockHandle');
            if sb < 0 || db < 0, continue; end      % 분기선의 중간 세그먼트
            e = struct();
            e.model   = M;
            e.name    = gets(l,'Name');
            if isempty(e.name), nUnnamed = nUnnamed + 1; end
            e.src     = rel(getfullname(sb), M);
            e.srcPort = portNum(geth(l,'SrcPortHandle'));
            e.dst     = rel(getfullname(db), M);
            e.dstPort = portNum(geth(l,'DstPortHandle'));
            L.lines(end+1) = e;
        end
    end

    % ── B. Goto / From ────────────────────────────────
    %    이름 있는 신호가 아니라 **태그**로 이어지는 가상 연결이다.
    %    실측: ExampleModel 29/31 · Debounce8 26/40 · Control_Fault 18/24
    L.gotos = struct('model',{},'tag',{},'goto',{},'froms',{});
    for m = 1:numel(mdls)
        M = mdls{m};
        gb = find_system(M, FF{:}, 'BlockType','Goto');
        for i = 1:numel(gb)
            tag = gets(gb{i}, 'GotoTag');
            fb  = find_system(M, FF{:}, 'BlockType','From', 'GotoTag', tag);
            e = struct();
            e.model = M;
            e.tag   = tag;
            e.goto  = rel(gb{i}, M);
            e.froms = cellfun(@(x) rel(x,M), reshape(fb,1,[]), 'uni', 0);
            if isempty(fb)
                L.warnings{end+1} = sprintf('%s: Goto 태그 %s 를 받는 From 이 없다', M, tag);
            end
            L.gotos(end+1) = e;
        end
    end

    % ── B2. Data Store — 모델 사이를 잇는 진짜 통로 ──
    %    🔴 2026-09-08 실측으로 드러난 것: **모델 간 연결이 신호선이 아니다.**
    %       `Example_Main_SF/SF` 출력 `Fault_State_Change` 를 따라가면
    %       `M1/Main_SF/Data Store Write1` 에서 라인이 끝난다.
    %       Goto/From 만 넣고 Data Store 를 빼면 체인이 거기서 끊긴다 —
    %       `graph-analyst` 가 비트마스크로 추정할 수밖에 없었던 이유가 이것이다.
    %       (`collect_types` 가 센 전역신호 84개가 이 저장소들이다)
    L.dataStores = struct('name',{},'writes',{},'reads',{});
    dsMapW = containers.Map('KeyType','char','ValueType','any');
    dsMapR = containers.Map('KeyType','char','ValueType','any');
    for m = 1:numel(mdls)
        M = mdls{m};
        for kind = {'DataStoreWrite','DataStoreRead'}
            bs = find_system(M, FF{:}, 'BlockType', kind{1});
            for i = 1:numel(bs)
                nm = gets(bs{i}, 'DataStoreName');
                if isempty(nm), continue; end
                entry = sprintf('%s :: %s', M, rel(bs{i}, M));
                if strcmp(kind{1},'DataStoreWrite')
                    if isKey(dsMapW,nm), dsMapW(nm) = [dsMapW(nm), {entry}]; else, dsMapW(nm) = {entry}; end
                else
                    if isKey(dsMapR,nm), dsMapR(nm) = [dsMapR(nm), {entry}]; else, dsMapR(nm) = {entry}; end
                end
            end
        end
    end
    allDS = unique([keys(dsMapW), keys(dsMapR)]);
    for i = 1:numel(allDS)
        nm = allDS{i};
        e = struct();
        e.name   = nm;
        if isKey(dsMapW,nm), e.writes = dsMapW(nm); else, e.writes = {}; end
        if isKey(dsMapR,nm), e.reads  = dsMapR(nm); else, e.reads  = {}; end
        % 「쓰기만 있고 읽기가 없다」/「읽기만 있고 쓰기가 없다」는 그 자체가 정보다.
        if isempty(e.reads)
            L.warnings{end+1} = sprintf('Data Store %s: 쓰기만 있고 읽는 곳이 없다', nm);
        elseif isempty(e.writes)
            L.warnings{end+1} = sprintf('Data Store %s: 읽기만 있고 쓰는 곳이 없다 (모델 밖에서 쓰는가)', nm);
        end
        L.dataStores(end+1) = e;
    end

    % ── C. Chart 포트 ↔ Chart Data ────────────────────
    %    🔴 이 매핑이 이 함수의 핵심이다. 이것 없이는 Chart 안 이름과
    %       바깥 배선이 이어지지 않는다.
    L.chartPorts = struct('model',{},'block',{},'chart',{},'direction',{}, ...
                          'portNum',{},'dataName',{},'dataType',{});
    r = sfroot;
    for m = 1:numel(mdls)
        M = mdls{m};
        cb = find_system(M, FF{:}, 'BlockType','SubSystem', 'SFBlockType','Chart');
        for i = 1:numel(cb)
            blk = cb{i};
            ch = r.find('-isa','Stateflow.Chart','-and','Path', strrep(blk, newline, ' '));
            if isempty(ch)
                % 경로에 개행이 있으면 Path 매칭이 어긋난다. 이름으로 한 번 더 찾는다.
                ch = r.find('-isa','Stateflow.Chart','-and','Name', gets(blk,'Name'));
            end
            if isempty(ch)
                L.warnings{end+1} = sprintf('%s: Chart 블록 %s 에 대응하는 Stateflow.Chart 를 못 찾았다', ...
                    M, rel(blk,M));
                continue
            end
            c = ch(1);
            dd = c.find('-isa','Stateflow.Data');
            inD = {}; outD = {}; inT = {}; outT = {};
            for k = 1:numel(dd)
                % 🔴 `find` 는 Chart **전체**의 Data 를 준다 — 그래픽 함수·MATLAB 함수의
                %    **인자까지** 포함한다. 함수 인자도 Scope 가 Input/Output 이라
                %    그냥 세면 포트 수와 어긋난다.
                %    실측(2026-09-08): PTP 의 Data 34개 중 **16개가 EMFunction 인자**여서
                %    「포트 5개인데 Input Data 16개」로 보였다. Chart 직속만 세면
                %    7개 Chart 전부 포트 수와 일치한다.
                isChartLevel = false;
                try, isChartLevel = isa(dd(k).getParent, 'Stateflow.Chart'); catch, end
                if ~isChartLevel, continue; end
                sc = ''; try, sc = char(dd(k).Scope); catch, end
                nm = ''; try, nm = char(dd(k).Name);  catch, end
                ty = ''; try, ty = char(dd(k).DataType); catch, end
                if strcmpi(sc,'Input'),  inD{end+1}=nm;  inT{end+1}=ty;  end %#ok<AGROW>
                if strcmpi(sc,'Output'), outD{end+1}=nm; outT{end+1}=ty; end %#ok<AGROW>
            end
            ph = get_param(blk,'PortHandles');

            % 🔴 수가 안 맞으면 매핑을 만들지 않는다.
            %    순서 가정이 깨진 채 이름을 붙이면 틀린 연결이 그럴듯하게 생긴다.
            if numel(ph.Inport) ~= numel(inD)
                L.warnings{end+1} = sprintf(['%s: %s 입력 포트 %d개인데 Scope=Input Data 는 %d개다 — ' ...
                    '매핑을 만들지 않는다'], M, rel(blk,M), numel(ph.Inport), numel(inD));
            else
                for k = 1:numel(inD)
                    L.chartPorts(end+1) = mkCP(M, rel(blk,M), char(c.Path), 'Input', k, inD{k}, inT{k});
                end
            end
            if numel(ph.Outport) ~= numel(outD)
                L.warnings{end+1} = sprintf(['%s: %s 출력 포트 %d개인데 Scope=Output Data 는 %d개다 — ' ...
                    '매핑을 만들지 않는다'], M, rel(blk,M), numel(ph.Outport), numel(outD));
            else
                for k = 1:numel(outD)
                    L.chartPorts(end+1) = mkCP(M, rel(blk,M), char(c.Path), 'Output', k, outD{k}, outT{k});
                end
            end
        end
    end

    % ── D. ModelReference 포트 ↔ 참조 모델 경계 ───────
    %    Chart 는 참조 모델 안에 있으므로 이 단계가 있어야 최상위에서 이어진다.
    L.refPorts = struct('model',{},'block',{},'refModel',{},'direction',{}, ...
                        'portNum',{},'portBlock',{});
    for m = 1:numel(mdls)
        M = mdls{m};
        rb = find_system(M, FF{:}, 'BlockType','ModelReference');
        for i = 1:numel(rb)
            refM = gets(rb{i}, 'ModelNameDialog');
            if isempty(refM), refM = gets(rb{i}, 'ModelName'); end
            refM = regexprep(refM, '\.slx$|\.mdl$', '');
            if isempty(refM) || ~bdIsLoaded(refM), continue; end
            for dir = {'Inport','Outport'}
                pb = find_system(refM, 'SearchDepth',1, FF{:}, 'BlockType', dir{1});
                for k = 1:numel(pb)
                    e = struct();
                    e.model     = M;
                    e.block     = rel(rb{i}, M);
                    e.refModel  = refM;
                    e.direction = dir{1};
                    e.portNum   = str2double(gets(pb{k},'Port'));
                    e.portBlock = gets(pb{k},'Name');
                    L.refPorts(end+1) = e;
                end
            end
        end
    end

    L.counts = struct('lines', numel(L.lines), 'unnamedLines', nUnnamed, ...
                      'gotos', numel(L.gotos), 'dataStores', numel(L.dataStores), ...
                      'chartPorts', numel(L.chartPorts), ...
                      'refPorts', numel(L.refPorts), 'warnings', numel(L.warnings));

    fprintf('  모델 %d · 라인 %d(이름없음 %d) · Goto %d · DataStore %d · Chart포트 %d · 참조포트 %d\n', ...
        numel(mdls), L.counts.lines, nUnnamed, L.counts.gotos, L.counts.dataStores, ...
        L.counts.chartPorts, L.counts.refPorts);
    if L.counts.warnings > 0
        fprintf('  ⚠ 경고 %d건\n', L.counts.warnings);
        for i = 1:min(6, numel(L.warnings)), fprintf('     %s\n', L.warnings{i}); end
        if numel(L.warnings) > 6, fprintf('     ... 외 %d건\n', numel(L.warnings)-6); end
    end
end


% ══════════════════════════════════════════════════════

function e = mkCP(M, blk, chartPath, dir, num, name, ty)
    e = struct('model', M, 'block', blk, 'chart', chartPath, ...
               'direction', dir, 'portNum', num, 'dataName', name, 'dataType', ty);
end

function v = geth(h, name)
    v = -1;
    try, v = get_param(h, name); catch, end
    if ~isnumeric(v) || isempty(v), v = -1; end
    v = double(v(1));
end

function s = gets(h, name)
    s = '';
    try
        s = get_param(h, name);
        if ~ischar(s), s = char(string(s)); end
    catch
        s = '';
    end
end

function n = portNum(ph)
%PORTNUM  포트 핸들에서 번호를 얻는다. 실패하면 NaN — 0 으로 두지 않는다.
%   0 은 「첫 포트」로 오해되고, 「못 읽었다」와 구분되지 않는다.
    n = NaN;
    if ~isnumeric(ph) || ph < 0, return; end
    try, n = double(get_param(ph, 'PortNumber')); catch, n = NaN; end
end

function t = rel(b, m)
    t = strrep(strrep(char(b), [m '/'], ''), newline, ' ');
end
