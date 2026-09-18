function rep = layout_chart(target, varargin)
%LAYOUT_CHART  Chart(또는 상위 State) 의 자식 State 를 **세로 한 줄**로 놓고 전이를 좌/우 규칙으로 배선한다.
%
%   rep = layout_chart('Esm/Esm')                       Chart 경로
%   rep = layout_chart(chartObj)                        Stateflow.Chart 또는 Stateflow.State
%   rep = layout_chart(..., 'X', 250, 'Y0', 80, 'Gap', 50, 'MinWidth', 200, 'Recursive', true)
%
%   왜 있나 (2026-09-18 사용자 결정 — 09-17 비교 회차 두 번에서 ruflo 쪽 결과물이 두 번 다 가장 읽기 쉬웠고,
%   그 차이는 정확성이 아니라 build 스크립트가 좌표를 찍는 습관 하나였다. 그 습관을 현행 하네스로 옮긴 것.)
%   → ruflo_comparison/2026-09-17_esm_간단_재대결/01_대조 §4 · 모델저작_규칙 §2.5
%
%   규칙 (ruflo 2회차 build_Esm.m 의 배치 규칙을 일반화)
%   ─────────────────────────────────────────────────
%     순서   default 전이의 목적지부터, 실행순서가 가장 작은 아직 안 놓인 자식으로 가는 전이를 따라 사슬을 만든다.
%            끊기면 남은 자식을 원래 y 순서로 붙인다.  → 순차 FSM 은 「기동 순서」가 위→아래가 된다
%     위치   같은 X, 폭은 자식 중 가장 긴 라벨에 맞춰 **균일**, 높이는 라벨 줄 수에 비례, 간격 Gap
%     전이   한 단 아래(i→i+1)   : 왼쪽 세로선  (Source 7시 → Destination 11시), 라벨은 왼쪽
%            한 단 위 (i→i-1)    : 오른쪽 세로선 (1시 → 5시), 라벨은 오른쪽
%            두 단 이상 위       : 오른쪽으로 부풀린 호 (3시 → 3시), 부풀림 70 + 50×(거리-1)
%            두 단 이상 아래     : 왼쪽으로 부풀린 호  (9시 → 9시), 같은 부풀림
%            자기 전이           : 오른쪽 작은 고리 (2시 → 4시)
%            default            : 목적지 위 30 px 에서 수직으로
%            상대가 이 컨테이너 밖(Junction · 형제 컨테이너)이면 손대지 않는다
%     재귀   자식이 또 자식을 가지면 먼저 그 안을 놓고 그 크기로 상자를 잡는다
%     부모   State 면 자식 + 왼쪽 라벨 여백 + 오른쪽 호 여백을 감싸게 **먼저** 넓힌다 —
%            호가 부모 경계를 넘으면 Stateflow 가 전이를 Chart 층으로 재부모화한다(ruflo 2차 실행 실측)
%
%   되돌리기: 좌표만 바꾼다. 라벨·계층·실행순서는 건드리지 않는다 — compare_spec 결과가 변하면 버그다.
%
%   🔴 이 회차에서 확인한 Stateflow API 사실 (2026-09-18, R2025b)
%     · 객체 API 로 State.Position 을 바꾸면 **기하학적 포함으로 계층을 즉시 다시 계산**한다 — 부모만 옮기면 자식이
%       Chart 층으로 빠지고(19→15), 부모를 옛+새 상자로 키우면 그 안에 든 형제를 삼킨다. 저수준
%       sf('set', id, 'state.position', pos) 는 재부모화를 하지 않는다 → 좌표 쓰기는 전부 sfpos() 로.
%     · sf set 은 전이 MidPoint 를 자동 갱신하지 않는다 — 옮긴 벡터만큼 MidPoint 도 옮겨야 중점이 부모 밖에 남아
%       전이가 재부모화되는 일을 막는다. 직선은 새 끝점 평균을 MidPoint 로(선 밖 점을 주면 OClock 이 6/0 으로 스냅).
%     · 검증: Esm_cur·Esm_ecc·EcApp_ruflo·EcApp_ecc 네 모델에서 전이 부모·State 경로·라벨·실행순서 변경 0, update 통과.

    p = inputParser;
    p.addParameter('X', 250); p.addParameter('Y0', 80); p.addParameter('Gap', 50);
    p.addParameter('MinWidth', 200); p.addParameter('LineH', 15); p.addParameter('CharW', 7.5);
    p.addParameter('Recursive', true); p.addParameter('Verbose', true);
    p.parse(varargin{:}); o = p.Results;

    if ischar(target) || isstring(target)
        rt = sfroot; target = rt.find('-isa', 'Stateflow.Chart', 'Path', char(target));
        assert(~isempty(target), 'layout_chart: Chart 를 못 찾았다: %s', char(target));
    end
    rep = struct('container', target.Path, 'states', 0, 'transitions', 0, 'skipped', 0, 'children', {{}});
    rep = do_layout(target, o, rep, 0);
end

function rep = do_layout(P, o, rep, depth)
    kids = P.find('-isa', 'Stateflow.State', '-depth', 1);
    kids = kids(arrayfun(@(k) k ~= P, kids));
    if isempty(kids), return; end

    % 1. 재귀 — 자식 안을 먼저 놓는다 (크기를 알아야 한다)
    for k = 1:numel(kids)
        if o.Recursive && ~isempty(kids(k).find('-isa', 'Stateflow.State', '-depth', 1)) && any(kids(k).find('-isa', 'Stateflow.State', '-depth', 1) ~= kids(k))
            sub = struct('container', kids(k).Path, 'states', 0, 'transitions', 0, 'skipped', 0, 'children', {{}});
            sub = do_layout(kids(k), o, sub, depth + 1);
            rep.children{end+1} = sub;
        end
    end

    % 2. 사슬 / 옆열 나누기 — 자식이 있는 State(상위 State)는 오른쪽 옆열로 뺀다(모든 자식이 상위거나 하나뿐이면 사슬로)
    allT = P.find('-isa', 'Stateflow.Transition', '-depth', 1);
    allT = allT(arrayfun(@(t) isequal(t.getParent, P), allT));
    isComposite = arrayfun(@(k) numel(k.find('-isa', 'Stateflow.State', '-depth', 1)) > 1, kids);
    if all(isComposite) || isscalar(kids), isComposite(:) = false; end
    side = kids(isComposite); kids = kids(~isComposite);
    inSet  = @(s) ~isempty(s) && any(arrayfun(@(k) k == s, kids));
    inSide = @(s) ~isempty(s) && any(arrayfun(@(k) k == s, side));

    % 2b. 사슬 순서 — default 목적지부터 실행순서가 가장 작은 전이를 따라간다
    order = [];
    dflt = allT(arrayfun(@(t) isempty(t.Source) && inSet(t.Destination), allT));
    if ~isempty(dflt), cur = dflt(1).Destination; else, [~, ix] = min(arrayfun(@(k) k.Position(2), kids)); cur = kids(ix); end
    while ~isempty(cur)
        order(end+1) = find(arrayfun(@(k) k == cur, kids)); %#ok<AGROW>
        outs = allT(arrayfun(@(t) ~isempty(t.Source) && t.Source == cur && inSet(t.Destination) && ~any(arrayfun(@(k) kids(k) == t.Destination, order)), allT));
        if isempty(outs), break; end
        [~, ix] = min(arrayfun(@(t) t.ExecutionOrder, outs)); cur = outs(ix).Destination;
    end
    rest = setdiff(1:numel(kids), order);
    if ~isempty(rest), [~, ix] = sort(arrayfun(@(k) kids(k).Position(2), rest)); order = [order rest(ix)]; end
    kids = kids(order);
    n = numel(kids);

    % 3. 크기 — 균일 폭, 줄 수 비례 높이 (자식이 있는 State 는 이미 놓인 내부 크기)
    W = o.MinWidth; H = zeros(1, n); hasKids = false(1, n);
    for k = 1:n
        lines = strsplit(kids(k).LabelString, newline);
        W = max(W, 20 + o.CharW * max(cellfun(@numel, lines)));
        sub = kids(k).find('-isa', 'Stateflow.State', '-depth', 1); sub = sub(arrayfun(@(s) s ~= kids(k), sub));
        if ~isempty(sub)
            hasKids(k) = true; b = bounds_of(sub, kids(k)); H(k) = b.h; W = max(W, b.w);
        else
            H(k) = max(60, 24 + o.LineH * numel(lines));
        end
    end
    % 3b. 호의 부풀림 → 좌우 여백
    maxUp = 0; maxDown = 0;
    idx = @(s) find(arrayfun(@(k) k == s, kids), 1);
    for ii = 1:numel(allT)
        t = allT(ii);
        if isempty(t.Source) || ~inSet(t.Source) || ~inSet(t.Destination), continue; end
        d = idx(t.Destination) - idx(t.Source);
        if d <= -2, maxUp = max(maxUp, 70 + 50 * (-d - 1)); end
        if d >= 2, maxDown = max(maxDown, 70 + 50 * (d - 1)); end
    end
    leftPad = 190 + maxDown;  rightPad = 60 + maxUp;
    % 4. 위치 — 컨테이너 기준 세로 한 줄 (State 면 왼쪽 + 라벨 여백, 라벨 줄 아래부터 · Chart 면 옵션 X·Y0)
    if isa(P, 'Stateflow.State')
        pp = P.Position;
        colX = pp(1) + leftPad;
        y0 = pp(2) + 24 + o.LineH * numel(strsplit(P.LabelString, newline));
    else
        colX = o.X; y0 = o.Y0;
    end
    y = y0; pos = zeros(n, 4);
    for k = 1:n
        pos(k, :) = [colX, y, W, H(k)];
        y = y + H(k) + o.Gap;
    end
    % 4b. 옆열 — 상위 State 는 사슬 오른쪽, 들어오는 전이 출발점들의 평균 높이에(없으면 위에서부터)
    ns = numel(side); spos = zeros(ns, 4); sideW = 0;
    if ns > 0
        sideX = colX + W + rightPad + 80;
        ySide = y0;
        for k = 1:ns
            sub = side(k).find('-isa', 'Stateflow.State', '-depth', 1); sub = sub(arrayfun(@(s) s ~= side(k), sub));
            b = bounds_of(sub, side(k)); sw = b.w; sh = b.h; sideW = max(sideW, sw);
            srcs = allT(arrayfun(@(t) ~isempty(t.Source) && inSet(t.Source) && t.Destination == side(k), allT));
            if ~isempty(srcs)
                cy = mean(arrayfun(@(t) pos(idx(t.Source), 2) + pos(idx(t.Source), 4)/2, srcs));
                yk = max(ySide, cy - sh/2);
            else
                yk = ySide;
            end
            spos(k, :) = [sideX, yk, sw, sh];
            ySide = yk + sh + o.Gap;
        end
        y = max(y, ySide);
    end
    % 5. 부모를 먼저 넓힌다 (재부모화 방지)
    if isa(P, 'Stateflow.State')
        newW = max(pp(3), leftPad + W + rightPad + (ns > 0) * (80 + sideW + 40));
        newH = max(pp(4), (y - o.Gap + 30) - pp(2));
        sfpos(P, [pp(1) pp(2) newW newH]);
    end
    for k = 1:n
        if hasKids(k), shift_children(kids(k), pos(k, :)); else, sfpos(kids(k), pos(k, :)); end
    end
    for k = 1:ns
        shift_children(side(k), spos(k, :));
    end
    n = n + ns;
    rep.states = rep.states + n;

    % 6. 전이 배선
    for ii = 1:numel(allT)
        t = allT(ii);
        if isempty(t.Source)
            % default — 목적지가 직계 자식이든 후손(Chart 층에서 substate 로 바로 들어가는 supertransition)이든
            % 목적지 위 30 px 에서 수직으로. 후손인 경우 목적지를 옮겼으므로 시작점을 반드시 따라 옮겨야 한다
            if inSet(t.Destination) || is_descendant(t.Destination, P)
                top = top_of(t.Destination);
                t.DestinationOClock = 0;
                t.SourceEndpoint = top - [0 30];
                t.MidPoint       = top - [0 15];
                rep.transitions = rep.transitions + 1;
            else
                rep.skipped = rep.skipped + 1;
            end
            continue;
        end
        if inSet(t.Source) && inSide(t.Destination)            % 사슬 → 옆열 (예: 단계 실패 → Exit): 오른쪽으로, 도착점은 출발 높이에 맞춰 왼쪽 변에 퍼뜨린다
            sp = pos(idx(t.Source), :); ks = find(arrayfun(@(q) q == t.Destination, side), 1); dpp = spos(ks, :);
            srcY = sp(2) + sp(4)/2; rel = (dpp(2) + dpp(4)/2 - srcY) / max(dpp(4)/2, 1);      % +1 = 출발이 위, -1 = 아래
            t.SourceOClock = 3; t.DestinationOClock = min(10.4, max(7.6, 9 + 1.4 * rel));
            t.MidPoint = (t.SourceEndpoint + t.DestinationEndpoint) / 2;
            lpos = t.LabelPosition; lpos(1:2) = [sp(1) + sp(3) + 8, sp(2) - 16]; t.LabelPosition = lpos;
            rep.transitions = rep.transitions + 1; continue;
        elseif inSide(t.Source) && inSet(t.Destination)        % 옆열 → 사슬: 왼쪽으로
            t.SourceOClock = 9; t.DestinationOClock = 3;
            t.MidPoint = (t.SourceEndpoint + t.DestinationEndpoint) / 2;
            rep.transitions = rep.transitions + 1; continue;
        end
        if ~inSet(t.Source) || ~inSet(t.Destination), rep.skipped = rep.skipped + 1; continue; end
        i = idx(t.Source); j = idx(t.Destination);
        sp = pos(i, :); dp = pos(j, :);
        if j == i + 1                                   % 한 단 아래 — 왼쪽 세로선 (MidPoint 는 Stateflow 가 직선으로 잡는다)
            so = 7; do = 11; mp = [];
            lp = [sp(1) - 180, sp(2) + sp(4) + 12];
        elseif j == i - 1                               % 한 단 위 — 오른쪽 세로선
            so = 1; do = 5; mp = [];
            lp = [sp(1) + sp(3) * 2/3 + 8, sp(2) - 32];
        elseif j < i - 1                                % 두 단 이상 위 — 오른쪽 호
            so = 3; do = 3;
            bulge = 70 + 50 * (i - j - 1);
            mp = [sp(1) + sp(3) + bulge, (sp(2) + sp(4)/2 + dp(2) + dp(4)/2) / 2];
            lp = [mp(1) + 6, mp(2) - 8];
        elseif j > i + 1                                % 두 단 이상 아래 — 왼쪽 호
            so = 9; do = 9;
            bulge = 70 + 50 * (j - i - 1);
            mp = [sp(1) - bulge, (sp(2) + sp(4)/2 + dp(2) + dp(4)/2) / 2];
            lp = [mp(1) - 170, mp(2) - 8];
        else                                            % 자기 전이 — 오른쪽 작은 고리
            so = 2; do = 4;
            mp = [sp(1) + sp(3) + 40, sp(2) + sp(4)/2];
            lp = [sp(1) + sp(3) + 48, sp(2) + sp(4)/2 - 8];
        end
        t.SourceOClock = so; t.DestinationOClock = do;
        if isempty(mp), mp = (t.SourceEndpoint + t.DestinationEndpoint) / 2; end   % 직선: 새 끝점의 평균(선 위) — 선 밖 점을 주면 OClock 이 6/0 으로 스냅된다(09-18 실측)
        t.MidPoint = mp;
        lpos = t.LabelPosition; lpos(1:2) = lp; t.LabelPosition = lpos;
        rep.transitions = rep.transitions + 1;
    end
    if o.Verbose
        fprintf('%s%s: State %d · 전이 %d 배선 · 건너뜀 %d\n', repmat('  ', 1, depth), P.Name, n, rep.transitions, rep.skipped);
    end
end

function tf = is_descendant(obj, P)
    tf = false; if isempty(obj), return; end
    q = obj;
    while true
        try
            q = q.getParent;
        catch
            return;
        end
        if isempty(q), return; end
        if q == P, tf = true; return; end
        if isa(q, 'Stateflow.Chart') || isa(q, 'Stateflow.Machine'), return; end
    end
end

function b = bounds_of(sub, parent)
    % 자식들의 경계 상자 + 여백 → 부모가 가져야 할 폭·높이 (부모 좌상단 기준 상대 크기)
    xs = arrayfun(@(s) s.Position(1), sub); ys = arrayfun(@(s) s.Position(2), sub);
    xe = arrayfun(@(s) s.Position(1) + s.Position(3), sub); ye = arrayfun(@(s) s.Position(2) + s.Position(4), sub);
    pp = parent.Position;
    b.w = max(pp(3), (max(xe) - pp(1)) + 60);
    b.h = max(pp(4), (max(ye) - pp(2)) + 30);
    b.x0 = min(xs); b.y0 = min(ys);
end

function shift_children(parent, newPos)
    % 부모와 그 안의 모든 State·Junction 을 같은 벡터로 평행이동한다.
    % 🔴 객체 API 의 Position 설정은 매번 기하학적 포함으로 계층을 다시 계산해 자식을 잃거나 형제를 삼킨다(09-18 실측).
    %    저수준 sf('set', id, 'state.position') 은 재부모화를 하지 않으므로 전부 옮긴 뒤의 최종 기하만 맞으면 된다.
    old = parent.Position; dx = newPos(1) - old(1); dy = newPos(2) - old(2);
    sfpos(parent, newPos);
    if dx == 0 && dy == 0, return; end
    st = parent.find('-isa', 'Stateflow.State');
    for ii = 1:numel(st)
        if st(ii) == parent, continue; end
        q = st(ii).Position; sfpos(st(ii), [q(1) + dx, q(2) + dy, q(3), q(4)]);
    end
    jn = parent.find('-isa', 'Stateflow.Junction');
    for ii = 1:numel(jn)
        c = jn(ii).Position.Center; r = jn(ii).Position.Radius;
        sf('set', jn(ii).Id, 'junction.position', [c(1) + dx, c(2) + dy, r]);
    end
    tl = parent.find('-isa', 'Stateflow.Transition');
    for ii = 1:numel(tl)
        t = tl(ii);
        try
            if isempty(t.Source) && ~isempty(t.Destination)
                top = top_of(t.Destination);
                t.SourceEndpoint = top - [0 30]; t.MidPoint = top - [0 15];
            elseif ~isempty(t.Source) && ~isempty(t.MidPoint)
                % sf set 은 MidPoint 를 자동 갱신하지 않는다 — 전부 같은 벡터로 옮겨야 중점이 부모 밖에 남지 않는다
                t.MidPoint = t.MidPoint + [dx dy];
            end
            lp = t.LabelPosition; lp(1:2) = lp(1:2) + [dx dy]; t.LabelPosition = lp;
        catch
        end
    end
end

function sfpos(obj, pos)
    % 재부모화 없는 좌표 쓰기
    sf('set', obj.Id, 'state.position', pos);
end

function top = top_of(obj)
    % State 는 위 변 중앙, Junction 은 원 위쪽 점
    if isa(obj, 'Stateflow.Junction')
        c = obj.Position.Center; top = [c(1), c(2) - obj.Position.Radius];
    else
        q = obj.Position; top = [q(1) + q(3)/2, q(2)];
    end
end
