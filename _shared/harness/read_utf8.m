function txt = read_utf8(path)
%READ_UTF8  파일을 UTF-8 로 안전하게 읽는다.
%
%   왜 fileread 를 쓰지 않나 (2026-08-05 실측)
%   ────────────────────────────────────────
%   `fileread` 는 **BMP(U+FFFF) 밖 문자를 조용히 지운다.** 대부분의 컬러
%   이모지가 여기 해당한다. 실측:
%
%     원본  '🔴 빨강 ① 원문자 ⚠️ 경고 — em dash'   (38자)
%     회수  '  빨강 ① 원문자 ⚠️ 경고 — em dash'    (37자)  ← 🔴 소실
%
%   ⚠️ 소실은 **첫 읽기에서만** 일어나고 두 번째 왕복부터는 안정적이다.
%      즉 재생성을 한 번 돌린 뒤에는 「원래 그랬던 것」처럼 보인다.
%      해석을 회수해 되쓰는 경로(read_interp)에 이 함수가 없으면
%      재생성할 때마다 문서에서 문자가 조용히 사라진다.
%
%   ① ⚠️ — 같은 BMP 안의 기호와 em dash 는 영향이 없다.

    fid = fopen(path, 'r');
    if fid < 0
        error('read_utf8:open', '열 수 없다: %s', path);
    end
    oc  = onCleanup(@() fclose(fid));
    raw = fread(fid, Inf, '*uint8')';

    % UTF-8 BOM(EF BB BF)을 걷어낸다.
    %   PowerShell 로 만든 파일에는 BOM 이 붙는다 (`.ps1` 은 BOM 이 필수라 습관이 된다).
    %   BOM 이 남으면 첫 줄이 U+FEFF 로 시작해 `startsWith(L,'#')` 같은 검사가 조용히
    %   빗나간다. 실제로 `_회귀고정.txt` 의 주석 첫 줄이 항목으로 읽혀 오탐이 났다.
    if numel(raw) >= 3 && isequal(raw(1:3), uint8([239 187 191]))
        raw = raw(4:end);
    end

    txt = native2unicode(raw, 'UTF-8');
end
