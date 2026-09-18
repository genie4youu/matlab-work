function ctx = vault_ctx(model)
%VAULT_CTX  이번 분석 세션의 맥락을 **현재 작업 폴더에서 도출한다.**
%
%   ctx = vault_ctx()            루트 모델을 자동으로 찾는다
%   ctx = vault_ctx('ExampleModel') 루트 모델을 지정한다
%
%   돌려주는 것
%     ctx.date     '20260804'          날짜 폴더 이름 그대로
%     ctx.iso      '2026-08-04'        문서 frontmatter 용
%     ctx.dir      세션 폴더 절대경로 (모델이 있는 곳)
%     ctx.vault    볼트 서브시스템 폴더 절대경로
%     ctx.wiki     'work/sessions/20260804/서브시스템'   위키링크 접두
%     ctx.model    루트 모델 이름
%     ctx.out      '_분석출력' 절대경로
%
%   왜 필요한가 (2026-08-05)
%   ──────────────────────
%   하네스가 `20260804` 과 `ExampleModel` 을 **문자열로 박고 있었다.**
%   그래서 새 날짜 폴더에서 돌리면 조용히 틀린다.
%
%     - `gen_vault_tree` 가 새 문서에 `세션: "20260804"` 과
%       `[[work/sessions/20260804/...]]` 링크를 박는다 → 엉뚱한 날짜를 가리킨다
%     - `audit_elements` 는 인자를 무시하고 늘 `ExampleModel` 을 감사한다
%       → **다른 모델을 감사하라고 해도 옛 모델을 감사한다**
%
%   둘 다 오류를 내지 않는다. 결과가 그럴듯하게 나오고 사람이 알아채기 어렵다.
%   그래서 맥락을 한 곳에서만 정한다 (vault_segs 가 폴더명 규칙의 단일 정의인 것과 같다).
%
%   🔴 날짜 폴더 이름은 볼트 쪽과 **문자 그대로 같아야 한다.** 그것이 이 함수의 전제다.

    VAULT_ROOT = fullfile('C:','Users','leeyj','Documents','yj.lee');

    ctx.dir = pwd;
    [~, ctx.date] = fileparts(ctx.dir);

    if isempty(regexp(ctx.date, '^(\d{8}|\d{4}-\d{2}-\d{2})$', 'once'))
        error('vault_ctx:notSession', ...
            ['현재 폴더가 날짜 폴더가 아닙니다: %s\n' ...
             '        session(''20260804'') 처럼 세션을 먼저 엽니다.'], ctx.dir);
    end

    d = regexprep(ctx.date, '\D', '');
    ctx.iso = sprintf('%s-%s-%s', d(1:4), d(5:6), d(7:8));

    % 🔴 2026-08-10: 볼트에서 sessions/ 가 work/ 밑에서 work/projects/ 밑으로 이동했다.
    %    여기를 안 고치면 하네스가 없어진 work/sessions/ 를 **다시 만들어** 문서를 쏟는다.
    %    (오류가 나지 않는다 — 조용히 엉뚱한 곳에 쌓인다)
    ctx.vault = fullfile(VAULT_ROOT, 'work', 'projects', 'sessions', ctx.date, '서브시스템');
    ctx.wiki  = sprintf('work/projects/sessions/%s/서브시스템', ctx.date);
    ctx.out   = fullfile(ctx.dir, '_분석출력');

    ensure_path(ctx.dir);

    if nargin >= 1 && ~isempty(model)
        ctx.model = model;
    else
        ctx.model = findRoot(ctx.dir);
    end
end


function m = findRoot(sessionDir)
%FINDROOT  세션 폴더 **최상위**의 모델을 루트로 본다.
%   하위 폴더(라이브러리)는 보지 않는다. `00. Lib` 에 40개가 넘게 있어서
%   재귀로 찾으면 어느 것이 루트인지 알 수 없다.
    f = [dir(fullfile(sessionDir,'*.slx')); dir(fullfile(sessionDir,'*.mdl'))];
    f = f(~[f.isdir]);
    if isempty(f)
        error('vault_ctx:noModel', ...
            ['세션 폴더 최상위에 모델(.slx/.mdl)이 없습니다: %s\n' ...
             '        루트 모델을 인자로 지정합니다: vault_ctx(''모델이름'')'], sessionDir);
    end
    if numel(f) > 1
        names = strjoin(cellfun(@(x) x, {f.name}, 'uni', 0), ', ');
        error('vault_ctx:manyModels', ...
            ['세션 폴더 최상위에 모델이 %d개입니다: %s\n' ...
             '        어느 것이 루트인지 기계가 정할 수 없습니다. 인자로 지정합니다.'], ...
            numel(f), names);
    end
    [~, m] = fileparts(f(1).name);
end
