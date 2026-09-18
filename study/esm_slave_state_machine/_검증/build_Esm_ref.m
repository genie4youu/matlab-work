% build_check — 검증 세션의 하네스 자가검사용 Esm 모델 (채점 대상 아님)
here = fileparts(fileparts(mfilename('fullpath')));
MDL = 'Esm_ref'; bdclose('all');
Simulink.fileGenControl('set', 'CacheFolder', fullfile(here, '_slprj'), 'CodeGenFolder', fullfile(here, '_slprj'), 'createDir', true);
new_system(MDL); load_system(MDL);
set_param(MDL, 'SolverType', 'Fixed-step', 'Solver', 'FixedStepDiscrete', 'FixedStep', '0.001', 'StopTime', '0.02');
add_block('simulink/Sources/In1', [MDL '/req'], 'Position', [30 40 60 56], 'OutDataTypeStr', 'uint8');
add_block('simulink/Sources/In1', [MDL '/ack'], 'Position', [30 90 60 106], 'OutDataTypeStr', 'boolean');
add_block('simulink/Sinks/Out1', [MDL '/st'], 'Position', [300 40 330 56]);
add_block('simulink/Sinks/Out1', [MDL '/err'], 'Position', [300 90 330 106]);
add_block('simulink/Sinks/Out1', [MDL '/outEn'], 'Position', [300 140 330 156]);
add_block('sflib/Chart', [MDL '/Chart'], 'Position', [120 30 240 160]);
rt = sfroot; ch = rt.find('-isa', 'Stateflow.Chart', 'Path', [MDL '/Chart']);
ch.ActionLanguage = 'C'; ch.ChartUpdate = 'DISCRETE'; ch.SampleTime = '0.001';
d = Stateflow.Data(ch); d.Name = 'req'; d.Scope = 'Input'; d.DataType = 'uint8';
d = Stateflow.Data(ch); d.Name = 'ack'; d.Scope = 'Input'; d.DataType = 'boolean';
d = Stateflow.Data(ch); d.Name = 'st'; d.Scope = 'Output'; d.DataType = 'uint8';
d = Stateflow.Data(ch); d.Name = 'err'; d.Scope = 'Output'; d.DataType = 'boolean';
d = Stateflow.Data(ch); d.Name = 'outEn'; d.Scope = 'Output'; d.DataType = 'boolean';
M = Stateflow.State(ch); M.Name = 'Machine'; M.Position = [20 20 520 320];
M.LabelString = sprintf('Machine\nduring: err = err && !ack;');
names = {'Init', 'PreOp', 'SafeOp', 'Op'}; codes = [1 2 4 8]; S = struct();
pos = {[40 60 100 60], [200 60 100 60], [360 60 100 60], [200 200 100 60]};
legal = {[2], [1 4], [1 2 8], [1 2 4]};
for i = 1:4
    s = Stateflow.State(M); s.Name = names{i}; s.Position = pos{i};
    cond = sprintf('req != 0 && req != %d', codes(i));
    notLegal = strjoin(arrayfun(@(c) sprintf('req != %d', c), legal{i}, 'UniformOutput', false), ' && ');
    s.LabelString = sprintf('%s\nentry: st = %d; outEn = %d;\nduring: err = err || (%s && %s);', names{i}, codes(i), codes(i) == 8, cond, notLegal);
    S.(names{i}) = s;
end
dt = Stateflow.Transition(M); dt.Destination = S.Init; dt.DestinationOClock = 0; dt.SourceEndpoint = [90 40]; dt.MidPoint = [90 50];
dt = Stateflow.Transition(ch); dt.Destination = M; dt.DestinationOClock = 0; dt.SourceEndpoint = [270 5]; dt.MidPoint = [270 12];
k = 0;
for i = 1:4
    for c = legal{i}
        j = find(codes == c); t = Stateflow.Transition(M); t.Source = S.(names{i}); t.Destination = S.(names{j});
        if c == 1, t.LabelString = '[req == 1]'; else, t.LabelString = sprintf('[req == %d && !err]', c); end
        k = k + 1; t.ExecutionOrder = 1;
    end
end
add_line(MDL, 'req/1', 'Chart/1'); add_line(MDL, 'ack/1', 'Chart/2');
add_line(MDL, 'Chart/1', 'st/1'); add_line(MDL, 'Chart/2', 'err/1'); add_line(MDL, 'Chart/3', 'outEn/1');
save_system(MDL, fullfile(here, [MDL '.slx']));
fprintf('saved, transitions %d\n', k);
