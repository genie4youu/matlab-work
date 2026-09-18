function body = read_interp(path)
%READ_INTERP  기존 문서의 `## N. 해석` 절 본문을 읽어온다. 없으면 빈 문자열.
%
%   왜 필요한가
%   ──────────
%   `gen_vault_tree` / `gen_vault_charts` 는 모델이 바뀌면 다시 돌린다.
%   그런데 초판은 문서를 통째로 새로 썼다. 즉 **재생성이 사람이 쓴 해석을 지운다.**
%   해석 51개를 써둔 상태에서 모델이 하나 바뀌어 재생성하면 51개가 모두 날아간다.
%   지워졌다는 사실은 커버리지 감사가 다음에 돌 때까지 드러나지 않는다.
%
%   그래서 재생성은 기계 추출 부분만 갱신하고 해석 절은 **읽어서 다시 붙인다.**
%
%   자리표시자는 보존 대상이 아니다 (빈 문자열로 취급).

    body = '';
    if ~isfile(path), return; end
    % 🔴 fileread 를 쓰지 않는다. BMP 밖 문자(이모지)를 조용히 지운다 → read_utf8.m
    txt = read_utf8(path);
    i = regexp(txt, '##\s*\d*\.?\s*해석', 'once');
    if isempty(i), return; end
    b = txt(i:end);
    b = regexprep(b, '^##[^\n]*\n', '');     % 제목 줄 제거
    b = regexprep(b, '\n---[\s\S]*$', '');   % 하단 구분선 이후 제거
    b = strtrim(b);
    if contains(b, '아직 채우지 않았다'), return; end
    body = b;
end
