function varargout = analyze(dateStr, varargin)
%ANALYZE  모델 분석을 한 줄로 시작한다. 점검 → 생성 → 감사 → 남은 일.
%
%   analyze                 날짜 폴더 목록을 보여준다
%   analyze 20260812        그 세션을 열고 전부 돌린다
%   analyze('20260812', 'Model','내모델')   루트 모델이 여럿일 때 지정
%   analyze('20260812', 'Gen',true)         트리를 강제로 재생성
%
%   하는 일 (순서가 곧 안전장치다)
%   ─────────────────────────────
%     1. session      날짜 폴더 + 공용 하네스를 경로에 올린다
%     2. preflight    전제와 이 모델의 함정을 점검한다      🔴 실패면 여기서 멈춘다
%     3. lint         하네스 코드가 규칙을 지키는가          🔴 실패면 여기서 멈춘다
%     4. selftest     검사기가 실제로 실패를 내는가          🔴 실패면 여기서 멈춘다
%     5. crosscheck   열거를 두 번째 경로로 다시 세서 대조    🔴 실패면 여기서 멈춘다
%     6. gen          볼트 트리·문서 생성 (첫 실행이거나 Gen=true 일 때만)
%     7. audit        판정 ①~⑤ 를 내고 **남은 일 목록**을 보여준다
%
%   🔴 2~5 중 하나라도 실패하면 6·7 을 하지 않는다.
%      도구나 전제가 틀린 상태로 만든 문서는 그럴듯하게 틀리기 때문이다.
%
%   왜 한 줄인가 (2026-08-05)
%   ────────────────────────
%   점검 명령을 사람이 손으로 나열하게 두면 언젠가 건너뛴다. 그리고 건너뛴 회차는
%   결과만 봐서는 구분되지 않는다. 순서와 중단 조건을 이 함수가 갖는다.

    % 결과는 **요청했을 때만** 돌려준다. 그러지 않으면 `analyze 20260804` 로 부를 때
    % 화면 끝에 `ans = logical 0` 이 붙어, 통과/실패 표시로 오해하기 쉽다.
    ok = false;

    if nargin < 1 || isempty(dateStr)
        session();   % 목록만 보여준다
        fprintf('\n  analyze 20260804   처럼 날짜를 주면 전부 돌립니다.\n\n');
        if nargout, varargout{1} = ok; end
        return
    end

    p = inputParser;
    p.addParameter('Model', '', @(x) ischar(x) || isstring(x));
    p.addParameter('Gen',   [], @(x) isempty(x) || islogical(x));
    p.parse(varargin{:});
    model = char(p.Results.Model);
    genOpt = p.Results.Gen;

    line('세션 열기');
    session(dateStr);
    c = vault_ctx(model);

    % ── 점검 3종 ──────────────────────────────────────
    line('전제 점검 (preflight)');
    okP = preflight(c.model);
    if ~okP, stop('전제가 깨져 있다', c); if nargout, varargout{1}=false; end, return; end

    line('하네스 검사 (lint_harness)');
    okL = lint_harness();
    if ~okL, stop('하네스 코드가 규칙을 어긴다', c); if nargout, varargout{1}=false; end, return; end

    line('검사기 자가 시험 (selftest_harness)');
    okS = selftest_harness(c.vault, c.model);
    if ~okS, stop('검사기가 죽어 있다', c); if nargout, varargout{1}=false; end, return; end

    % 열거원이 하나뿐이면 빠진 것을 볼 방법이 없다. 두 번째 경로로 다시 세고
    % 대조한다 (R26). 이 프로젝트의 실패는 매번 「열거 범위」에서 났다.
    line('열거 교차검증 (audit_crosscheck)');
    okX = audit_crosscheck(c.model);
    if ~okX, stop('두 열거원이 어긋난다', c); if nargout, varargout{1}=false; end, return; end

    % ── 생성 ──────────────────────────────────────────
    nDoc = 0;
    if isfolder(c.vault), nDoc = numel(dir(fullfile(c.vault,'**','*.md'))); end
    doGen = genOpt;
    if isempty(doGen), doGen = (nDoc == 0); end   % 첫 실행이면 자동 생성

    if doGen
        line('볼트 트리 생성');
        if nDoc > 0
            fprintf('  기존 문서 %d개 — 해석은 보존된다 (read_interp). 백업은 별도로 뜬다.\n', nDoc);
        end
        gen_vault_tree(c.model, c.vault);
        gen_vault_charts(c.model, c.vault);
    else
        line('볼트 트리');
        fprintf('  기존 문서 %d개를 그대로 쓴다. 재생성하려면 analyze(''%s'',''Gen'',true)\n', nDoc, c.date);
    end

    % ── 감사 ──────────────────────────────────────────
    line('감사');
    if ~isfolder(c.out), mkdir(c.out); end
    covFile = fullfile(c.out, 'coverage.md');
    elFile  = fullfile(c.out, 'elements.md');
    audit_coverage(c.model, c.vault, covFile);
    audit_elements(c.vault, elFile, c.model);

    % ── 남은 일 ───────────────────────────────────────
    line('결과');
    txt = read_utf8(covFile);
    i = strfind(txt, '## 4. 결과');
    if isempty(i)
        fprintf('  감사 출력 형식이 바뀌었다. %s 를 직접 본다.\n', covFile);
        if nargout, varargout{1} = false; end
        return
    end
    s = txt(i:end);
    j = strfind(s, '**②');
    if isempty(j), j = numel(s); end
    fprintf('%s', s(1:j(1)-1));

    ok = ~contains(s, '실패');
    if nargout, varargout{1} = ok; end
    if ok
        fprintf('\n  분석 완료. 모델이 바뀌면 analyze(''%s'',''Gen'',true) 로 다시 돌린다.\n\n', c.date);
    else
        fprintf('  남은 일 목록: %s\n', covFile);
        fprintf('  원소 감사    : %s\n\n', elFile);
        fprintf('  다음: 실패 목록 **맨 위 하나**를 골라 그 컨테이너의 덤프를 열고 해석을 쓴다 (R14).\n');
        fprintf('        한 세션 4~6개가 상한이다. 다 쓰면 analyze(''%s'') 로 다시 확인한다.\n\n', c.date);
    end
end


function line(t)
    fprintf('\n──────── %s ────────\n', t);
end

function stop(why, c)
    fprintf('\n');
    fprintf('🔴 %s. 여기서 멈춘다.\n\n', why);
    fprintf('   문서를 만들지 않는다 — 도구나 전제가 틀린 상태로 만든 문서는\n');
    fprintf('   오류 없이 그럴듯하게 틀리고, 나중에 구분할 수 없다.\n\n');
    fprintf('   위 출력의 실패 항목을 먼저 고친 뒤 analyze(''%s'') 를 다시 돌린다.\n\n', c.date);
end
