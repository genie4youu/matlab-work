function varargout = build(dateStr, varargin)
%BUILD  저작 회차를 한 줄로 시작한다. 점검 → 덤프 → 그래프 → 전이표.
%
%   build                        날짜 폴더 목록을 보여준다
%   build 20260804               그 세션을 열고 전부 돌린다
%   build('20260804','Model','내모델')     루트 모델이 여럿일 때 지정
%   build('20260804','Verify',true)        🔴 저작 없이 **감사만** 돈다
%   build('20260804','Compile',true)       타입 수집 때 컴파일까지 시도 (느리다)
%
%   하는 일 (순서가 곧 안전장치다)
%   ─────────────────────────────
%     1. session          날짜 폴더 + 공용 하네스를 경로에 올린다
%     2. build_preflight  저작 전제 P1~P9                    🔴 실패면 멈춘다
%     3. lint_harness     하네스 코드가 규칙을 지키는가        🔴 실패면 멈춘다
%     4. emit_dump        Chart 를 JSON 으로 (에이전트가 읽을 기질)
%     5. emit_graph       ⓐ영향범위 · ⓑ구조검증
%     6. collect_types    타입 계약
%     7. emit_transtable  손 변환용 전이표
%
%   🔴 2·3 중 하나라도 실패하면 4~7 을 하지 않는다.
%      전제나 도구가 틀린 상태로 만든 덤프는 오류 없이 그럴듯하게 틀리고,
%      그 위에서 에이전트가 판단하면 틀린 근거로 옳아 보이는 결론이 나온다.
%
%   왜 한 줄인가 (R25 를 저작 쪽으로 옮긴 것)
%   ────────────────────────────────────────
%   점검 명령을 사람이 손으로 나열하게 두면 언젠가 건너뛴다. 그리고 건너뛴 회차는
%   결과만 봐서는 구분되지 않는다. 순서와 중단 조건을 이 함수가 갖는다.
%
%   Verify 모드 (R16)
%   ────────────────
%   「검증은 쓴 세션이 하지 않는다」의 수단이다. 다음 세션이 `build('<날짜>','Verify',true)`
%   로 들어오면 **덤프를 다시 만들지 않고** 기존 산출물만 감사한다. 진입점이 하나뿐이면
%   검증하러 온 세션이 실수로 회차를 새로 열어 산출물을 덮어쓴다.
%
%   ⚠️ 아직 **저작 단계(emit_ops / apply_ops)가 없다.** 지금 build 는
%      「모델을 읽어 기질을 만들고 감사한다」까지다. 저작을 붙이기 전에는
%      이 함수가 모델을 바꾸지 않는다 — 그 사실을 결과에 명시한다.

    ok = false;

    if nargin < 1 || isempty(dateStr)
        session();
        fprintf('\n  build 20260804   처럼 날짜를 주면 전부 돌립니다.\n');
        fprintf('  build(''20260804'',''Verify'',true)  는 감사만 돕니다 (R16).\n\n');
        if nargout, varargout{1} = ok; end
        return
    end

    p = inputParser;
    p.addParameter('Model',   '',    @(x) ischar(x) || isstring(x));
    p.addParameter('Verify',  false, @islogical);
    p.addParameter('Compile', false, @islogical);
    p.parse(varargin{:});
    model    = char(p.Results.Model);
    verify   = p.Results.Verify;
    doCompile = p.Results.Compile;

    line('세션 열기');
    session(dateStr);
    c = vault_ctx(model);
    dumpDir = fullfile(pwd, '_덤프');

    % ── 점검 ──────────────────────────────────────────
    % 🔴 저작 단계(emit_ops / apply_ops)는 아직 없다. 이 상수가 true 가 되는 날
    %    P5(블록 정책)가 정지 관문으로 켜진다. 지금 켜면 읽기만 하는 회차를 막는
    %    오탐이 되고, 오탐이 잦으면 검사 전체를 무시하게 된다.
    AUTHORING_IMPLEMENTED = false;
    willAuthor = AUTHORING_IMPLEMENTED && ~verify;

    line('저작 전제 점검 (build_preflight)');
    [okP, rep] = build_preflight(c.model, struct('Authoring', willAuthor));
    if ~okP
        stop('저작 전제가 깨져 있다', dateStr);
        if nargout, varargout{1} = false; end
        return
    end

    line('하네스 검사 (lint_harness)');
    okL = true;
    try
        okL = lint_harness();
    catch e
        fprintf('  ⚠ lint_harness 를 돌리지 못했다: %s\n', e.message);
        fprintf('    (저작 하네스는 `build\\` 하위라 기존 lint 대상이 아닐 수 있다)\n');
    end
    if ~okL
        stop('하네스 코드가 규칙을 어긴다', dateStr);
        if nargout, varargout{1} = false; end
        return
    end

    % ── 저작 (미구현) ─────────────────────────────────
    if ~verify
        line('저작');
        fprintf('  ⓘ `build` 자체는 **모델을 바꾸지 않는다.** 읽어서 기질을 만들고 감사만 한다.\n');
        fprintf('    저작은 계획과 적용을 나눠 **따로** 부른다 — 승인을 구조로 만들기 위해서다:\n');
        fprintf('      emit_ops(spec)              계획만 낸다 (ops.json)\n');
        fprintf('      apply_ops(ops, ''Dry'',true)  관문 확인 + 무엇이 적용될지 미리 본다\n');
        fprintf('      apply_ops(ops)              관문 통과 시 메인이 model_edit 으로 적용\n');
    end

    % ── 덤프 ──────────────────────────────────────────
    if verify && isfolder(dumpDir) && isfile(fullfile(dumpDir,'nodes.json'))
        line('덤프 (Verify — 기존 산출물을 그대로 쓴다)');
        fprintf('  %s 를 다시 만들지 않는다.\n', dumpDir);
    else
        line('덤프 (emit_dump)');
        emit_dump(c.model, dumpDir);
    end

    % ── 감사 ──────────────────────────────────────────
    line('그래프 판정 (emit_graph)');
    G = emit_graph(dumpDir);

    line('타입 계약 (collect_types)');
    T = collect_types(c.model, struct('Compile', doCompile));
    % 🔴 2026-09-08 결함 수정 (model-auditor·safety-refuter 가 각자 지적).
    %    `전이표.md` 가 7개 Chart 전부에서 「Data 상세는 types.json 이 정본」이라
    %    적는데 **그 파일이 없었다.** 손 변환 사양의 타입 근거가 0/123 이었다.
    %    문서가 가리키는 곳에 파일이 없으면 그 문서는 근거가 없는 것이다.
    typesFile = fullfile(dumpDir, 'types.json');
    fid = fopen(typesFile, 'w', 'n', 'UTF-8');
    if fid > 0
        cl = onCleanup(@() fclose(fid)); %#ok<NASGU>
        fwrite(fid, unicode2native(jsonencode(T,'PrettyPrint',true),'UTF-8'), 'uint8');
        clear cl
        fprintf('  → %s\n', typesFile);
    else
        fprintf('  ⚠ types.json 을 쓰지 못했다 — 전이표가 가리키는 정본이 비게 된다\n');
    end

    % 🔴 Chart 안쪽만 담으면 **모델 사이가 끊긴다.** 실측(2026-09-08): 모델 간 연결이
    %    신호선이 아니라 **Data Store** 로 이뤄져서, 에이전트가 비트마스크로 추정할
    %    수밖에 없었다. 신호선·Goto·Data Store·Chart 포트 매핑을 함께 담는다.
    line('신호선·경계 매핑 (collect_lines)');
    LN = collect_lines(c.model);
    linesFile = fullfile(dumpDir, 'lines.json');
    fid = fopen(linesFile, 'w', 'n', 'UTF-8');
    if fid > 0
        cl2 = onCleanup(@() fclose(fid)); %#ok<NASGU>
        fwrite(fid, unicode2native(jsonencode(LN,'PrettyPrint',true),'UTF-8'), 'uint8');
        clear cl2
        fprintf('  → %s\n', linesFile);
    else
        fprintf('  ⚠ lines.json 을 쓰지 못했다 — Chart 경계를 넘는 추적이 불가능해진다\n');
    end

    line('손 변환 전이표 (emit_transtable)');
    ttFile = emit_transtable(dumpDir);

    % ── 결과 ──────────────────────────────────────────
    line('결과');
    fprintf('  덤프      : %s\n', dumpDir);
    fprintf('  전이표    : %s\n', ttFile);
    fprintf('  그래프    : %d 검사 / %d 지적 (병렬이라 제외 %d)\n', ...
        G.checked, G.violations, G.skipped);
    fprintf('  타입      : 포트 %d · 전역신호 %d · 변환 %d · ChartData %d\n', ...
        T.counts.ports, T.counts.signals, T.counts.conversions, T.counts.chartData);
    fprintf('  배선      : 라인 %d · Goto %d · DataStore %d · Chart포트 %d\n', ...
        LN.counts.lines, LN.counts.gotos, LN.counts.dataStores, LN.counts.chartPorts);
    if LN.counts.warnings > 0
        fprintf('  ⚠ 배선 경고 %d건 — 한쪽만 있는 Data Store 를 포함한다 (lines.json)\n', ...
            LN.counts.warnings);
        for i = 1:min(4, numel(LN.warnings)), fprintf('     %s\n', LN.warnings{i}); end
        if numel(LN.warnings) > 4, fprintf('     ... 외 %d건\n', numel(LN.warnings)-4); end
    end
    if ~isempty(T.compileError)
        fprintf('  ⚠ 실제 전파 타입은 **미확인**이다 — 컴파일이 막혔다.\n');
        fprintf('    %s\n', firstLine(T.compileError));
    end
    if G.violations > 0
        fprintf('\n  지적 %d건:\n', G.violations);
        for i = 1:numel(G.findings)
            f = G.findings(i);
            fprintf('    - [%s] %s  (%s)\n', f.kind, f.target, shorten(f.chart, 30));
        end
        fprintf('\n  🔴 이 지적들은 **관문이 아니라 확인 요청**이다. 하나씩 보고\n');
        fprintf('     의도한 것이면 그대로 두고, 아니면 고친다.\n');
    end
    if ~isempty(rep.warn)
        fprintf('\n  전제 경고 %d건:\n', numel(rep.warn));
        for i = 1:numel(rep.warn), fprintf('    ⚠ %s\n', rep.warn{i}); end
    end

    fprintf('\n  다음: 덤프 JSON 을 에이전트에게 병렬로 읽힌다 (`/model`).\n');
    fprintf('        MATLAB 은 메인만 만진다 — MCP 는 세션 하나에 붙으므로 병렬이 안 된다.\n\n');

    ok = true;
    if nargout, varargout{1} = ok; end
end


% ══════════════════════════════════════════════════════

function line(t)
    fprintf('\n──────── %s ────────\n', t);
end

function stop(why, dateStr)
    fprintf('\n');
    fprintf('🔴 %s. 여기서 멈춘다.\n\n', why);
    fprintf('   산출물을 만들지 않는다 — 전제나 도구가 틀린 상태로 만든 덤프는\n');
    fprintf('   오류 없이 그럴듯하게 틀리고, 그 위에서 에이전트가 판단하면\n');
    fprintf('   틀린 근거로 옳아 보이는 결론이 나온다.\n\n');
    fprintf('   위 실패 항목을 먼저 고친 뒤 build(''%s'') 를 다시 돌린다.\n\n', dateStr);
end

function s = firstLine(s)
    i = strfind(s, newline);
    if ~isempty(i), s = s(1:i(1)-1); end
    if numel(s) > 150, s = [s(1:147) '...']; end
end

function s = shorten(s, n)
    if numel(s) > n, s = ['…' s(end-n+2:end)]; end
end
