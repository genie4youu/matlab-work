function C = public_cases()
%PUBLIC_CASES  과제에 공개하는 수용 시험 3개. 각 행 = 한 틱의 [req ack].
    C = struct('name', {}, 'in', {});
    % T1 기동·하강: Init→PreOp→SafeOp→Op→SafeOp→Init
    C(end+1) = struct('name','T1_기동하강', 'in', [2 0; 0 0; 4 0; 8 0; 8 0; 4 0; 1 0]);
    % T2 불법 요청: Init→Op 불허 → err, ack 로 해제 뒤 PreOp
    C(end+1) = struct('name','T2_불법요청', 'in', [8 0; 0 0; 0 1; 2 0; 0 0]);
    % T3 오류 중 요청: PreOp 에서 Op 요청(불법) → err, err 중 SafeOp 요청(합법)은 무시, Init 요청은 통과, ack 와 요청 같은 틱
    C(end+1) = struct('name','T3_오류중요청', 'in', [2 0; 8 0; 4 0; 1 0; 2 1; 4 0]);
end
