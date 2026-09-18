function session(dateStr)
%SESSION  날짜별 작업 폴더 하나만 골라서 연다.
%
%   session('20260804')   해당 날짜 폴더로 이동하고 그 폴더만 경로에 올린다
%   session               쓸 수 있는 날짜 목록을 보여준다
%
%   찾는 위치 두 곳 (둘 다 지원):
%     C:\Users\leeyj\matlab-work\20260804\
%     C:\Users\leeyj\matlab-work\sessions\2026-08-05\
%
%   왜 이렇게 하나:
%     날짜 폴더를 전부 경로에 올리면, 같은 이름의 모델이 여러 날짜에 있을 때
%     MATLAB 이 경로 순서대로 아무거나 집는다. 경고가 안 나서 알아채기 어렵다.
%     ("고쳤는데 안 바뀐다" 의 전형적 원인)
%     그래서 startup.m 은 날짜 폴더를 제외하고, 이 함수가 하나만 올린다.
%
%   이전에 올렸던 날짜 폴더는 자동으로 경로에서 내려간다.

    WORKROOT = fullfile('C:', 'Users', 'leeyj', 'matlab-work');
    SESSIONS = fullfile(WORKROOT, 'sessions');
    PAT      = '^(\d{8}|\d{4}-\d{2}-\d{2})$';

    % ── 후보 날짜 폴더 모으기 ──────────────────────────
    cand = {};
    for base = {WORKROOT, SESSIONS}
        if ~isfolder(base{1}), continue; end
        d = dir(base{1});
        d = d([d.isdir]);
        for k = 1:numel(d)
            if ~isempty(regexp(d(k).name, PAT, 'once'))
                cand{end+1} = fullfile(base{1}, d(k).name); %#ok<AGROW>
            end
        end
    end

    % ── 인자가 없으면 목록만 ───────────────────────────
    if nargin < 1
        if isempty(cand)
            fprintf('날짜 폴더가 없습니다.\n');
            fprintf('  %s 아래에 20260804 같은 폴더를 만드세요.\n', WORKROOT);
            return
        end
        fprintf('쓸 수 있는 날짜 폴더:\n');
        for k = 1:numel(cand)
            [~, nm] = fileparts(cand{k});
            fprintf('  session(''%s'')\n', nm);
        end
        return
    end

    % ── 지정한 날짜 찾기 ───────────────────────────────
    target = '';
    for k = 1:numel(cand)
        [~, nm] = fileparts(cand{k});
        if strcmp(nm, dateStr)
            target = cand{k};
            break
        end
    end
    if isempty(target)
        error('session:notFound', ...
            ['날짜 폴더를 찾지 못했습니다: %s\n' ...
             '        session 이라고만 입력하면 목록을 볼 수 있습니다.'], dateStr);
    end

    % ── 이전 날짜 폴더를 경로에서 내린다 (충돌 방지) ───
    old = strsplit(path, pathsep);
    drop = false(size(old));
    for k = 1:numel(old)
        rel = strrep(strrep(old{k}, [SESSIONS filesep], ''), [WORKROOT filesep], '');
        seg = strtok(rel, filesep);
        drop(k) = ~isempty(regexp(seg, PAT, 'once'));
    end
    if any(drop)
        rmpath(strjoin(old(drop), pathsep));
    end

    % ── 이번 날짜만 올린다 (빌드 찌꺼기 제외) ──────────
    skip = {'codegen', 'slprj', '_ert_rtw', '_grt_rtw', '_sfun_rtw', '.git', 'html'};
    entries = strsplit(genpath(target), pathsep);
    entries = entries(~cellfun(@isempty, entries));
    keep = entries(~contains(entries, skip));

    addpath(strjoin(keep, pathsep));

    % 분석 하네스는 날짜와 무관하게 늘 같은 것을 쓴다 (_shared\harness).
    % 날짜 폴더마다 복사하면 갈라지고, 갈라지면 감사가 영원히 실패하거나 영원히 통과한다.
    HARNESS = fullfile(WORKROOT, '_shared', 'harness');
    if isfolder(HARNESS) && ~contains([pathsep path pathsep], [pathsep HARNESS pathsep])
        addpath(HARNESS);
    end

    cd(target);

    fprintf('작업 세션: %s\n', dateStr);
    fprintf('  폴더: %s\n', target);
    fprintf('  경로 %d개 등록 (빌드 산출물 %d개 제외)\n', ...
        numel(keep), numel(entries) - numel(keep));

    % ── 안에 뭐가 있는지 요약 ──────────────────────────
    models = [dir(fullfile(target, '**', '*.slx')); dir(fullfile(target, '**', '*.mdl'))];
    dicts  = dir(fullfile(target, '**', '*.sldd'));

    if isempty(models)
        fprintf('  ⚠ 모델 파일(.slx/.mdl)이 없습니다.\n');
    else
        fprintf('  모델 %d개', numel(models));
        if ~isempty(dicts)
            fprintf(' / 데이터 딕셔너리 %d개', numel(dicts));
        end
        fprintf('\n');

        % 최상위에 있는 모델만 이름을 찍는다 (라이브러리는 수가 많다)
        top = models(strcmp({models.folder}, target));
        for k = 1:numel(top)
            fprintf('    최상위: %s\n', top(k).name);
        end
        if numel(models) > numel(top)
            fprintf('    (하위 폴더에 %d개 더 — dir(''**/*.slx'') 로 확인)\n', ...
                numel(models) - numel(top));
        end
    end

    % ── 경로에 위험 문자가 있으면 경고 ─────────────────
    bad = keep(~cellfun(@(p) isempty(regexp(p, '[^\x20-\x7E]|\s', 'once')), keep));
    if ~isempty(bad)
        fprintf(2, '  ⚠ 공백·비ASCII 가 든 경로 %d개 — 코드 생성 시 깨질 수 있습니다:\n', numel(bad));
        for k = 1:min(3, numel(bad))
            fprintf(2, '      %s\n', strrep(bad{k}, [target filesep], ''));
        end
    end
end
