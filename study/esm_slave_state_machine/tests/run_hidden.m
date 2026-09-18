function R = run_hidden(slxPath, casesFile, outMd)
%RUN_HIDDEN  모델 하나를 시험 집합으로 채점한다. 각 쪽의 주장은 쓰지 않는다.
%   R = run_hidden('C:\...\Esm.slx')                          → hidden_cases.mat (숨은 14)
%   R = run_hidden('C:\...\Esm.slx', 'public')                → public_cases (공개 3)
%   R = run_hidden(slx, casesFile, 'C:\...\채점.md')          → 결과 표 저장
%
%   구동 규칙(과제와 동일): 고정 스텝 1 ms. t=0 은 초기화 틱(입력 0, 기대 st=1·err=0·outEn=0), k번째 입력은 t = k ms.
%   루트 Inport req(uint8)·ack(boolean), 루트 Outport st·err·outEn 을 이름으로 찾는다(포트 번호 무관).
    here = fileparts(mfilename('fullpath'));
    if nargin < 2 || isempty(casesFile), casesFile = fullfile(here, 'hidden_cases.mat'); end
    if strcmp(casesFile, 'public')
        P = public_cases(); C = struct('name', {}, 'in', {}, 'exp', {});
        for i = 1:numel(P), [st, err, oe] = esm_ref(P(i).in(:,1), P(i).in(:,2)); C(end+1) = struct('name', P(i).name, 'in', P(i).in, 'exp', [st err oe]); end %#ok<AGROW>
    else
        S = load(casesFile); C = S.C;
    end
    [mdlDir, mdl] = fileparts(slxPath);
    bdclose('all'); load_system(slxPath);
    inp = find_system(mdl, 'SearchDepth', 1, 'BlockType', 'Inport'); outp = find_system(mdl, 'SearchDepth', 1, 'BlockType', 'Outport');
    inName = cellfun(@(b) get_param(b, 'Name'), inp, 'UniformOutput', false); outName = cellfun(@(b) get_param(b, 'Name'), outp, 'UniformOutput', false);
    inPort = cellfun(@(b) str2double(get_param(b, 'Port')), inp); outPort = cellfun(@(b) str2double(get_param(b, 'Port')), outp);
    need = {'req', 'ack'}; types = {'uint8', 'logical'}; needOut = {'st', 'err', 'outEn'};
    for k = 1:numel(need), assert(any(strcmp(inName, need{k})), 'Inport %s 없음', need{k}); end
    for k = 1:numel(needOut), assert(any(strcmp(outName, needOut{k})), 'Outport %s 없음', needOut{k}); end
    R = struct('name', {}, 'ticks', {}, 'mismatch', {}, 'first_bad', {}, 'pass', {}, 'err', {});
    for i = 1:numel(C)
        in = [zeros(1, numel(need)); C(i).in]; N = size(in, 1); t = (0:N-1)' * 0.001;
        ds = Simulink.SimulationData.Dataset;
        [~, order] = sort(inPort);
        for k = 1:numel(order)                      % Inport 포트 순서대로 요소를 넣는다
            nm = inName{order(k)}; col = find(strcmp(need, nm));
            if strcmp(types{col}, 'logical'), v = logical(in(:, col)); else, v = cast(in(:, col), types{col}); end
            ts = timeseries(v, t); ts.Name = nm;
            ds = ds.addElement(ts, nm);
        end
        exp = [1 0 0; C(i).exp];
        try
            simIn = Simulink.SimulationInput(mdl);
            simIn = simIn.setModelParameter('StopTime', num2str(t(end)), 'SolverType', 'Fixed-step', 'FixedStep', '0.001', ...
                'LoadExternalInput', 'on', 'ExternalInput', 'ds', 'SaveOutput', 'on', 'SaveFormat', 'Dataset', 'OutputSaveName', 'yout', ...
                'SaveTime', 'on', 'TimeSaveName', 'tout');
            simIn = simIn.setVariable('ds', ds);
            so = sim(simIn);
            y = so.yout; got = zeros(N, 3);
            for k = 1:3
                col = find(strcmp(outName, needOut{k})); el = y.get(outPort(col));
                v = double(el.Values.Data(:)); tt = el.Values.Time(:);
                got(:, k) = interp1(tt, v, t, 'previous', 'extrap');
            end
            bad = find(any(got ~= exp, 2)); fb = 0; if ~isempty(bad), fb = bad(1) - 1; end
            R(end+1) = struct('name', C(i).name, 'ticks', N-1, 'mismatch', numel(bad), 'first_bad', fb, 'pass', isempty(bad), 'err', ''); %#ok<AGROW>
        catch e
            R(end+1) = struct('name', C(i).name, 'ticks', N-1, 'mismatch', N, 'first_bad', 0, 'pass', false, 'err', e.message); %#ok<AGROW>
        end
    end
    bdclose('all');
    np = sum([R.pass]); fprintf('%s: %d / %d 통과 (틱 불일치 합계 %d)\n', mdl, np, numel(R), sum([R.mismatch]));
    if nargin >= 3 && ~isempty(outMd)
        L = {sprintf('# 채점 — %s', slxPath), '', sprintf('> 시험 %d개 · 통과 %d · 틱 불일치 합계 %d · %s', numel(R), np, sum([R.mismatch]), datestr(now, 'yyyy-mm-dd HH:MM')), '', '| 시험 | 틱 | 불일치 틱 수 | 첫 불일치 틱 | 판정 | 오류 |', '| --- | --- | --- | --- | --- | --- |'};
        for i = 1:numel(R), L{end+1} = sprintf('| %s | %d | %d | %d | %s | %s |', R(i).name, R(i).ticks, R(i).mismatch, R(i).first_bad, tern(R(i).pass, '○', '✗'), strrep(R(i).err, '|', '\|')); end %#ok<AGROW>
        fid = fopen(outMd, 'w', 'n', 'UTF-8'); fprintf(fid, '%s\n', L{:}); fclose(fid);
    end
end

function v = tern(c, a, b)
    if c, v = a; else, v = b; end
end
