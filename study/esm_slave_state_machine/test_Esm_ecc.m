% test_Esm_ecc.m — Esm_ecc.slx 의 공개 수용 시험 3개를 sim 으로 돌려 틱 단위로 대조하고 `통과 n/3` 을 출력한다.
%
% 실행:
%   matlab -wait -nosplash -batch "run('C:\Users\leeyj\Documents\yj.lee\ecc\회차\2026-09-17_esm_간단_재대결\test_Esm_ecc.m')" -logfile ...\test.log
%
% 시간 규약: t = 0 은 초기화 틱(입력 무시, st=1·err=0·outEn=0). 시험 입력의 k번째 틱은 t = k ms 에 들어가고
%            그 틱의 출력은 t = k ms 값이다. 그래서 입력 앞에 t = 0 의 0 행을 붙인다.
% 판정: 틱 1~N 의 st·err·outEn 이 기대와 전부 같고, t = 0 행이 (1, 0, 0) 이면 통과.
% 덧붙여 사양표 §5 금지 조건 F1~F6 을 같은 실행의 전 틱에서 센다(통과 n/3 에는 넣지 않는다).
% 이 스크립트는 결과 폴더(OUT) 밖에 아무것도 쓰지 않는다(slprj 는 fileGenControl 로 OUT 안).

OUT = fileparts(mfilename('fullpath'));
MDL = 'Esm_ecc';
SLX = fullfile(OUT, [MDL '.slx']);
DT  = 0.001;

cd(OUT);
Simulink.fileGenControl('set', 'CacheFolder', OUT, 'CodeGenFolder', OUT, 'createDir', true);
if bdIsLoaded(MDL), close_system(MDL, 0); end
load_system(SLX);
fprintf('[test] %s  MATLAB %s  model %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), version, SLX);

%% 공개 수용 시험 3개 — 각 틱 뒤의 기대 출력 (과제 표 그대로)
T = struct('name', {}, 'req', {}, 'ack', {}, 'st', {}, 'err', {}, 'outEn', {});
T(end+1) = struct('name', 'T1 기동·하강', ...
    'req',   [2 0 4 8 8 4 1], 'ack',   [0 0 0 0 0 0 0], ...
    'st',    [2 2 4 8 8 4 1], 'err',   [0 0 0 0 0 0 0], 'outEn', [0 0 0 1 1 0 0]);
T(end+1) = struct('name', 'T2 불법 요청', ...
    'req',   [8 0 0 2 0],     'ack',   [0 0 1 0 0], ...
    'st',    [1 1 1 2 2],     'err',   [1 1 0 0 0],     'outEn', [0 0 0 0 0]);
T(end+1) = struct('name', 'T3 오류 중 요청', ...
    'req',   [2 8 4 1 2 4],   'ack',   [0 0 0 0 1 0], ...
    'st',    [2 2 2 1 2 4],   'err',   [0 1 1 1 0 0],   'outEn', [0 0 0 0 0 0]);

nPass = 0;
runs  = cell(1, numel(T));
for k = 1:numel(T)
    tc = T(k);
    n  = numel(tc.req);
    t  = (0:n)' * DT;                                  % t = 0 (초기화 틱) + 틱 1..n
    req = uint8([0 tc.req(:)']');                      % t = 0 행은 0 (입력 없음)
    ack = logical([0 tc.ack(:)']');
    o = runSim(MDL, t, req, ack);
    runs{k} = struct('t', t, 'req', req, 'ack', ack, 'st', o.st, 'err', o.err, 'outEn', o.outEn);

    okInit = (o.st(1) == 1) && (o.err(1) == 0) && (o.outEn(1) == 0);
    dSt  = double(o.st(2:end))'    ~= tc.st;
    dErr = double(o.err(2:end))'   ~= tc.err;
    dEn  = double(o.outEn(2:end))' ~= tc.outEn;
    nBad = sum(dSt | dErr | dEn);
    pass = okInit && nBad == 0;
    nPass = nPass + pass;
    fprintf('[test] %s : %s — 틱 %d 중 불일치 %d, t=0 초기화 %s\n', tc.name, pf(pass), n, nBad, tf(okInit));
    if ~pass
        fprintf('  틱 | req ack | st(기대/관측) | err(기대/관측) | outEn(기대/관측)\n');
        for i = 1:n
            mark = ' ';
            if dSt(i) || dErr(i) || dEn(i), mark = '*'; end
            fprintf(' %s%2d | %3d %3d | %d/%d | %d/%d | %d/%d\n', mark, i, tc.req(i), tc.ack(i), ...
                tc.st(i), o.st(i+1), tc.err(i), o.err(i+1), tc.outEn(i), o.outEn(i+1));
        end
        if ~okInit, fprintf('  t=0 관측: st=%d err=%d outEn=%d (기대 1 0 0)\n', o.st(1), o.err(1), o.outEn(1)); end
    end
end
fprintf('통과 %d/%d\n', nPass, numel(T));

%% 금지 조건 F1~F6 (사양표 §5) — 3 실행의 전 틱
ALLOWED = [1 2; 2 1; 2 4; 4 1; 4 2; 4 8; 8 1; 8 2; 8 4];
F = struct('name', {}, 'bad', {});
b1 = 0; b2 = 0; b3 = 0; b4 = 0; b5 = 0; b6 = 0;
for k = 1:numel(runs)
    r = runs{k};
    st = double(r.st(:)); err = double(r.err(:)); en = double(r.outEn(:));
    req = double(r.req(:)); ack = double(r.ack(:));
    b1 = b1 + sum(en ~= (st == 8));
    b2 = b2 + sum(~ismember(st, [1 2 4 8]));
    chg = find(st(2:end) ~= st(1:end-1)) + 1;              % st 가 바뀐 틱
    for i = chg(:)'
        if ~ismember([st(i-1) st(i)], ALLOWED, 'rows'), b3 = b3 + 1; end
        if err(i) == 1 && st(i) ~= 1, b4 = b4 + 1; end
    end
    b5 = b5 + sum(ack == 1 & req == 0 & err == 1);
    b6 = b6 + ~(st(1) == 1 && err(1) == 0 && en(1) == 0);
end
F(end+1) = struct('name', 'F1 outEn == (st == 8) 전 틱',                 'bad', b1);
F(end+1) = struct('name', 'F2 st ∈ {1,2,4,8} 전 틱',                    'bad', b2);
F(end+1) = struct('name', 'F3 st 변화는 허용 전이 9개 중 하나',           'bad', b3);
F(end+1) = struct('name', 'F4 err=1 중 st 변화는 Init(1) 로만',           'bad', b4);
F(end+1) = struct('name', 'F5 ack=1·req=0 인 틱의 err 는 0',              'bad', b5);
F(end+1) = struct('name', 'F6 t=0 출력 (1,0,0)',                          'bad', b6);
for i = 1:numel(F)
    fprintf('[forbid] %s : %s — 위반 %d\n', F(i).name, pf(F(i).bad == 0), F(i).bad);
end
fprintf('[forbid] 통과 %d/%d\n', sum([F.bad] == 0), numel(F));

close_system(MDL, 0);

%% ---------------------------------------------------------------- 보조 함수
function o = runSim(mdl, t, req, ack)
    ds = Simulink.SimulationData.Dataset;
    ts = timeseries(req, t); ts.Name = 'req'; ds = ds.addElement(ts, 'req');
    ts = timeseries(ack, t); ts.Name = 'ack'; ds = ds.addElement(ts, 'ack');
    in = Simulink.SimulationInput(mdl);
    in = in.setExternalInput(ds);
    in = in.setModelParameter('StopTime', num2str(t(end)));
    out = sim(in);
    lg = out.logsout;
    o = struct();
    for nm = {'st', 'err', 'outEn'}
        e = lg.get(nm{1});
        o.(nm{1}) = holdOnGrid(e.Values.Time(:), double(e.Values.Data(:)), t);
    end
end

function v = holdOnGrid(tsTime, tsData, t)
    % 로그를 1 ms 격자에 zero-order hold 로 편다. 시각 비교는 정수 tick 으로(부동소수 회피).
    dt = t(2) - t(1);
    k  = round(tsTime / dt);
    kt = round(t / dt);
    v  = zeros(numel(t), 1);
    cur = NaN; j = 1;
    for i = 1:numel(kt)
        while j <= numel(k) && k(j) <= kt(i)
            cur = tsData(j); j = j + 1;      % 같은 tick 에 여러 기록이면 마지막 것
        end
        v(i) = cur;
    end
end

function s = tf(b), if b, s = 'O'; else, s = 'X'; end, end
function s = pf(b), if b, s = '통과'; else, s = '**실패**'; end, end
