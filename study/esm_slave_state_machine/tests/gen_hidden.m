function gen_hidden()
%GEN_HIDDEN  숨은 시험 — 무작위 10 + 방향 4 = 14 시퀀스. 기대 출력은 esm_ref 가 낸다. hidden_cases.mat 로 저장.
    here = fileparts(mfilename('fullpath'));
    rng(20260917, 'twister');
    C = struct('name', {}, 'in', {}, 'exp', {});
    reqPool = [0 0 0 0 0 1 2 4 8];          % 0 이 55%
    for i = 1:10
        N = 25;
        req = reshape(reqPool(randi(numel(reqPool), N, 1)), N, 1);
        ack = double(rand(N,1) < 0.25);
        C(end+1) = mk(sprintf('R%02d', i), [req ack]); %#ok<AGROW>
    end
    % 방향 시험 — 규칙의 모서리
    C(end+1) = mk('D1_ack와_요청_같은틱',   [8 0; 2 1; 0 0; 8 1; 4 0]);                 % 불법→err · ack+합법 요청 같은 틱 통과 · ack+불법 요청 → 다시 err
    C(end+1) = mk('D2_req_유지',           [2 0; 2 0; 4 0; 4 0; 8 0; 8 0; 8 1; 1 0; 1 0]); % 유지해도 재트리거 없음, Op 에서 Init 직행
    C(end+1) = mk('D3_연속_불법',          [4 0; 8 0; 2 0; 0 1; 4 0; 0 0; 8 0; 1 1; 2 0]); % Init 에서 4·8 불법(err 유지) · err 중 2 무시 · ack 뒤 4 불법 · 8 무시 · ack+1 통과 · 2
    C(end+1) = mk('D4_Op_왕복',            [2 0; 4 0; 8 0; 2 0; 4 0; 8 0; 1 0; 2 0; 8 0; 0 1; 4 0; 8 0]); % Op→PreOp 허용 · Init 에서 8 불법 → err · ack · 정상 재상승
    save(fullfile(here, 'hidden_cases.mat'), 'C');
    fprintf('hidden cases: %d (ticks total %d)\n', numel(C), sum(arrayfun(@(c) size(c.in,1), C)));
end

function c = mk(name, in)
    [st, err, oe] = esm_ref(in(:,1), in(:,2));
    c = struct('name', name, 'in', in, 'exp', [st err oe]);
end
