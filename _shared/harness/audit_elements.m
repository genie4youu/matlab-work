function ok = audit_elements(vaultDir, outFile, model)
%AUDIT_ELEMENTS  컨테이너 **안의 구성요소**가 문서에 빠짐없이 있는지 대조한다.
%
%   audit_elements('C:\...\work\sessions\20260804\서브시스템', '_분석출력\elements.md')
%
%   왜 필요한가 — audit_coverage 가 못 보는 층
%   ────────────────────────────────────────
%   2026-08-05 사용자 지적:
%     "set_passive_joint_range_fault 는 분석도 안 됐고, set_pc_vc_interrupt_fault 는 이름도 틀렸다"
%
%   지적이 둘 다 옳았다. 실체는 이랬다.
%     Set_Passive_Joint_Range_Fault : M1/Fault_Management 의 **실재하는 SubSystem**(SID 1270).
%                                     Commented='on' 이라 find_system 이 조용히 뺐다 (R21).
%     Set_PC_VC_Interrupt_Fault     : 같은 층의 **area_annotation**(SID 1326).
%                                     캔버스에서 기능 그룹 이름 역할을 하는데 한 번도 열거하지 않았다 (R22).
%
%   두 실수의 공통점은 「블록 목록에 안 나오는 것은 없는 것으로 취급했다」는 점이다.
%   그리고 audit_coverage 의 판정 ①②③④ 는 전부 **컨테이너 단위**라 이것을 못 본다.
%
%     ① 그 컨테이너의 문서가 있는가
%     ② 해석 절이 채워졌는가
%     ③ 식별자가 3개 이상 나오는가      ← 3개면 통과한다. State 가 7개여도.
%     ④ 소절 5개가 있는가
%
%   즉 **컨테이너 안에 무엇이 몇 개 있고 그것이 전부 문서에 있는가는 아무도 안 본다.**
%   Chart 문서에 State 7개가 다 있는 것은 gen_vault_charts 가 기계적으로 뽑기
%   때문이지 검사를 통과해서가 아니다. 사람이 문서를 고쳐 쓰면서 State 하나를
%   빠뜨리거나 이름을 잘못 적어도 지금은 아무 판정도 실패하지 않는다.
%
%   이 스크립트가 보는 것
%   ────────────────────
%   컨테이너마다 그 안의 **원소를 전수 열거**하고, 각 원소 이름이 그 컨테이너의
%   정본 문서 본문에 **문자 그대로** 있는지 센다.
%
%     Stateflow Chart : State · Data · Event 이름
%     SubSystem       : 직속 하위 블록 이름 · Data Store 이름
%
%   ⚠️ 이름을 **잘못 적은 것**도 여기서 잡힌다. 원본 이름이 문서에 없으면 실패다.

    if nargin < 2 || isempty(outFile), outFile = fullfile('_분석출력','elements.md'); end
    if nargin < 3, model = ''; end

    % 🔴 모델 이름을 문자열로 박지 않는다.
    %    초판은 `vault_units('ExampleModel')` 이라 **다른 모델을 감사하라고 해도
    %    늘 ExampleModel 을 감사했다.** 오류가 나지 않아 알아채기 어렵다.
    ctx = vault_ctx(model);

    d = fileparts(outFile);
    if ~isempty(d) && ~isfolder(d), mkdir(d); end

    U = vault_units(ctx.model);   % 열거는 vault_units 하나가 한다 (R19)

    fid = fopen(outFile,'w','n','UTF-8');
    oc  = onCleanup(@() fclose(fid));
    p = @(varargin) fprintf(fid, varargin{:});

    p('# 원소 커버리지 감사\n\n');
    p('`audit_coverage` 는 **컨테이너**가 문서화됐는지 본다.\n');
    p('이 문서는 **컨테이너 안의 원소**가 그 문서에 빠짐없이 있는지 본다.\n\n');
    p('> 계기 (2026-08-05): `M1/Fault_Management/Set_Passive_Joint_Range_Fault`(Commented) 와\n');
    p('> 같은 층의 area annotation `Set_PC_VC_Interrupt_Fault` 가 분석 단위 78개 어디에도 없었다.\n');
    p('> 판정 ③ 은 식별자 3개면 통과하므로, 원소가 20개여도 17개가 빠질 수 있다.\n\n');

    p('| # | 컨테이너 | 종류 | 원소 | 문서에 있음 | 빠진 것 |\n');
    p('| --- | --- | --- | --- | --- | --- |\n');

    nBad = 0; bad = {}; noDoc = {};
    for k = 1:numel(U)
        u   = U(k);
        % 정본 문서 경로는 audit_coverage 와 **같은 방식**으로 계산한다.
        doc = fullfile(vaultDir, u.segs{:}, [strjoin(u.segs,'_') '.md']);
        if ~isfile(doc), noDoc{end+1} = u.rel; continue; end %#ok<AGROW>
        txt = read_utf8(doc);

        ids = elementsOf(u);
        if isempty(ids), continue; end

        missing = {};
        for j = 1:numel(ids)
            if ~contains(txt, ids{j}), missing{end+1} = ids{j}; end %#ok<AGROW>
        end

        okMark = 'O';
        if ~isempty(missing)
            okMark = '**X**'; nBad = nBad + 1;
            bad{end+1} = sprintf('`%s` — %d/%d 누락: %s', u.rel, numel(missing), numel(ids), ...
                                 strjoin(missing, ', ')); %#ok<AGROW>
        end
        p('| %d | `%s` | %s | %d | %s %d | %s |\n', k, u.rel, u.kind, numel(ids), ...
            okMark, numel(ids)-numel(missing), strjoin(missing, ' / '));
    end

    if ~isempty(noDoc)
        p('\n> 정본 문서가 없어 대조하지 못한 컨테이너 %d개 — 이것은 `audit_coverage` ① 이 잡는다.\n\n', numel(noDoc));
    end

    p('\n## 결과\n\n');
    if nBad == 0
        p('**통과.** 모든 컨테이너의 원소가 그 정본 문서에 전부 등장한다.\n');
    else
        p('🔴 **실패 %d건.**\n\n', nBad);
        for k = 1:numel(bad), p('- %s\n', bad{k}); end
        p('\n원소 이름이 문서에 없다는 것은 둘 중 하나다 — **빠뜨렸거나, 이름을 잘못 적었거나.**\n');
    end
    ok = (nBad == 0);
    fprintf('원소 감사 완료: 실패 %d건 → %s\n', nBad, outFile);
end


function ids = elementsOf(u)
%ELEMENTSOF  컨테이너 안의 원소 이름을 전수로 모은다.
    ids = {};
    switch u.kind
        case 'Stateflow Chart'
            c = u.chart;
            for cls = {'Stateflow.State','Stateflow.Data','Stateflow.Event'}
                o = c.find('-isa', cls{1});
                for j = 1:numel(o), ids{end+1} = char(o(j).Name); end %#ok<AGROW>
            end
        case 'SubSystem'
            b = u.path;
            kid = find_system(b,'SearchDepth',1,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants);
            for j = 1:numel(kid)
                if strcmp(kid{j}, b), continue; end
                ids{end+1} = strrep(strrep(kid{j},[b '/'],''), newline, ' '); %#ok<AGROW>
            end
            for bt = {'DataStoreRead','DataStoreWrite'}
                L = find_system(b,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants, ...
                                'BlockType',bt{1});
                for j = 1:numel(L), ids{end+1} = get_param(L{j},'DataStoreName'); end %#ok<AGROW>
            end
            % 영역 주석 이름 — 블록이 아니지만 캔버스에서 읽히는 기능 이름이다 (R22).
            try
                a = find_system(b,'SearchDepth',1,'LookUnderMasks','all','FollowLinks','on', ...
                                'IncludeCommented','on','MatchFilter',@Simulink.match.allVariants,'FindAll','on','Type','annotation');
                for j = 1:numel(a)
                    ty = ''; try, ty = get_param(a(j),'AnnotationType'); catch, end
                    if ~strcmp(ty,'area_annotation'), continue; end
                    nm = ''; try, nm = get_param(a(j),'Name'); catch, end
                    nm = strtrim(regexprep(strrep(strrep(nm,sprintf('\r'),' '),sprintf('\n'),' '), '\s+',' '));
                    if ~isempty(nm), ids{end+1} = nm; end %#ok<AGROW>
                end
            catch
            end
        otherwise
            % ModelReference 는 내부가 없다. 참조 대상 모델이 자기 문서를 갖는다.
            return
    end
    ids = unique(ids(~cellfun(@isempty, ids)));
end
