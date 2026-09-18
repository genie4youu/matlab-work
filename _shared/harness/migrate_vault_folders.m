function migrate_vault_folders(model, vaultDir, doIt)
%MIGRATE_VAULT_FOLDERS  기존 볼트 문서를 규칙 R13 폴더명으로 옮긴다.
%
%   migrate_vault_folders('ExampleModel', vaultDir, false)   % dry run (기본)
%   migrate_vault_folders('ExampleModel', vaultDir, true)    % 실제 이동
%
%   구(舊) 규칙 : 폴더명 = 블록 이름
%   신(新) 규칙 : 폴더명 = 블록 이름, 참조 블록이면 「블록이름-참조대상」
%
%   🔴 반드시 재생성(gen_vault_*) **전에** 돌린다.
%      재생성은 기존 문서에서 해석을 읽어 보존하는데, 그 「기존 문서」를
%      새 경로에서 찾는다. 옮기기 전에 재생성하면 해석을 못 찾고
%      자리표시자로 덮어쓴다.

    if nargin < 3, doIt = false; end
    if ~bdIsLoaded(model), load_system(model); end

    LIBMASK = {'Compare To Constant','Compare To Zero','Detect Change','Detect Increase'};
    ss = find_system(model,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants, ...
                     'BlockType','SubSystem');
    mr = find_system(model,'LookUnderMasks','all','FollowLinks','on','IncludeCommented','on','MatchFilter',@Simulink.match.allVariants, ...
                     'BlockType','ModelReference');

    blocks = {};
    for k = 1:numel(ss)
        mt = ''; try, mt = get_param(ss{k},'MaskType'); catch, end
        if any(strcmp(mt, LIBMASK)), continue; end
        blocks{end+1} = ss{k}; %#ok<AGROW>
    end
    for k = 1:numel(mr), blocks{end+1} = mr{k}; end %#ok<AGROW>

    % 참조 모델 -> ModelReference 블록 (Chart 위치 계산용)
    refMap = containers.Map('KeyType','char','ValueType','char');
    for k = 1:numel(mr)
        nm = get_param(mr{k},'ModelName');
        if ~isKey(refMap, nm), refMap(nm) = mr{k}; end
    end

    plan = {};   % {구경로, 신경로}

    for k = 1:numel(blocks)
        b       = blocks{k};
        oldSegs = oldSegsOf(b, model);
        newSegs = vault_segs(b, model);
        plan    = addPlan(plan, vaultDir, oldSegs, newSegs);
    end

    r  = sfroot;
    ch = r.find('-isa','Stateflow.Chart');
    for k = 1:numel(ch)
        cpth  = char(ch(k).Path);
        parts = strsplit(cpth,'/');
        owner = parts{1};
        tail  = cellfun(@safeName, parts(2:end), 'uni', 0);
        if isKey(refMap, owner)
            oldBase = oldSegsOf(refMap(owner), model);
            newBase = vault_segs(refMap(owner), model);
        else
            oldBase = {'_간접참조모델', safeName(owner)};
            newBase = oldBase;
        end
        plan = addPlan(plan, vaultDir, [oldBase tail], [newBase tail]);
    end

    % ── 보고 ─────────────────────────────────────────
    if isempty(plan)
        fprintf('이동할 문서가 없다. 이미 규칙 R13 상태다.\n');
        return
    end
    fprintf('%s — 이동 대상 %d건\n\n', tern(doIt,'실행','DRY RUN'), size(plan,1));
    for k = 1:size(plan,1)
        fprintf('  %s\n  → %s\n\n', rel(plan{k,1},vaultDir), rel(plan{k,2},vaultDir));
    end

    if ~doIt
        fprintf('실제로 옮기려면 세 번째 인자에 true 를 준다.\n');
        return
    end

    % ── 실행 ─────────────────────────────────────────
    moved = 0;
    for k = 1:size(plan,1)
        src = plan{k,1}; dst = plan{k,2};
        srcDir = fileparts(src); dstDir = fileparts(dst);
        if ~isfolder(dstDir), mkdir(dstDir); end

        % 1) 정본 문서 (이름이 폴더 경로를 평탄화한 것이라 함께 바뀐다)
        if isfile(src) && ~isfile(dst)
            [ok,msg] = movefile(src, dst);
            if ok, moved = moved + 1; else, fprintf('실패: %s (%s)\n', rel(src,vaultDir), msg); end
        end

        % 2) 같은 폴더의 다른 문서 (사람이 쓴 주제 문서). 이름은 그대로 둔다.
        %    🔴 초판은 정본 1개만 옮겨서 주제 문서 7개가 옛 폴더에 남았다.
        %       폴더가 비지 않으니 정리에도 안 걸려, 새 폴더와 옛 폴더가 공존했다.
        if isfolder(srcDir)
            loose = dir(fullfile(srcDir, '*.md'));
            for j = 1:numel(loose)
                s2 = fullfile(loose(j).folder, loose(j).name);
                d2 = fullfile(dstDir, loose(j).name);
                if isfile(d2), continue; end
                [ok,msg] = movefile(s2, d2);
                if ok
                    moved = moved + 1;
                    fprintf('  (동반) %s\n', loose(j).name);
                else
                    fprintf('실패: %s (%s)\n', rel(s2,vaultDir), msg);
                end
            end
        end
    end
    fprintf('\n%d건 이동 완료.\n', moved);

    n = rmEmpty(vaultDir);
    fprintf('빈 폴더 %d개 삭제.\n', n);
end


% ══════════════════════════════════════════════════════
function segs = oldSegsOf(b, model)
%OLDSEGSOF  구 규칙 — 블록 이름만 safeName 한다.
    r = strrep(strrep(b, [model '/'], ''), newline, ' ');
    segs = cellfun(@safeName, strsplit(r,'/'), 'uni', 0);
end

function plan = addPlan(plan, vaultDir, oldSegs, newSegs)
    if isequal(oldSegs, newSegs), return; end
    o = fullfile(vaultDir, oldSegs{:}, [strjoin(oldSegs,'_') '.md']);
    n = fullfile(vaultDir, newSegs{:}, [strjoin(newSegs,'_') '.md']);

    % 🔴 옛 위치에 실제로 무언가 있을 때만 계획한다.
    %    초판은 이 검사가 없어서 **이미 이전을 마친 뒤에도 같은 22건을 계속 계획**했다.
    %    「이동할 문서가 없다」가 영영 뜨지 않아, 이전이 남아 있는 것처럼 보였다.
    oldDir = fileparts(o);
    if ~isfile(o) && (~isfolder(oldDir) || isempty(dir(fullfile(oldDir,'*.md'))))
        return
    end
    plan(end+1,:) = {o, n};
end

function s = rel(f, root)
    s = strrep(strrep(f, [root filesep], ''), '\', '/');
end

function s = tern(c,a,b)
    if c, s = a; else, s = b; end
end

function n = rmEmpty(root)
%RMEMPTY  빈 폴더를 아래에서부터 지운다. 여러 번 돌아 중첩된 빈 폴더까지 없앤다.
    n = 0;
    for pass = 1:8
        d = dir(fullfile(root,'**',filesep));
        removed = 0;
        for k = 1:numel(d)
            if ~d(k).isdir, continue; end
            if any(strcmp(d(k).name, {'.','..'})), continue; end
            f = fullfile(d(k).folder, d(k).name);
            e = dir(f);
            e = e(~ismember({e.name},{'.','..'}));
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
