function U = vault_units(root)
%VAULT_UNITS  분석 단위 전수 열거 — **단일 정의** (규칙 R19, 2026-08-05)
%
%   U = vault_units('ExampleModel')
%
%   반환 struct 배열의 필드
%     path  : 블록 경로 (Chart 는 Chart 경로)
%     kind  : 'SubSystem' | 'ModelReference' | 'Stateflow Chart'
%     model : 소속 모델
%     rel   : 표시용 이름. 참조 모델 소속이면 `모델명: 경로`
%     segs  : 볼트 폴더 세그먼트 (vault_base + vault_segs)
%     chart : Stateflow.Chart 핸들 (그 밖은 [])
%
%   왜 하나로 모았나
%   ──────────────
%   전에는 gen_vault_tree · gen_vault_charts · audit_coverage 가 **각자**
%   분석 단위를 열거했다. 그 결과 실제로 갈라졌다.
%
%     - audit_coverage 는 Chart 를 `sfroot` 로 셌다. 그때 열려 있는 모델에
%       따라 3 / 7 / 9 로 흔들렸다 (R18).
%     - SubSystem 은 최상위 모델 안에서만 셌다. 참조 모델 내부 27개가
%       아무 판정에도 걸리지 않았다.
%
%   열거가 갈라지면 감사는 영원히 통과하거나 영원히 실패한다. 여기 하나만 고친다.
%
%   세는 규칙
%   ────────
%   분석 단위 = 하위를 갖거나 다른 파일을 참조하는 모든 것 (R4)
%     SubSystem + ModelReference + Stateflow Chart
%   제외
%     - Simulink 라이브러리 마스크 (부모 문서에 표로 흡수, R10)
%     - 🔴 `SFBlockType='Chart'` 인 SubSystem. Stateflow Chart 는 캔버스에서
%       SubSystem 블록으로도 잡히므로, 배제하지 않으면 **같은 것을 두 번 센다.**
%     - 참조 모델은 **한 번만** 문서화한다. `Debounce8` 이 `Debounce` 를 8번
%       참조해도 단위는 하나다 (vault_base 참조).
%
%   find_system 은 항상 필터 3종을 명시한다 (R3). 기본값에 맡기면 마스크 아래·
%   라이브러리 링크 너머·비활성 Variant 가 조용히 빠진다.

    LIBMASK = {'Compare To Constant','Compare To Zero','Detect Change','Detect Increase'};

    % 경로가 안 잡혀 있으면 참조 모델을 못 찾는다. 스크립트가 스스로 보장한다.
    % (경로 등록이 run_ExampleModel.m 안에만 있어서 실제로 깨졌다 — 2026-08-05)
    ensure_path();

    if ~bdIsLoaded(root), load_system(root); end
    mdls = find_mdlrefs(root);
    for i = 1:numel(mdls)
        if ~bdIsLoaded(mdls{i}), load_system(mdls{i}); end
    end

    U = struct('path',{},'kind',{},'model',{},'rel',{},'segs',{},'chart',{});

    for i = 1:numel(mdls)
        M  = mdls{i};
        b0 = vault_base(M, root);

        ss = find_system(M,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants, ...
                         'BlockType','SubSystem');
        for k = 1:numel(ss)
            mt = ''; try, mt = get_param(ss{k},'MaskType');    catch, end %#ok<CTCH>
            sf = ''; try, sf = get_param(ss{k},'SFBlockType'); catch, end %#ok<CTCH>
            if any(strcmp(mt, LIBMASK)), continue; end
            if strcmp(sf, 'Chart'), continue; end   % Chart 로 따로 센다
            U(end+1) = mkUnit(ss{k}, 'SubSystem', M, root, [b0, vault_segs(ss{k}, M)], []); %#ok<AGROW>
        end

        mr = find_system(M,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants, ...
                         'BlockType','ModelReference');
        for k = 1:numel(mr)
            U(end+1) = mkUnit(mr{k}, 'ModelReference', M, root, [b0, vault_segs(mr{k}, M)], []); %#ok<AGROW>
        end
    end

    % ── Stateflow Chart ───────────────────────────────
    %    sfroot 는 「그때 로드된 모든 모델」을 준다. 참조 목록으로 걸러
    %    무관한 모델이 열려 있어도 결과가 같게 만든다 (R18).
    r  = sfroot;
    ch = r.find('-isa','Stateflow.Chart');
    for k = 1:numel(ch)
        cp    = char(ch(k).Path);
        parts = strsplit(cp, '/');
        owner = parts{1};
        if ~any(strcmp(owner, mdls)), continue; end
        segs = [vault_base(owner, root), cellfun(@safeName, parts(2:end), 'uni', 0)];
        U(end+1) = mkUnit(cp, 'Stateflow Chart', owner, root, segs, ch(k)); %#ok<AGROW>
    end
end


% ══════════════════════════════════════════════════════
function u = mkUnit(pth, kind, M, root, segs, chart)
%MKUNIT  필드 대입으로 만든다. struct('segs',{segs}) 는 셀이 구조체 배열로 펼쳐진다.
    u.path  = pth;
    u.kind  = kind;
    u.model = M;
    r = strrep(strrep(pth, [M '/'], ''), newline, ' ');
    if strcmp(M, root)
        u.rel = r;
    else
        u.rel = sprintf('%s: %s', M, r);   % 어느 모델 소속인지 표에서 보이게 한다
    end
    u.segs  = segs;
    u.chart = chart;
end

function s = safeName(s)
    s = strtrim(strrep(s, newline, ' '));
    s = regexprep(s, '[<>:"/\\?*]', '_');
    s = regexprep(s, '\s+', '_');
end
