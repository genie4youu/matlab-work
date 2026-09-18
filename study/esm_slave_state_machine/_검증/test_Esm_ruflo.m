%% test_Esm_ruflo.m — 공개 수용 시험 3개를 sim 으로 돌려 틱 단위로 대조하고 「통과 n/3」 을 낸다
%
%   실행: build_Esm_ruflo.m 다음에(모델이 로드돼 있지 않으면 Esm_ruflo.slx 를 연다).
%     matlab -wait -nosplash -batch "run('<OUT>\test_Esm_ruflo.m')" -logfile <OUT>\test.log
%
%   시험 입력은 t = 0 에 0 행(초기화 틱)을 앞에 붙여 k번째 틱을 t = k ms 에 넣는다.
%   출력 대조는 t = 0(st=1·err=0·outEn=0) 과 t = 1..N ms 의 st·err·outEn 전부.
%   시험 표는 Esm_ruflo_사양.md §6 과 같다. 결과 폴더(OUT) 밖에는 아무것도 쓰지 않는다.

OUT = fileparts(fileparts(mfilename('fullpath')));
MDL = 'Esm_ruflo';
SLX = fullfile(OUT, [MDL '.slx']);

fprintf('\n==== test_Esm_ruflo ====\n');
assert(isfolder(OUT), 'result folder not found: %s', OUT);
cd(OUT);
Simulink.fileGenControl('set', ...
    'CacheFolder',   fullfile(OUT, '_검증', '_slprj'), ...
    'CodeGenFolder', fullfile(OUT, '_검증', '_slprj'), 'createDir', true);
if ~bdIsLoaded(MDL)
    assert(isfile(SLX), 'Esm_ruflo.slx not found — run build_Esm_ruflo.m first');
    load_system(SLX);
end

% ── 공개 수용 시험 3개 (사양 §6) — 열: 이름 · req · ack · st · err · outEn ──
cases = { ...
 'T1 기동·하강',   [2 0 4 8 8 4 1], [0 0 0 0 0 0 0], [2 2 4 8 8 4 1], [0 0 0 0 0 0 0], [0 0 0 1 1 0 0];
 'T2 불법 요청',   [8 0 0 2 0],     [0 0 1 0 0],     [1 1 1 2 2],     [1 1 0 0 0],     [0 0 0 0 0];
 'T3 오류 중 요청', [2 8 4 1 2 4],   [0 0 0 0 1 0],   [2 2 2 1 2 4],   [0 1 1 1 0 0],   [0 0 0 0 0 0];
};

nPass = 0;
traj  = cell(1, size(cases, 1));                  % 금지 조건 검사용 궤적
for c = 1:size(cases, 1)
    name = cases{c,1};
    req  = cases{c,2}(:);  ack = logical(cases{c,3}(:));
    eSt  = cases{c,4}(:);  eErr = logical(cases{c,5}(:));  eEn = logical(cases{c,6}(:));
    n = numel(req);
    % t = 0 초기화 틱을 앞에 붙인다 — 입력 0, 기대 st=1·err=0·outEn=0
    reqIn = uint8([0; req]);  ackIn = [false; ack];
    eSt = [1; eSt];  eErr = [false; eErr];  eEn = [false; eEn];
    t = (0:n)' * 1e-3;
    try
        y = simonce(MDL, t, reqIn, ackIn);
    catch e
        fprintf('%s: ERROR %s\n', name, strrep(e.message, newline, ' / '));
        continue
    end
    % 틱 k 의 값 = t == k ms 인 행. 스텝이 정확히 n+1 개여야 한다
    tick = round(y.t * 1000);
    assert(isequal(tick, (0:n)'), '%s: 출력 시각이 0..%d ms 가 아니다 (%s)', name, n, mat2str(tick'));
    okSt  = (y.st == eSt);  okErr = (y.err == eErr);  okEn = (y.outEn == eEn);
    okAll = okSt & okErr & okEn;
    pass  = all(okAll);
    nPass = nPass + pass;
    fprintf('\n%s — %s (틱 %d개 중 불일치 %d)\n', name, tern(pass, '통과', '실패'), n + 1, sum(~okAll));
    fprintf('  틱 | req ack | st err outEn | 기대 st err outEn | 판정\n');
    for k = 1:n + 1
        fprintf('  %2d | %3d %3d | %2d %3d %5d | %7d %3d %5d | %s\n', k - 1, reqIn(k), ackIn(k), ...
            y.st(k), y.err(k), y.outEn(k), eSt(k), eErr(k), eEn(k), tern(okAll(k), '○', '✗'));
    end
    traj{c} = struct('name', name, 'req', double(reqIn), 'ack', ackIn, 'st', y.st, 'err', y.err, 'outEn', y.outEn);
end

fprintf('\n통과 %d/3\n', nPass);

% ── 금지 조건 F1·F2·F3·F4·F6 (사양 §5) — 위 세 궤적에서 (정보, 통과 수에는 안 넣는다) ──
allowed = [1 2; 2 1; 2 4; 4 1; 4 2; 4 8; 8 1; 8 2; 8 4];
for c = 1:numel(traj)
    if isempty(traj{c}), continue; end
    z = traj{c};  k = 2:numel(z.st);
    F1 = all(z.outEn == (z.st == 8));
    chg = z.st(k) ~= z.st(k-1);
    F2 = all(ismember(z.st, [1 2 4 8])) && all(ismember([z.st(k(chg)-1), z.st(k(chg))], allowed, 'rows'));
    m3 = z.err(k-1) & ~z.ack(k) & chg;      F3 = all(z.st(k(m3)) == 1);
    m4 = z.err(k-1) & ~z.err(k);            F4 = all(z.ack(k(m4)));
    m6 = z.req(k) == 0;                     F6 = all(~chg(m6)) && all(~(z.err(k(m6)) & ~z.err(k(m6)-1)));
    fprintf('  %s: F1=%d F2=%d F3=%d F4=%d F6=%d\n', z.name, F1, F2, F3, F4, F6);
end
fprintf('==== test_Esm_ruflo done: 통과 %d/3 ====\n', nPass);

% ══════════════════════════════════════════════════════════════════════
function y = simonce(MDL, t, reqIn, ackIn)
    ds = Simulink.SimulationData.Dataset;
    ds = ds.addElement(named(timeseries(reqIn, t), 'req'));
    ds = ds.addElement(named(timeseries(ackIn, t), 'ack'));
    in = Simulink.SimulationInput(MDL);
    in = in.setExternalInput(ds);
    in = in.setModelParameter('StopTime', sprintf('%.3f', t(end)), 'SaveFormat', 'Dataset', ...
                              'SaveOutput', 'on', 'SaveTime', 'on');
    out = sim(in);
    yo = out.yout;
    y.t     = yo.get('st').Values.Time;
    y.st    = double(yo.get('st').Values.Data);
    y.err   = logical(yo.get('err').Values.Data);
    y.outEn = logical(yo.get('outEn').Values.Data);
end

function ts = named(ts, nm)
    ts.Name = nm;
end

function v = tern(c, a, b)
    if c, v = a; else, v = b; end
end
