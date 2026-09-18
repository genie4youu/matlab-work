function ensure_path(sessionDir)
%ENSURE_PATH  세션 폴더의 모델·딕셔너리 경로를 MATLAB 경로에 올린다.
%
%   ensure_path()             현재 폴더를 세션 폴더로 본다
%   ensure_path(sessionDir)   명시
%
%   왜 별도 함수인가 (2026-08-05)
%   ────────────────────────────
%   경로 등록이 `run_ExampleModel.m` 안에만 있었다. 그래서 그 스크립트를 거치지
%   않고 하네스를 부르면 참조 모델을 못 찾는다. 실제로 발생했고 `find_mdlrefs` 가
%   오류를 냈다.
%
%   🔴 오류가 난 것은 **다행**이다. 조용히 적게 열거됐다면 감사는 통과했을 것이고,
%      참조 모델 12개가 통째로 빠진 채 「분석 완료」가 나왔을 것이다 (R18 과 같은 계열).
%
%   ⚠️ 초판은 `mfilename('fullpath')` 로 자기 위치를 기준 삼았다. 하네스를
%      `_shared\harness\` 로 옮기면서 그 전제가 깨진다. 이제 **세션 폴더**를 받는다.
%
%   딕셔너리·라이브러리 폴더 이름은 회사 자료 구조를 따른다. 없으면 건너뛴다.
%   비재귀로 올린다 — `00. Lib\temp\` 에 소문자 이름의 옛 사본이 40개 있어서
%   재귀로 올리면 어느 쪽이 잡힐지 예측할 수 없다.

    if nargin < 1 || isempty(sessionDir), sessionDir = pwd; end

    cand = {sessionDir};
    for sub = {fullfile('ModelDictionary','00. Dic'), fullfile('ModelDictionary','00. Lib')}
        cand{end+1} = fullfile(sessionDir, sub{1}); %#ok<AGROW>
    end

    add = {};
    cur = [pathsep path pathsep];
    for k = 1:numel(cand)
        d = cand{k};
        if isfolder(d) && ~contains(cur, [pathsep d pathsep])
            add{end+1} = d; %#ok<AGROW>
        end
    end
    if ~isempty(add)
        addpath(add{:});
        rel = cellfun(@(x) strrep(x, [sessionDir filesep], ''), add, 'uni', 0);
        rel(strcmp(rel, sessionDir)) = {'(세션 폴더)'};
        fprintf('경로 등록: %s\n', strjoin(rel, ' / '));
    end
end
