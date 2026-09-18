function T = collect_types(root, opts)
%COLLECT_TYPES  모델의 **데이터 타입 계약**을 구조체로 수집한다.
%
%   T = collect_types('ExampleModel')
%   T = collect_types('ExampleModel', struct('Compile', true))
%
%   왜 dump_types 와 따로 만드나
%   ──────────────────────────
%   ① `dump_types.m:103` 이 **R18 을 위반한다.** `sfroot` 로 Chart 를 세면서
%      `find_mdlrefs` 로 거르지 않아, 그때 열려 있는 모델에 따라 결과가 달라진다.
%      (같은 볼트에서 Chart 수가 3/7/9 로 흔들린 원인이 그것이다.)
%      여기서는 참조 트리로 고정한다.
%   ② `dump_types` 는 사람이 읽는 마크다운을 낸다. 손 변환의 **타입 대응표**는
%      기계가 읽을 수 있어야 에이전트가 병렬로 대조한다.
%   ③ `CompiledPortDataTypes` 는 dump_types 에 없다. 「선언된 타입」과
%      「실제로 전파된 타입」은 다르고, C 로 옮길 때 필요한 것은 후자다.
%
%   opts.Compile (기본 false)
%   ────────────────────────
%   true 면 모델을 컴파일해 `CompiledPortDataTypes` 를 읽는다.
%   ⚠️ 실측(2026-09-08): 이 모델은 진단 6종이 전부 `error` 다. 컴파일이 실패하면
%      그 자체가 정보이므로 **삼키지 않고 T.compileError 에 남긴다.**
%      컴파일은 부작용이 있으므로(모델 상태 변경) 기본값은 false 다.
%
%   🔴 추론하지 않는다. `get_param` / 객체 속성에서 읽은 값만 담는다.

    if nargin < 1 || isempty(root)
        error('collect_types:noArg', '루트 모델 이름이 필요하다.');
    end
    root = char(root);
    if nargin < 2 || isempty(opts), opts = struct(); end
    doCompile = isfield(opts,'Compile') && opts.Compile;

    FF = {'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on', ...
          'MatchFilter',@Simulink.match.allVariants};   % 침묵 제외 4종 (R3)

    if ~bdIsLoaded(root), load_system(root); end
    mdls = find_mdlrefs(root);
    for i = 1:numel(mdls)
        if ~bdIsLoaded(mdls{i}), load_system(mdls{i}); end
    end

    T = struct();
    T.root      = root;
    T.collected = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
    T.models    = reshape(mdls, 1, []);
    T.filters   = 'LookUnderMasks=all · FollowLinks=on · IncludeCommented=on · allVariants (R3)';
    T.warnings  = {};

    % ── A. 모델 경계 포트 ─────────────────────────────
    %    C 함수의 인자·반환에 대응한다. 손 변환의 출발점이다.
    T.ports = struct('model',{},'kind',{},'name',{},'portNumber',{}, ...
                     'declaredType',{},'compiledType',{},'dims',{});
    for m = 1:numel(mdls)
        M = mdls{m};
        for kind = {'Inport','Outport'}
            bs = find_system(M,'SearchDepth',1,FF{:},'BlockType',kind{1});
            for i = 1:numel(bs)
                e = struct();
                e.model        = M;
                e.kind         = kind{1};
                e.name         = getp(bs{i},'Name');
                e.portNumber   = getp(bs{i},'Port');
                e.declaredType = getp(bs{i},'OutDataTypeStr');
                e.compiledType = '';        % Compile 단계에서 채운다
                e.dims         = getp(bs{i},'PortDimensions');
                T.ports(end+1) = e;
            end
        end
    end

    % ── B. 전역 데이터스토어 (Simulink.Signal) ────────
    T.signals = struct('model',{},'name',{},'dataType',{},'dims',{}, ...
                       'complexity',{},'initialValue',{},'min',{},'max',{});
    for m = 1:numel(mdls)
        M = mdls{m};
        try
            mw = get_param(M,'ModelWorkspace');
            v  = mw.whos;
            sig = v(strcmp({v.class},'Simulink.Signal'));
            for i = 1:numel(sig)
                o = mw.getVariable(sig(i).name);
                e = struct();
                e.model        = M;
                e.name         = sig(i).name;
                e.dataType     = str(tryget(o,'DataType'));
                e.dims         = str(tryget(o,'Dimensions'));
                e.complexity   = str(tryget(o,'Complexity'));
                e.initialValue = str(tryget(o,'InitialValue'));
                e.min          = str(tryget(o,'Min'));
                e.max          = str(tryget(o,'Max'));
                T.signals(end+1) = e;
            end
        catch e2
            T.warnings{end+1} = sprintf('%s ModelWorkspace 읽기 실패: %s', M, e2.message);
        end
    end

    % ── C. 타입 변환 블록 ─────────────────────────────
    %    C 에서 캐스팅이 되는 자리다. 반올림·포화가 의미를 바꾼다.
    T.conversions = struct('model',{},'path',{},'outType',{},'rounding',{},'saturate',{});
    for m = 1:numel(mdls)
        M = mdls{m};
        bs = find_system(M,FF{:},'BlockType','DataTypeConversion');
        for i = 1:numel(bs)
            e = struct();
            e.model    = M;
            e.path     = rel(bs{i}, M);
            e.outType  = getp(bs{i},'OutDataTypeStr');
            e.rounding = getp(bs{i},'RndMeth');
            e.saturate = getp(bs{i},'SaturateOnIntegerOverflow');
            T.conversions(end+1) = e;
        end
    end

    % ── D. Stateflow Chart Data ───────────────────────
    %    🔴 R18: sfroot 를 참조 트리로 거른다. dump_types 는 이것을 안 한다.
    T.chartData = struct('chart',{},'name',{},'scope',{},'dataType',{}, ...
                         'size',{},'initialValue',{},'min',{},'max',{});
    r  = sfroot;
    ch = r.find('-isa','Stateflow.Chart');
    nSkipped = 0;
    for k = 1:numel(ch)
        cp = char(ch(k).Path);
        if ~any(strcmp(strtok(cp,'/'), mdls))
            nSkipped = nSkipped + 1;    % 참조 트리 밖 — 세지 않는다
            continue
        end
        dd = ch(k).find('-isa','Stateflow.Data');
        for j = 1:numel(dd)
            d = dd(j);
            e = struct();
            e.chart        = cp;
            e.name         = str(tryget(d,'Name'));
            e.scope        = str(tryget(d,'Scope'));
            e.dataType     = str(tryget(d,'DataType'));
            e.size         = str(tryprops(d,'Array','Size'));
            e.initialValue = str(tryprops(d,'InitialValue'));
            e.min          = str(tryrange(d,'Minimum'));
            e.max          = str(tryrange(d,'Maximum'));
            T.chartData(end+1) = e;
        end
    end
    T.chartsSkipped = nSkipped;    % 「몇 개를 뺐는가」를 남긴다 — 0건의 근거가 된다

    % ── E. 컴파일해서 실제 전파 타입 읽기 (선택) ──────
    T.compiled     = doCompile;
    T.compileError = '';
    if doCompile
        % 🔴 `set_param(m,'SimulationCommand','update')` 를 쓰면 안 된다 (2026-09-08 실측).
        %    update 는 컴파일을 끝내고 상태를 `stopped` 로 되돌리는데,
        %    `CompiledPortDataTypes` 는 **컴파일 상태에서만** 유효하다.
        %    그래서 get_param 이 빈 struct 를 주고 전 포트가 빈 값이 됐다.
        %    모델을 컴파일 상태로 붙잡아 두는 관용구는 `model([],[],[],'compile')` 이다.
        % 🔴 실측(2026-09-08): 이 모델은 그냥 컴파일하면 막힌다.
        %      [Simulink:Engine:OutportCannotLogNonBuiltInDataTypes]
        %      outport 'ExampleModel/PDO_Outputs' 를 structure/array 로 로깅할 수 없다
        %    출력 로깅 설정 때문이지 모델 구조 문제가 아니다. 회차 중에만 로깅을 끄고
        %    **반드시 원복한다.** 원복은 onCleanup 이 보장한다 — 중간에 에러가 나도 돈다.
        %    ⚠️ 회사 모델의 설정이므로 dirty 플래그까지 원래대로 되돌린다.
        %       (원복해도 dirty 가 남으면 사용자가 무심코 저장할 때 설정이 바뀐다)
        cs0       = getActiveConfigSet(root);
        wasDirty  = strcmp(get_param(root,'Dirty'), 'on');
        saveOut0  = get_param(cs0, 'SaveOutput');

        % 🔴 Configuration Reference 면 설정을 바꾸지 않는다 (2026-09-08 실측).
        %    이 모델은 설정을 외부 Configuration Set 에서 참조한다. set_param 이
        %    거부되고("Parameter update is not supported for a configuration reference"),
        %    참조 원본을 고치면 **그것을 참조하는 다른 모델까지 바뀐다.**
        %    회사 모델에서 그런 부작용을 감수하면서까지 읽을 값이 아니다.
        T.configRef = '';
        if isa(cs0, 'Simulink.ConfigSetRef')
            try, T.configRef = char(cs0.SourceName); catch, T.configRef = '(이름 미상)'; end
            T.warnings{end+1} = sprintf(['Configuration Reference(%s)를 쓰므로 로깅 설정을 ' ...
                '바꾸지 않았다. 컴파일이 막히면 CompiledPortDataTypes 는 미확인으로 남는다'], T.configRef);
        else
            restore = onCleanup(@() restore_logging(root, saveOut0, wasDirty)); %#ok<NASGU>
            try
                set_param(cs0, 'SaveOutput', 'off');
            catch e0
                T.warnings{end+1} = sprintf('SaveOutput 을 끄지 못했다: %s', e0.message);
            end
        end

        compiled = false;
        try
            feval(root, [], [], [], 'compile');
            compiled = true;
            for i = 1:numel(T.ports)
                b = [T.ports(i).model '/' T.ports(i).name];
                try
                    cpt = get_param(b, 'CompiledPortDataTypes');
                    if isstruct(cpt) && isfield(cpt,'Outport') && ~isempty(cpt.Outport)
                        v = cpt.Outport;
                        if iscell(v), v = v{1}; end
                        T.ports(i).compiledType = char(string(v));
                    else
                        T.ports(i).compiledType = '<컴파일값없음>';
                    end
                catch
                    T.ports(i).compiledType = '<읽기실패>';
                end
            end
        catch e3
            % 🔴 삼키지 않는다. 진단 6종이 error 라 컴파일 실패 자체가 정보다.
            T.compileError = sprintf('[%s] %s', e3.identifier, e3.message);
        end
        if compiled
            try, feval(root, [], [], [], 'term'); catch, end
        end
    end

    T.counts = struct('models', numel(mdls), 'ports', numel(T.ports), ...
                      'signals', numel(T.signals), 'conversions', numel(T.conversions), ...
                      'chartData', numel(T.chartData), 'warnings', numel(T.warnings));

    fprintf('\n──────── 타입 수집 (collect_types) ────────\n');
    fprintf('  모델 %d · 경계포트 %d · 전역신호 %d · 타입변환 %d · ChartData %d\n', ...
        T.counts.models, T.counts.ports, T.counts.signals, ...
        T.counts.conversions, T.counts.chartData);
    fprintf('  참조 트리 밖이라 제외한 Chart: %d개  (R18 — sfroot 를 그대로 쓰지 않는다)\n', nSkipped);
    if ~isempty(T.compileError)
        fprintf('  🔴 컴파일 실패 — CompiledPortDataTypes 없음\n     %s\n', T.compileError);
    elseif doCompile
        % 🔴 `~isempty` 로 세면 '<읽기실패>' 도 「확보」로 센다 (2026-09-08 실제 오판).
        %    「실패 0건」이 「0건을 검사했다」인 것과 같은 구조다. 실패 문자열을 뺀다.
        cts  = {T.ports.compiledType};
        bad  = strcmp(cts,'<읽기실패>') | strcmp(cts,'<컴파일값없음>') | cellfun(@isempty, cts);
        nGot = sum(~bad);
        fprintf('  컴파일 타입 확보: %d/%d 포트  (실패 %d)\n', nGot, numel(T.ports), sum(bad));
        if nGot == 0
            fprintf('  🔴 하나도 못 읽었다. CompiledPortDataTypes 는 컴파일 상태에서만 유효하다.\n');
        end
    end
    if T.counts.warnings > 0
        fprintf('  ⚠ 경고 %d건\n', T.counts.warnings);
        for i = 1:numel(T.warnings), fprintf('     %s\n', T.warnings{i}); end
    end
end


% ══════════════════════════════════════════════════════

function restore_logging(root, saveOut0, wasDirty)
%RESTORE_LOGGING  회차 중 바꾼 로깅 설정을 되돌린다.
%   🔴 실패하면 조용히 넘어가지 않고 경고를 띄운다 — 회사 모델의 설정이
%      바뀐 채 남는 것이 이 함수가 막으려는 사고다.
    try
        cs = getActiveConfigSet(root);
        if ~strcmp(get_param(cs,'SaveOutput'), saveOut0)
            set_param(cs, 'SaveOutput', saveOut0);
        end
    catch e
        warning('collect_types:restore', ...
            ['SaveOutput 을 %s 로 되돌리지 못했다: %s\n' ...
             '  🔴 이 모델을 저장하기 전에 손으로 확인한다.'], saveOut0, e.message);
        return
    end
    % 바꾸기 전에 깨끗했으면 깨끗한 상태로 되돌린다.
    try
        if ~wasDirty
            set_param(root, 'Dirty', 'off');
        end
    catch
        warning('collect_types:dirty', ...
            'Dirty 플래그를 되돌리지 못했다. 저장 전에 확인한다.');
    end
end

function v = getp(b, name)
    try
        v = get_param(b, name);
        if ~ischar(v), v = str(v); end
    catch
        v = '<읽기실패>';
    end
end

function v = tryget(o, name)
    try
        v = o.(name);
    catch
        v = '';
    end
end

function v = tryprops(o, varargin)
    try
        v = o.Props;
        for i = 1:numel(varargin)
            v = v.(varargin{i});
        end
    catch
        v = '';
    end
end

function v = tryrange(o, which)
    try
        v = o.Props.Range.(which);
    catch
        v = '';
    end
end

function s = str(x)
    if ischar(x),        s = x;
    elseif isstring(x),  s = char(x);
    elseif isempty(x),   s = '';
    elseif isnumeric(x) && isscalar(x), s = num2str(x);
    elseif isnumeric(x), s = mat2str(x);
    elseif islogical(x), s = mat2str(x);
    else
        try, s = char(string(x)); catch, s = class(x); end
    end
    s = strrep(s, newline, ' ');
end

function t = rel(b, m)
    t = strrep(strrep(b, [m '/'], ''), newline, ' ');
end
