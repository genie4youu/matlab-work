function segs = vault_segs(b, model)
%VAULT_SEGS  Simulink 블록 경로 -> 볼트 폴더 세그먼트 (규칙 R13, 2026-08-04)
%
%   segs = vault_segs('ExampleModel/M1/Main_SF/Model', 'ExampleModel')
%       -> {'M1','Main_SF','Model-Example_Main_SF'}
%
%   규칙
%   ────
%   폴더명 = 블록 이름.
%   단 **참조 블록이면 「블록이름-참조대상」** 으로 짓는다.
%     - ModelReference : 참조대상 = ModelName
%     - SubSystem 중 ReferencedSubsystem 이 있는 것 = Subsystem Reference
%
%   왜 이렇게 정했나
%   ──────────────
%   모델 안에서 같은 종류의 블록 이름이 일관되지 않다. ModelReference 가
%   어떤 데선 `Model`(기본 이름), 어떤 데선 `PC_Ref_Gen` 이다. Subsystem
%   Reference 는 6개가 전부 기본 이름 `Subsystem Reference` 다.
%   폴더가 모델의 거울이므로 그 불일치가 그대로 복제되어, 폴더만 봐서는
%   `M1/Main_SF/Model/SF` 가 무엇인지 알 수 없었다.
%
%   블록 이름을 버리지 않고 참조 대상을 덧붙인다. 거울 원칙(블록 이름이
%   앞에 남는다)을 지키면서 폴더명만으로 정체가 드러난다.
%
%   🔴 이 함수는 gen_vault_tree · gen_vault_charts · audit_coverage 가
%      **공유한다.** 규칙이 한 곳에만 반영되면 감사가 영원히 실패한다.
%      이름 규칙을 바꾸려면 여기만 고치고 세 스크립트를 다시 돌린다.

    parts = strsplit(b, '/');
    segs  = cell(1, numel(parts)-1);      % parts{1} 은 모델 이름이라 폴더가 아니다
    for k = 2:numel(parts)
        segs{k-1} = vault_seg(strjoin(parts(1:k), '/'));
    end
end


function s = vault_seg(bp)
%VAULT_SEG  블록 경로 하나 -> 폴더명 한 조각.
    parts = strsplit(bp, '/');
    nm    = strrep(parts{end}, newline, ' ');

    tgt = '';
    bt  = ''; try, bt = get_param(bp, 'BlockType'); catch, end
    switch bt
        case 'ModelReference'
            try, tgt = get_param(bp, 'ModelName'); catch, end
        case 'SubSystem'
            % ReferencedSubsystem 이 비어 있지 않으면 Subsystem Reference 다.
            try, tgt = get_param(bp, 'ReferencedSubsystem'); catch, end
    end

    if isempty(tgt)
        s = safeName(nm);
    else
        s = [safeName(nm) '-' safeName(tgt)];
    end
end


function s = safeName(s)
    s = strtrim(strrep(s, newline, ' '));
    s = regexprep(s, '[<>:"/\\?*]', '_');
    s = regexprep(s, '\s+', '_');
end
