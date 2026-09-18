function dump_subsystem(sysPath, outFile)
%DUMP_SUBSYSTEM  Simulink 서브시스템 하나를 마크다운으로 전수 덤프한다.
%
%   dump_subsystem('ExampleModel/M1/Fault_Management', 'out\Fault_Management_sys.md')
%
%   덤프 항목
%     - 블록 유형별 집계
%     - Data Store Read / Write 전수 (어느 블록이 어느 전역변수를 읽고 쓰는가)
%     - Constant 값, Gain, 비교/논리 연산자
%     - Model Reference / Subsystem Reference 대상
%     - 하위 서브시스템 목록
%
%   Data Store 표가 핵심이다. 이 모델은 신호선이 아니라 전역 데이터스토어로
%   통신하므로, 배선도를 봐도 데이터 흐름을 알 수 없다.

    if ~bdIsLoaded(strtok(sysPath,'/'))
        load_system(strtok(sysPath,'/'));
    end

    d = fileparts(outFile);
    if ~isempty(d) && ~isfolder(d), mkdir(d); end
    fid = fopen(outFile,'w','n','UTF-8');
    oc  = onCleanup(@() fclose(fid));
    p = @(varargin) fprintf(fid, varargin{:});

    p('# 서브시스템 덤프 — `%s`\n\n', sysPath);

    blks = find_system(sysPath, 'LookUnderMasks','all', 'FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants);
    blks = blks(2:end);   % 자기 자신 제외
    p('전체 블록 %d개 (하위 포함)\n\n', numel(blks));

    % ── 블록 유형 집계 ────────────────────────────────
    bt = cell(numel(blks),1);
    for k = 1:numel(blks)
        try, bt{k} = get_param(blks{k},'BlockType'); catch, bt{k} = '?'; end
    end
    [u,~,ic] = unique(bt);
    cnt = accumarray(ic,1);
    [cnt, si] = sort(cnt,'descend'); u = u(si);
    p('## A. 블록 유형별 집계\n\n| 유형 | 개수 |\n| --- | --- |\n');
    for k = 1:numel(u), p('| `%s` | %d |\n', u{k}, cnt(k)); end
    p('\n');

    % ── Data Store 읽기/쓰기 ──────────────────────────
    p('## B. Data Store 접근 (전역 변수 사용처)\n\n');
    rd = collect(blks, 'DataStoreRead');
    wr = collect(blks, 'DataStoreWrite');

    p('### B-1. Write (%d개) — 이 서브시스템이 값을 만드는 곳\n\n', numel(wr));
    dumpDS(p, wr, sysPath);

    p('### B-2. Read (%d개) — 이 서브시스템이 값을 가져오는 곳\n\n', numel(rd));
    dumpDS(p, rd, sysPath);

    % 같은 스토어에 write 가 여럿인지
    wn = cellfun(@(b) get_param(b,'DataStoreName'), wr, 'uni', 0);
    [uw,~,iw] = unique(wn);
    cw = accumarray(iw,1);
    multi = uw(cw > 1);
    p('### B-3. 이 서브시스템 안에서 writer 가 복수인 스토어\n\n');
    if isempty(multi)
        p('없음\n\n');
    else
        p('| 스토어 | writer 수 |\n| --- | --- |\n');
        for k = 1:numel(multi)
            p('| `%s` | %d |\n', multi{k}, cw(strcmp(uw,multi{k})));
        end
        p('\n동일 스텝에서 복수 writer 가 발화하면 마지막 writer 의 값이 남는다.\n\n');
    end

    % ── 참조 블록 ─────────────────────────────────────
    p('## C. 참조 대상\n\n');
    mr = collect(blks, 'ModelReference');
    sr = find_system(sysPath, 'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants,'BlockType','SubSystem');
    p('### C-1. Model Reference (%d개)\n\n', numel(mr));
    if isempty(mr), p('없음\n\n'); else
        p('| 블록 | 참조 모델 |\n| --- | --- |\n');
        for k = 1:numel(mr)
            p('| `%s` | `%s` |\n', rel(mr{k},sysPath), get_param(mr{k},'ModelName'));
        end
        p('\n');
    end

    srr = {};
    for k = 1:numel(sr)
        try
            f = get_param(sr{k},'ReferencedSubsystem');
            if ~isempty(f), srr{end+1} = sr{k}; end %#ok<AGROW>
        catch
        end
    end
    p('### C-2. Subsystem Reference (%d개)\n\n', numel(srr));
    if isempty(srr), p('없음\n\n'); else
        p('| 블록 | 참조 대상 |\n| --- | --- |\n');
        for k = 1:numel(srr)
            p('| `%s` | `%s` |\n', rel(srr{k},sysPath), get_param(srr{k},'ReferencedSubsystem'));
        end
        p('\n');
    end

    % ── 상수·게인·비교 ────────────────────────────────
    p('## D. 값이 박혀 있는 블록\n\n');
    dumpParam(p, collect(blks,'Constant'),      'Value',    'Constant', sysPath);
    dumpParam(p, collect(blks,'Gain'),          'Gain',     'Gain',     sysPath);
    dumpParam(p, collect(blks,'RelationalOperator'), 'Operator','Relational', sysPath);
    dumpParam(p, collect(blks,'Logic'),         'Operator', 'Logic',    sysPath);
    dumpParam(p, collect(blks,'Switch'),        'Criteria', 'Switch',   sysPath);

    % ── 하위 서브시스템 ───────────────────────────────
    sub = find_system(sysPath,'SearchDepth',1,'LookUnderMasks','none','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants,'BlockType','SubSystem');
    p('## E. 직속 하위 서브시스템 (%d개)\n\n', numel(sub));
    if isempty(sub), p('없음\n'); else
        p('| 이름 | 하위 블록 수 |\n| --- | --- |\n');
        for k = 1:numel(sub)
            n = numel(find_system(sub{k},'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants)) - 1;
            p('| `%s` | %d |\n', get_param(sub{k},'Name'), n);
        end
    end
    p('\n');
end


function out = collect(blks, btype)
    out = {};
    for k = 1:numel(blks)
        try
            if strcmp(get_param(blks{k},'BlockType'), btype)
                out{end+1} = blks{k}; %#ok<AGROW>
            end
        catch
        end
    end
end

function dumpDS(p, list, root)
    if isempty(list), p('없음\n\n'); return; end
    nm = cellfun(@(b) get_param(b,'DataStoreName'), list, 'uni', 0);
    [~, si] = sort(nm);
    p('| 스토어 | 블록 위치 |\n| --- | --- |\n');
    for k = si
        p('| `%s` | `%s` |\n', get_param(list{k},'DataStoreName'), rel(list{k}, root));
    end
    p('\n');
end

function dumpParam(p, list, prm, label, root)
    if isempty(list), return; end
    p('### %s (%d개)\n\n| 블록 | %s |\n| --- | --- |\n', label, numel(list), prm);
    for k = 1:numel(list)
        v = '';
        try, v = get_param(list{k}, prm); catch, end
        p('| `%s` | `%s` |\n', rel(list{k}, root), strrep(v, '|', '\|'));
    end
    p('\n');
end

function s = rel(blk, root)
    s = strrep(blk, [root '/'], '');
    s = strrep(s, sprintf('\n'), ' ');
end
