function segs = vault_base(M, root)
%VAULT_BASE  모델 하나가 볼트의 어디에 놓이는지 (규칙 R19, 2026-08-05)
%
%   vault_base('ExampleModel','ExampleModel')  -> {}                          (루트)
%   vault_base('Debounce',   'ExampleModel') -> {'_참조모델','Debounce'}
%
%   왜 참조 모델을 계층에 끼워넣지 않나
%   ────────────────────────────────
%   R10 의 「폴더는 모델 계층의 거울」은 **한 모델 안에서** 성립하는 규칙이다.
%   모델 경계를 넘으면 거울이 성립하지 않는다. 이유가 둘이다.
%
%     (1) 참조 모델은 여러 곳에서 참조된다. `Debounce8` 은 `Debounce` 를 8번
%         참조한다. 거울대로라면 같은 내용의 폴더가 8개 생긴다. 실제로는
%         「최초 참조 블록 아래 한 번만」 두고 있었으므로 이미 거울이 아니었다.
%     (2) 경로가 Windows 한계를 넘는다. 참조 블록 아래로 끼워넣어 실측하면
%         최장 **287자**로 260을 넘겼다. `_참조모델\<모델명>\` 아래에 두면 **199자**다.
%         (R13 이 경고한 지점이 실제로 터진 것이다.)
%
%   참조 모델은 **그 자체가 파일**이므로 파일 단위로 문서화한다. 계층 안의
%   ModelReference 블록 문서는 포트 배선을 담고, 내부는 이 폴더를 가리킨다.
%
%   🔴 `vault_segs.m`(R13) 과 짝을 이루는 단일 정의다. 놓이는 위치를
%      스크립트마다 옮겨 적지 않는다.

    if strcmp(M, root)
        segs = {};
    else
        segs = {'_참조모델', safeName(M)};
    end
end


function s = safeName(s)
    s = strtrim(strrep(s, newline, ' '));
    s = regexprep(s, '[<>:"/\\?*]', '_');
    s = regexprep(s, '\s+', '_');
end
