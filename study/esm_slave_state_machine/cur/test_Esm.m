%% test_Esm.m — 공개 수용 시험 T1~T3 을 sim 으로 돌려 틱 단위로 대조한다. 「통과 n/3」 출력.
%
%   실행:  matlab -wait -nosplash -batch "run('<OUT>\test_Esm.m')" -logfile <OUT>\test.log
%
%   시험 입력은 t = 0 에 0 행(초기화 틱)을 앞에 붙여 k번째 틱을 t = k ms 에 넣는다.
%   기대값은 Esm_사양.md §6 과 같다. 금지 조건 F1~F6(§5) 도 같은 로그로 같이 잰다.
%   결과 폴더(OUT) 밖에는 아무것도 쓰지 않는다 — slprj 캐시는 OUT\_slprj.

OUT = fileparts(mfilename('fullpath'));
MDL = 'Esm';
SLX = fullfile(OUT, [MDL '.slx']);

fprintf('\n==== test_Esm ====\n');
assert(isfolder(OUT), 'result folder not found: %s', OUT);
assert(isfile(SLX), 'Esm.slx not found — run build_Esm.m first');
cd(OUT);
Simulink.fileGenControl('set', ...
    'CacheFolder',   fullfile(OUT, '_slprj'), ...
    'CodeGenFolder', fullfile(OUT, '_slprj'), 'createDir', true);
if ~bdIsLoaded(MDL), load_system(SLX); end

% ── 공개 수용 시험 3개 (틱 1~N 의 입력과 기대 출력) ─────────
C = {};
C{end+1} = mkcase('T1 기동·하강',   [2 0 4 8 8 4 1], [0 0 0 0 0 0 0], ...
                                    [2 2 4 8 8 4 1], [0 0 0 0 0 0 0], [0 0 0 1 1 0 0]);
C{end+1} = mkcase('T2 불법 요청',   [8 0 0 2 0],     [0 0 1 0 0], ...
                                    [1 1 1 2 2],     [1 1 0 0 0],     [0 0 0 0 0]);
C{end+1} = mkcase('T3 오류 중 요청', [2 8 4 1 2 4],   [0 0 0 0 1 0], ...
                                    [2 2 2 1 2 4],   [0 1 1 1 0 0],   [0 0 0 0 0 0]);

nPass = 0;
for k = 1:numel(C)
    c = C{k};
    fprintf('\n[%s] 틱 %d개\n', c.id, numel(c.req));
    try
        y = runcase(MDL, c);
    catch e
        fprintf('  ✗ sim 오류: %s\n', strrep(e.message, newline, ' / '));
        continue
    end
    N = numel(c.req);
    if k == 1, fprintf('  yout 요소: %s\n', strjoin(cellfun(@(s) ['''' char(s) ''''], y.names, 'UniformOutput', false), ' ')); end
    if numel(y.t) ~= N + 1
        fprintf('  ✗ 로그 길이 %d ≠ %d (t = 0 .. %d ms)\n', numel(y.t), N + 1, N);
        continue
    end
    % 초기화 틱 t = 0 (F6)
    ok0 = (y.st(1) == 1) && (y.err(1) == 0) && (y.outEn(1) == 0);
    % 틱 1..N — 행 k+1 이 t = k ms
    got = [y.st(2:end)'; y.err(2:end)'; y.outEn(2:end)'];
    exp = [c.st; c.err; c.outEn];
    bad = any(got ~= exp, 1);
    fprintf('  %-6s %s\n', 'tick',  sprintf('%3d', 1:N));
    fprintf('  %-6s %s\n', 'req',   sprintf('%3d', c.req));
    fprintf('  %-6s %s\n', 'ack',   sprintf('%3d', c.ack));
    fprintf('  %-6s %s   (기대 %s)\n', 'st',    sprintf('%3d', got(1,:)), sprintf('%d ', exp(1,:)));
    fprintf('  %-6s %s   (기대 %s)\n', 'err',   sprintf('%3d', got(2,:)), sprintf('%d ', exp(2,:)));
    fprintf('  %-6s %s   (기대 %s)\n', 'outEn', sprintf('%3d', got(3,:)), sprintf('%d ', exp(3,:)));
    % 금지 조건 F1~F5 (§5) — 같은 로그로
    F = forbidden(y.st, y.err, y.outEn, [0, c.ack]);
    fprintf('  t=0 초기화 틱 %s | F1 %d F2 %d F3 %d F4 %d F5 %d\n', ternary(ok0, '○', '✗'), F);
    if ok0 && ~any(bad) && all(F)
        nPass = nPass + 1;
        fprintf('  ○ 통과\n');
    else
        if any(bad), fprintf('  ✗ 틀린 틱: %s\n', num2str(find(bad))); end
        if ~all(F),  fprintf('  ✗ 금지 조건 위반: F%s\n', num2str(find(~F))); end
        fprintf('  ✗ 실패\n');
    end
end

fprintf('\n통과 %d/%d\n', nPass, numel(C));
fprintf('==== test_Esm done ====\n');

% ══════════════════════════════════════════════════════════
function c = mkcase(id, req, ack, st, err, outEn)
    c = struct('id', id, 'req', req, 'ack', ack, 'st', st, 'err', err, 'outEn', outEn);
end

function y = runcase(MDL, c)
%RUNCASE  t = 0 에 0 행을 앞에 붙여 k번째 틱을 t = k ms 에 넣고 돌린다.
    N  = numel(c.req);
    t  = (0:N)' * 0.001;
    ds = Simulink.SimulationData.Dataset;
    ts = timeseries(uint8([0, c.req])',   t); ts.Name = 'req'; ds = ds.addElement(ts);
    ts = timeseries(logical([0, c.ack])', t); ts.Name = 'ack'; ds = ds.addElement(ts);

    in = Simulink.SimulationInput(MDL);
    in = in.setExternalInput(ds);
    in = in.setModelParameter('StopTime', num2str(N * 0.001), 'SaveFormat', 'Dataset', ...
                              'SaveOutput', 'on', 'SaveTime', 'on');
    out = sim(in);
    yo = out.yout;
    % Dataset 요소는 신호 이름이 없으면 Outport 이름이 아닐 수 있다 — 이름으로 찾고, 없으면 포트 번호로
    y.names = yo.getElementNames();
    v1 = getout(yo, 'st', 1); v2 = getout(yo, 'err', 2); v3 = getout(yo, 'outEn', 3);
    y.t     = v1.Time;
    y.st    = double(v1.Data);
    y.err   = double(v2.Data);
    y.outEn = double(v3.Data);
end

function v = getout(yo, name, idx)
    names = yo.getElementNames();
    j = find(strcmp(names, name), 1);
    if isempty(j), j = idx; end
    v = yo.get(j).Values;
end

function F = forbidden(st, err, outEn, ack)
%FORBIDDEN  사양표 §5 F1~F5 를 로그 하나에서 잰다. 전부 true 여야 한다.
%   ack 는 로그와 같은 길이(t = 0 행 포함). F4 는 같은 틱에 ack 가 없을 때만 본다.
    allowed = [1 2; 2 1; 2 4; 4 1; 4 2; 4 8; 8 1; 8 2; 8 4];
    F1 = all(outEn == (st == 8));
    F2 = all(ismember(st, [1 2 4 8]));
    F3 = true; F4 = true;
    for k = 2:numel(st)
        if st(k) == st(k-1), continue; end
        if ~any(allowed(:,1) == st(k-1) & allowed(:,2) == st(k)), F3 = false; end
        if err(k-1) && ~ack(k) && st(k) ~= 1, F4 = false; end
    end
    F5 = ~any(diff(st) ~= 0 & diff(err) == 1);
    F = [F1 F2 F3 F4 F5];
end

function v = ternary(c, a, b)
    if c, v = a; else, v = b; end
end
