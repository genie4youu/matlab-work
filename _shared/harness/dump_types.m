function dump_types(model, outFile)
%DUMP_TYPES  데이터 타입·크기·비트 연산을 전수 덤프한다.
%
%   추론하지 않는다. get_param / 객체 속성에서 읽은 값만 적는다.
%
%   덤프 항목
%     A. 전역 데이터스토어 (Simulink.Signal) 전수 — 타입·차원·초기값·범위
%     B. Bitwise Operator 전수 — 연산·마스크
%     C. Shift Arithmetic 전수 — 시프트 수·방향
%     D. Data Type Conversion 전수 — 출력 타입·반올림·포화
%     E. Sum / Gain 전수 — 누적 타입·포화
%     F. 모델 경계 Inport / Outport 타입
%     G. Stateflow Chart Data 전수 — Scope·타입

    if ~bdIsLoaded(model), load_system(model); end
    d = fileparts(outFile);
    if ~isempty(d) && ~isfolder(d), mkdir(d); end
    fid = fopen(outFile,'w','n','UTF-8');
    oc  = onCleanup(@() fclose(fid));
    p = @(varargin) fprintf(fid, varargin{:});

    p('# 데이터 타입·비트 전수 덤프 — `%s`\n\n', model);
    p('추출: `dump_types.m`. 모든 값은 `get_param` 또는 객체 속성 원본이며 추론이 없다.\n\n');

    % ── A. 전역 데이터스토어 ───────────────────────────
    mw = get_param(model,'ModelWorkspace');
    v  = mw.whos;
    sig = v(strcmp({v.class},'Simulink.Signal'));
    p('## A. 전역 데이터스토어 `Simulink.Signal` (%d개)\n\n', numel(sig));
    p('| 이름 | DataType | Dimensions | Complexity | InitialValue | Min | Max |\n');
    p('| --- | --- | --- | --- | --- | --- | --- |\n');
    nm = sort({sig.name});
    for k = 1:numel(nm)
        o = mw.getVariable(nm{k});
        p('| `%s` | `%s` | %s | %s | `%s` | %s | %s |\n', ...
            nm{k}, s(o.DataType), s(mat2strq(o.Dimensions)), s(o.Complexity), ...
            s(o.InitialValue), s(mat2strq(o.Min)), s(mat2strq(o.Max)));
    end
    p('\n');

    % ── B. Bitwise Operator ───────────────────────────
    bw = find_system(model,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants,'BlockType','S-Function');
    bw = keepFcn(bw, 'sfix_bitop');
    p('## B. Bitwise Operator (%d개)\n\n', numel(bw));
    p('| 블록 | 연산 | 마스크 | 마스크 사용 |\n| --- | --- | --- | --- |\n');
    for k = 1:numel(bw)
        p('| `%s` | `%s` | `%s` | %s |\n', rel(bw{k},model), ...
            gp(bw{k},'logicop'), gp(bw{k},'BitMask'), gp(bw{k},'UseBitMask'));
    end
    p('\n');

    % ── C. Shift Arithmetic ───────────────────────────
    sh = find_system(model,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants,'BlockType','ArithShift');
    p('## C. Shift Arithmetic (%d개)\n\n', numel(sh));
    p('> 부호 규약은 최소 모델로 실측했다. **양수 N = 오른쪽 시프트, 음수 N = 왼쪽 시프트.**\n\n');
    p('| 블록 | N | 방향 | 해석 | BinPt |\n| --- | --- | --- | --- | --- |\n');
    for k = 1:numel(sh)
        n = str2double(gp(sh{k},'BitShiftNumber'));
        if n > 0,      how = sprintf('`>> %d`', n);
        elseif n < 0,  how = sprintf('`<< %d`', -n);
        else,          how = '이동 없음';
        end
        p('| `%s` | %s | `%s` | %s | %s |\n', rel(sh{k},model), ...
            gp(sh{k},'BitShiftNumber'), gp(sh{k},'BitShiftDirection'), how, gp(sh{k},'BinPtShiftNumber'));
    end
    p('\n');

    % ── D. Data Type Conversion ───────────────────────
    dt = find_system(model,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants,'BlockType','DataTypeConversion');
    p('## D. Data Type Conversion (%d개)\n\n', numel(dt));
    p('| 블록 | 출력 타입 | 입력·출력 해석 | 반올림 | 포화 |\n| --- | --- | --- | --- | --- |\n');
    for k = 1:numel(dt)
        p('| `%s` | `%s` | `%s` | `%s` | `%s` |\n', rel(dt{k},model), ...
            gp(dt{k},'OutDataTypeStr'), gp(dt{k},'ConvertRealWorld'), ...
            gp(dt{k},'RndMeth'), gp(dt{k},'SaturateOnIntegerOverflow'));
    end
    p('\n');

    % ── E. Sum / Gain ─────────────────────────────────
    sm = find_system(model,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants,'BlockType','Sum');
    p('## E. Sum (%d개)\n\n', numel(sm));
    p('| 블록 | 부호 | 누적 타입 | 출력 타입 | 포화 |\n| --- | --- | --- | --- | --- |\n');
    for k = 1:numel(sm)
        p('| `%s` | `%s` | `%s` | `%s` | `%s` |\n', rel(sm{k},model), ...
            gp(sm{k},'Inputs'), gp(sm{k},'AccumDataTypeStr'), ...
            gp(sm{k},'OutDataTypeStr'), gp(sm{k},'SaturateOnIntegerOverflow'));
    end
    p('\n');

    % ── F. 모델 경계 포트 ─────────────────────────────
    p('## F. 모델 경계 포트\n\n');
    for bt = {'Inport','Outport'}
        pp = find_system(model,'SearchDepth',1,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants,'BlockType',bt{1});
        p('### %s (%d개)\n\n| 포트 | 데이터형 | 포트번호 |\n| --- | --- | --- |\n', bt{1}, numel(pp));
        for k = 1:numel(pp)
            p('| `%s` | `%s` | %s |\n', get_param(pp{k},'Name'), ...
                gp(pp{k},'OutDataTypeStr'), gp(pp{k},'Port'));
        end
        p('\n');
    end

    % ── G. Chart Data ─────────────────────────────────
    r  = sfroot;
    ch = r.find('-isa','Stateflow.Chart');
    p('## G. Stateflow Chart Data (Chart %d개)\n\n', numel(ch));
    for k = 1:numel(ch)
        c  = ch(k);
        dd = c.find('-isa','Stateflow.Data');
        p('### `%s` — Data %d개\n\n', c.Path, numel(dd));
        p('| 이름 | Scope | DataType | Size | InitialValue |\n| --- | --- | --- | --- | --- |\n');
        for j = 1:numel(dd)
            x = dd(j); iv = '';
            try, iv = x.Props.InitialValue; catch, end
            p('| `%s` | %s | `%s` | %s | `%s` |\n', x.Name, x.Scope, ...
                s(x.DataType), s(x.Props.Array.Size), s(iv));
        end
        p('\n');
        ev = c.find('-isa','Stateflow.Event');
        if ~isempty(ev)
            p('Event %d개\n\n| 이름 | Scope | Trigger |\n| --- | --- | --- |\n', numel(ev));
            for j = 1:numel(ev)
                p('| `%s` | %s | %s |\n', ev(j).Name, ev(j).Scope, s(gpo(ev(j),'Trigger')));
            end
            p('\n');
        end
    end
end


function out = keepFcn(list, fname)
    out = {};
    for k = 1:numel(list)
        try
            if strcmp(get_param(list{k},'FunctionName'), fname), out{end+1} = list{k}; end %#ok<AGROW>
        catch
        end
    end
end

function v = gp(b, name)
    v = '-';
    try, x = get_param(b,name); if ischar(x), v = x; end, catch, end
end

function v = gpo(o, name)
    v = '-';
    try, v = o.(name); catch, end
end

function t = s(x)
    if isempty(x),        t = '';
    elseif ischar(x),     t = x;
    elseif isstring(x),   t = char(x);
    else
        try, t = char(string(x)); catch, t = class(x); end
    end
    t = strrep(strrep(t, sprintf('\n'), ' '), '|', '\|');
end

function t = mat2strq(x)
    if isempty(x), t = ''; else
        try, t = mat2str(x); catch, t = class(x); end
    end
end

function t = rel(b, root)
    t = strrep(strrep(b, [root '/'], ''), sprintf('\n'), ' ');
end
