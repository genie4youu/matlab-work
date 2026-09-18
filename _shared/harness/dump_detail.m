function dump_detail(sysPath, outFile)
%DUMP_DETAIL  서브시스템을 블록 단위로 상세 덤프한다 (파라미터 + 입력 소스).
%
%   dump_subsystem 이 집계를 낸다면 이쪽은 개별 블록의 값과 배선을 낸다.
%   조합 논리(비교·비트연산·스위치)로 된 소형 서브시스템을 읽을 때 쓴다.

    root = strtok(sysPath,'/');
    if ~bdIsLoaded(root), load_system(root); end

    d = fileparts(outFile);
    if ~isempty(d) && ~isfolder(d), mkdir(d); end
    fid = fopen(outFile,'w','n','UTF-8');
    oc  = onCleanup(@() fclose(fid));
    p = @(varargin) fprintf(fid, varargin{:});

    p('# 상세 덤프 — `%s`\n\n', sysPath);

    blks = find_system(sysPath,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants);
    blks = blks(2:end);
    p('블록 %d개\n\n', numel(blks));
    p('| 블록 | 유형 | 값·연산 | 입력 소스 |\n| --- | --- | --- | --- |\n');

    for k = 1:numel(blks)
        b = blks{k};
        bt = ''; try, bt = get_param(b,'BlockType'); catch, end
        p('| `%s` | `%s` | %s | %s |\n', ...
            clean(strrep(b,[sysPath '/'],'')), bt, valOf(b,bt), srcOf(b, sysPath));
    end
    p('\n');

    % Enable / Trigger 포트가 있으면 그 소스를 따로
    en = find_system(sysPath,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants,'BlockType','EnablePort');
    tg = find_system(sysPath,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants,'BlockType','TriggerPort');
    if ~isempty(en) || ~isempty(tg)
        p('## Enable / Trigger 포트\n\n| 소속 서브시스템 | 종류 | 구동 소스 |\n| --- | --- | --- |\n');
        for k = 1:numel(en)
            par = get_param(en{k},'Parent');
            p('| `%s` | Enable | %s |\n', clean(strrep(par,[sysPath '/'],'')), portSrc(par,'Enable',sysPath));
        end
        for k = 1:numel(tg)
            par = get_param(tg{k},'Parent');
            p('| `%s` | Trigger (%s) | %s |\n', clean(strrep(par,[sysPath '/'],'')), ...
                get_param(tg{k},'TriggerType'), portSrc(par,'Trigger',sysPath));
        end
        p('\n');
    end
end


function s = valOf(b, bt)
    s = '';
    try
        switch bt
            case 'Constant',           s = ['`' get_param(b,'Value') '`'];
            case 'Gain',               s = ['gain `' get_param(b,'Gain') '`'];
            case 'RelationalOperator', s = ['`' get_param(b,'Operator') '`'];
            case 'Logic',              s = ['`' get_param(b,'Operator') '`'];
            case 'Switch',             s = ['조건 `' get_param(b,'Criteria') '` 임계 `' get_param(b,'Threshold') '`'];
            case 'UnitDelay',          s = ['ic `' get_param(b,'InitialCondition') '`'];
            case 'Memory',             s = ['ic `' get_param(b,'InitialCondition') '`'];
            case 'DataStoreRead',      s = ['read `' get_param(b,'DataStoreName') '`'];
            case 'DataStoreWrite',     s = ['**write** `' get_param(b,'DataStoreName') '`'];
            case 'Goto',               s = ['tag `' get_param(b,'GotoTag') '`'];
            case 'From',               s = ['tag `' get_param(b,'GotoTag') '`'];
            case 'S-Function',         s = ['`' get_param(b,'FunctionName') '`'];
            case 'ModelReference',     s = ['-> `' get_param(b,'ModelName') '`'];
            case 'Selector'
                ipa = get_param(b,'IndexParamArray');
                if iscell(ipa) && ~isempty(ipa), s = ['idx `' ipa{1} '`']; end
            case 'BusSelector',        s = ['`' strrep(get_param(b,'OutputSignals'),',',' / ') '`'];
            case 'BusCreator',         s = ['입력 ' get_param(b,'Inputs')];
            case 'Mux',                s = ['입력 ' get_param(b,'Inputs')];
            case 'DataTypeConversion', s = ['-> `' get_param(b,'OutDataTypeStr') '`'];
            case 'SubSystem'
                rs = ''; try, rs = get_param(b,'ReferencedSubsystem'); catch, end
                if ~isempty(rs), s = ['ref -> `' rs '`'];
                else
                    mt=''; try, mt=get_param(b,'MaskType'); catch, end
                    if ~isempty(mt), s = ['mask `' mt '`']; end
                end
        end
    catch
    end
    s = strrep(s, '|', '\|');
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
            sb = get_param(sp,'Parent');
            parts{end+1} = clean(strrep(sb,[root '/'],'')); %#ok<AGROW>
        end
        s = strjoin(parts, ' / ');
    catch
    end
    s = strrep(s, '|', '\|');
end

function s = portSrc(blk, kind, root)
    s = '(미연결)';
    try
        ph = get_param(blk,'PortHandles');
        h = ph.(kind);
        if isempty(h), return; end
        l = get_param(h(1),'Line');
        if l <= 0, return; end
        sp = get_param(l,'SrcPortHandle');
        if sp <= 0, return; end
        sb = get_param(sp,'Parent');
        s = sprintf('`%s` [%s]', clean(strrep(sb,[root '/'],'')), get_param(sb,'BlockType'));
    catch
    end
end

function s = clean(s)
    s = strrep(s, sprintf('\n'), ' ');
end
