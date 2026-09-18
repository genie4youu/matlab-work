function [st, err, outEn] = esm_ref(req, ack)
%ESM_REF  기준 구현 — 과제 `## 과제` 의 틱 규칙을 그대로 옮긴 순수 MATLAB. 채점의 정본.
%   [st, err, outEn] = esm_ref(req, ack)   입력 두 열벡터(N×1) → 출력 세 열벡터(N×1), k번째 = k번째 틱 뒤의 출력
%   규칙(틱마다 이 순서):
%     0. 초기: st=1(Init), err=0
%     1. ack==1 이면 err=0
%     2. 요청: req~=0 && req~=st 이면
%          err==1 && req~=1  → 무시
%          (st,req) 허용     → st=req
%          그 밖             → err=1 (st 유지)
%     3. outEn = (st==8)
    allowed = [1 2; 2 1; 2 4; 4 1; 4 2; 4 8; 8 1; 8 2; 8 4];
    N = numel(req); st = zeros(N,1); err = zeros(N,1); outEn = zeros(N,1);
    s = 1; e = 0;
    for k = 1:N
        if ack(k), e = 0; end
        r = req(k);
        if r ~= 0 && r ~= s
            if e == 1 && r ~= 1
                % 무시
            elseif any(allowed(:,1) == s & allowed(:,2) == r)
                s = r;
            else
                e = 1;
            end
        end
        st(k) = s; err(k) = e; outEn(k) = (s == 8);
    end
end
