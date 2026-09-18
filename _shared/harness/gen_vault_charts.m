function gen_vault_charts(model, vaultRoot)
%GEN_VAULT_CHARTS  Stateflow Chart 마다 폴더와 문서를 만든다 (규칙 R10).
%
%   2026-08-05 (R19) — 열거와 배치를 vault_units.m 에 맡긴다
%   ────────────────────────────────────────────────────
%   전에는 이 파일이 `sfroot` 로 직접 Chart 를 열거하고, 소속 모델을 참조하는
%   ModelReference 블록 폴더 아래에 놓았다. 두 가지가 문제였다.
%     (1) `sfroot` 는 그때 열려 있는 모델에 따라 결과가 달라진다 (R18)
%     (2) 참조 블록 아래로 끼워넣으면 경로가 Windows 260자를 넘는다 (R19)
%   이제 Chart 는 `_참조모델\<모델명>\` 아래에 놓인다.

    % 날짜·위키링크 접두는 세션 맥락에서 받는다 (gen_vault_tree 와 같은 이유).
    ctx = vault_ctx(model);

    U = vault_units(model);
    U = U(strcmp({U.kind}, 'Stateflow Chart'));

    made = 0;
    for k = 1:numel(U)
        u      = U(k);
        folder = fullfile(vaultRoot, u.segs{:});
        if ~isfolder(folder), mkdir(folder); end
        writeChart(fullfile(folder, [strjoin(u.segs,'_') '.md']), u.chart, u.model, ctx);
        made = made + 1;
    end
    fprintf('Chart 문서 %d개 생성\n', made);
end


function writeChart(path, c, owner, ctx)
    % 🔴 기존 해석 보존. 재생성이 사람이 쓴 해석을 지우면 안 된다 (gen_vault_tree 와 같은 이유).
    keep = read_interp(path);

    fid = fopen(path,'w','n','UTF-8');
    oc  = onCleanup(@() fclose(fid));
    p   = @(varargin) fprintf(fid, varargin{:});

    st = c.find('-isa','Stateflow.State');
    tr = c.find('-isa','Stateflow.Transition');
    ju = c.find('-isa','Stateflow.Junction');
    dd = c.find('-isa','Stateflow.Data');
    ev = c.find('-isa','Stateflow.Event');
    fn = c.find('-isa','Stateflow.EMFunction');
    gf = c.find('-isa','Stateflow.Function');

    p('---\n분류: work\n세션: "%s"\n대상: %s\n작성일: %s\n---\n\n', ctx.date, c.Path, ctx.iso);
    p('# Chart `%s`\n\n', c.Name);
    p('> 소속 모델 `%s` · 경로 `%s`\n', owner, c.Path);
    p('> **기계 추출 문서.** 값은 전부 Stateflow API 원본이다. 규칙 → [[%s/_분석규칙|분석 규칙]]\n\n', ctx.wiki);

    p('## 1. Chart 속성\n\n| 항목 | 값 |\n| --- | --- |\n');
    p('| Decomposition | `%s` |\n', c.Decomposition);
    p('| State | %d |\n| Transition | %d |\n| Junction | %d |\n', numel(st), numel(tr), numel(ju));
    p('| Data | %d |\n| Event | %d |\n', numel(dd), numel(ev));
    p('| MATLAB 함수 | %d |\n| 그래픽 함수 | %d |\n', numel(fn), numel(gf));
    for f = {'ActionLanguage','ChartUpdate','SampleTime','ExecuteAtInitialization','StatesWhenEnabling'}
        v = '-'; try, v = str(c.(f{1})); catch, end
        p('| %s | `%s` |\n', f{1}, v);
    end
    p('\n');

    sc = {dd.Scope};
    p('## 2. Data (%d)\n\n', numel(dd));
    p('Scope 집계: ');
    u = unique(sc);
    for j = 1:numel(u), p('%s %d / ', u{j}, sum(strcmp(sc,u{j}))); end
    p('\n\n| 이름 | Scope | DataType | Size | InitialValue |\n| --- | --- | --- | --- | --- |\n');
    for j = 1:numel(dd)
        iv = ''; try, iv = dd(j).Props.InitialValue; catch, end
        p('| `%s` | %s | `%s` | %s | `%s` |\n', dd(j).Name, dd(j).Scope, ...
            str(dd(j).DataType), str(dd(j).Props.Array.Size), str(iv));
    end
    p('\n');

    if ~isempty(ev)
        p('## 3. Event (%d)\n\n| 이름 | Scope | Trigger |\n| --- | --- | --- |\n', numel(ev));
        for j = 1:numel(ev)
            tg = '-'; try, tg = str(ev(j).Trigger); catch, end
            p('| `%s` | %s | %s |\n', ev(j).Name, ev(j).Scope, tg);
        end
        p('\n');
    end

    top = st(arrayfun(@(x) isa(x.getParent,'Stateflow.Chart'), st));
    p('## 4. State 계층 (%d, 최상위 %d)\n\n', numel(st), numel(top));
    [~,i] = sort(arrayfun(@(x) statePath(x), st));
    p('| 경로 | 깊이 | Decomposition | 실행순서 | 하위 |\n| --- | --- | --- | --- | --- |\n');
    for k2 = i'
        sp = char(statePath(st(k2)));
        p('| `%s` | %d | %s | %s | %d |\n', sp, numel(strfind(sp,'.')), ...
            st(k2).Decomposition, str(st(k2).ExecutionOrder), numel(st(k2).find('-isa','Stateflow.State'))-1);
    end
    p('\n## 5. State Action 전문\n\n');
    for k2 = i'
        L = strtrim(st(k2).LabelString);
        p('### `%s`\n\n', char(statePath(st(k2))));
        if isempty(L), p('Action 없음\n\n'); else, p('```\n%s\n```\n\n', L); end
    end

    p('## 6. Transition (%d)\n\n| # | Source | Destination | 순서 | Label |\n| --- | --- | --- | --- | --- |\n', numel(tr));
    for j = 1:numel(tr)
        p('| %d | %s | %s | %s | `%s` |\n', j, ep(tr(j).Source), ep(tr(j).Destination), ...
            str(tr(j).ExecutionOrder), oneline(tr(j).LabelString));
    end
    p('\n');

    if ~isempty(fn)
        p('## 7. MATLAB 함수 전문 (%d)\n\n', numel(fn));
        for j = 1:numel(fn)
            p('### `%s`\n\n```matlab\n%s\n```\n\n', fn(j).Name, fn(j).Script);
        end
    end

    emit_interp(p, keep, 8);   % 해석 절 구조는 emit_interp.m 하나가 정한다 (R17)
    p('---\n\n[[%s/_안내|↑ 서브시스템 지도]]\n', ctx.wiki);
end


function nm = statePath(s)
    parts = {s.Name};
    pr = s.getParent;
    while ~isempty(pr) && ~isa(pr,'Stateflow.Chart')
        parts{end+1} = pr.Name; %#ok<AGROW>
        pr = pr.getParent;
    end
    nm = string(strjoin(fliplr(parts),'.'));
end

function s = ep(e)
    if isempty(e), s = '**(기본 전이)**';
    elseif isa(e,'Stateflow.State'), s = ['`' char(statePath(e)) '`'];
    elseif isa(e,'Stateflow.Junction'), s = sprintf('Junction %d', e.Id);
    else, s = class(e); end
end

function out = oneline(s)
    if isempty(s), out=''; return; end
    out = regexprep(s, '\s*\n\s*', ' ; ');
    out = strrep(out,'|','\|');
end

function t = str(x)
    if isempty(x), t='';
    elseif ischar(x), t=x;
    elseif isnumeric(x)||islogical(x), t=mat2str(x);
    else, try, t=char(string(x)); catch, t=class(x); end
    end
    t = strrep(t, sprintf('\n'), ' ');
end


function s = safeName(s)
    s = strtrim(strrep(s, sprintf('\n'), ' '));
    s = regexprep(s, '[<>:"/\\?*]', '_');
    s = regexprep(s, '\s+', '_');
end
