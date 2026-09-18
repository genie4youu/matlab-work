% open_all — 재대결 2026-09-17 의 세 모델을 나란히 연다 (보기 전용 사본).
%   Esm_cur = 현행(헤드리스) · Esm_ruflo = ruflo · Esm_ecc = ecc.  셋 다 숨은 시험 14/14 · 공개 3/3 · compare_spec 0.
%   각 쪽의 build/test/verify 스크립트를 원래 이름(Esm)으로 돌려 보려면 ..\재현\<쪽>\ 에서 한 쪽씩.
here = fileparts(mfilename('fullpath'));
addpath('C:\Users\leeyj\matlab-work\_shared\harness');
addpath('C:\Users\leeyj\matlab-work\_shared\harness\build');
names = {'Esm_ruflo', 'Esm_cur', 'Esm_ecc'};
for i = 1:numel(names)
    open_system(fullfile(here, [names{i} '.slx']));
    ch = find_system(names{i}, 'SearchDepth', 1, 'BlockType', 'SubSystem', 'SFBlockType', 'Chart');
    if ~isempty(ch), open_system(ch{1}); end
end
fprintf('\n열림: %s\n', strjoin(names, ' · '));
