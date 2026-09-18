function migrate_vault_r19(root, vaultDir, doIt)
%MIGRATE_VAULT_R19  Chart 문서를 규칙 R19 위치(`_참조모델\<모델명>\`)로 옮긴다.
%
%   migrate_vault_r19('ExampleModel', vaultDir, false)   % dry run (기본)
%   migrate_vault_r19('ExampleModel', vaultDir, true)    % 실제 이동
%
%   무엇이 바뀌나
%   ────────────
%   구(R13) : 참조 모델의 Chart 를 **그 모델을 가리키는 첫 ModelReference 블록**
%             폴더 아래에 두었다.  예) M1\Main_SF\Model-Example_Main_SF\SF\
%   신(R19) : 참조 모델은 파일 단위로 문서화한다.
%             예) _참조모델\Example_Main_SF\SF\
%
%   🔴 반드시 gen_vault_* **전에** 돌린다.
%      재생성은 기대 경로에서 기존 문서를 찾아 해석을 회수한다(read_interp).
%      옮기기 전에 재생성하면 새 경로에 문서가 없으므로 **해석이 자리표시자로
%      덮여 사라진다.** 그리고 그 사실은 다음 감사까지 드러나지 않는다.
%
%   ⚠️ 돌리기 전에 zip 백업을 뜬다. `Copy-Item -Recurse` 는 260자를 넘는 경로에서
%      조용히 일부만 복사한다. `Compress-Archive` 를 쓴다.

    if nargin < 3, doIt = false; end
    if ~bdIsLoaded(root), load_system(root); end

    mdls = find_mdlrefs(root);
    for i = 1:numel(mdls)
        if ~bdIsLoaded(mdls{i}), load_system(mdls{i}); end
    end

    % 참조 모델 -> 그 모델을 가리키는 첫 ModelReference 블록 (구 규칙의 기준)
    %
    % 🔴 **최상위 모델 안에서만** 찾는다. 구 규칙이 그랬기 때문이다.
    %    참조 모델 내부에서까지 찾으면 옛 경로를 다르게 계산해 「옛 위치에 파일이
    %    없다」로 판단하고 조용히 건너뛴다. 실제로 그렇게 2건이 계획에서 빠졌다.
    %    `Debounce` 와 `Set_Control_Fault` 는 참조 모델 내부에서만 참조되므로
    %    구 규칙에서 `_간접참조모델\` 로 떨어졌고, 그 위치에 문서가 있다.
    refMap = containers.Map('KeyType','char','ValueType','char');
    mrRoot = find_system(root,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants, ...
                         'BlockType','ModelReference');
    for k = 1:numel(mrRoot)
        nm = get_param(mrRoot{k},'ModelName');
        if ~isKey(refMap, nm), refMap(nm) = mrRoot{k}; end
    end

    r    = sfroot;
    ch   = r.find('-isa','Stateflow.Chart');
    plan = {};
    for k = 1:numel(ch)
        cp    = char(ch(k).Path);
        parts = strsplit(cp,'/');
        owner = parts{1};
        if ~any(strcmp(owner, mdls)), continue; end
        if strcmp(owner, root),        continue; end   % 루트 모델의 Chart 는 자리가 그대로다
        tail = cellfun(@safeName, parts(2:end), 'uni', 0);

        if isKey(refMap, owner)
            oldBase = vault_segs(refMap(owner), modelOf(refMap(owner)));
        else
            oldBase = {'_간접참조모델', safeName(owner)};
        end
        newBase = vault_base(owner, root);

        oldSegs = [oldBase, tail];
        newSegs = [newBase, tail];
        if isequal(oldSegs, newSegs), continue; end

        o = fullfile(vaultDir, oldSegs{:}, [strjoin(oldSegs,'_') '.md']);
        n = fullfile(vaultDir, newSegs{:}, [strjoin(newSegs,'_') '.md']);

        % 옛 위치에 실제로 무언가 있을 때만 계획한다. 없으면 이미 옮긴 것이다.
        oldDir = fileparts(o);
        if ~isfile(o) && (~isfolder(oldDir) || isempty(dir(fullfile(oldDir,'*.md'))))
            continue
        end
        plan(end+1,:) = {o, n}; %#ok<AGROW>
    end

    if isempty(plan)
        fprintf('이동할 Chart 문서가 없다. 이미 규칙 R19 상태다.\n');
        return
    end

    fprintf('%s — Chart 문서 이동 %d건\n\n', tern(doIt,'실행','DRY RUN'), size(plan,1));
    for k = 1:size(plan,1)
        fprintf('  %s\n  → %s\n\n', rel(plan{k,1},vaultDir), rel(plan{k,2},vaultDir));
    end
    if ~doIt
        fprintf('실제로 옮기려면 세 번째 인자에 true 를 준다.\n');
        return
    end

    moved = 0;
    for k = 1:size(plan,1)
        src = plan{k,1}; dst = plan{k,2};
        srcDir = fileparts(src); dstDir = fileparts(dst);
        if ~isfolder(dstDir), mkdir(dstDir); end

        if isfile(src) && ~isfile(dst)
            [ok,msg] = movefile(src, dst);
            if ok, moved = moved + 1; else, fprintf('실패: %s (%s)\n', rel(src,vaultDir), msg); end
        end

        % 같은 폴더의 다른 문서도 함께 옮긴다. 정본만 옮기면 옛 폴더가 남아
        % 새 폴더와 공존하고, 폴더가 비지 않으니 정리에도 걸리지 않는다.
        if isfolder(srcDir)
            loose = dir(fullfile(srcDir,'*.md'));
            for j = 1:numel(loose)
                s2 = fullfile(loose(j).folder, loose(j).name);
                d2 = fullfile(dstDir, loose(j).name);
                if isfile(d2), continue; end
                [ok,~] = movefile(s2, d2);
                if ok, moved = moved + 1; fprintf('  (동반) %s\n', loose(j).name); end
            end
        end
    end
    fprintf('\n%d건 이동 완료.\n', moved);
    fprintf('빈 폴더 %d개 삭제.\n', rmEmpty(vaultDir));
end


% ══════════════════════════════════════════════════════
function m = modelOf(b)
    m = strtok(b, '/');
end

function s = rel(f, rootDir)
    s = strrep(strrep(f, [rootDir filesep], ''), '\', '/');
end

function s = tern(c,a,b)
    if c, s = a; else, s = b; end
end

function n = rmEmpty(rootDir)
    n = 0;
    for pass = 1:8
        d = dir(fullfile(rootDir,'**',filesep));
        removed = 0;
        for k = 1:numel(d)
            if ~d(k).isdir, continue; end
            if any(strcmp(d(k).name, {'.','..'})), continue; end
            f = fullfile(d(k).folder, d(k).name);
            e = dir(f); e = e(~ismember({e.name},{'.','..'}));
            if isempty(e), rmdir(f); removed = removed + 1; end
        end
        n = n + removed;
        if removed == 0, break; end
    end
end

function s = safeName(s)
    s = strtrim(strrep(s, newline, ' '));
    s = regexprep(s, '[<>:"/\\?*]', '_');
    s = regexprep(s, '\s+', '_');
end
