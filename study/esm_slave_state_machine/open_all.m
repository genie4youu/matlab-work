% open_all — 이 폴더의 네 모델(Esm_cur · Esm_ruflo · Esm_ecc · Esm_ref)을 나란히 연다.
%   _cur = 현행(Claude Code + 볼트 규칙) · _ruflo · _ecc · _ref = 검증 세션의 채점기 자가검사용 참조 모델
here = fileparts(mfilename('fullpath'));
addpath('C:\Users\leeyj\matlab-work\_shared\harness'); addpath('C:\Users\leeyj\matlab-work\_shared\harness\build');
names = {'Esm_ruflo', 'Esm_cur', 'Esm_ecc', 'Esm_ref'};
for i = 1:numel(names)
    if ~isfile(fullfile(here, [names{i} '.slx'])), continue; end
    open_system(fullfile(here, [names{i} '.slx']));
    ch = find_system(names{i}, 'SearchDepth', 1, 'BlockType', 'SubSystem', 'SFBlockType', 'Chart');
    if ~isempty(ch), open_system(ch{1}); end
end
fprintf('열림: %s\n', strjoin(names, ' · '));
