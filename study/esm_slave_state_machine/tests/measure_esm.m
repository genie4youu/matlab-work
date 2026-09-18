function M = measure_esm(sideDir, hiddenDir)
%MEASURE_ESM  한 쪽의 build_Esm.m 을 다시 돌리고, API 로 직접 세고, 공개·숨은 시험으로 채점한다. 각 쪽의 주장은 쓰지 않는다.
    addpath('C:\Users\leeyj\matlab-work\_shared\harness');
    addpath('C:\Users\leeyj\matlab-work\_shared\harness\build');
    addpath(hiddenDir);
    MDL = 'Esm';
    M = struct('side', sideDir, 'build_ok', false, 'build_err', '', 'build_s', NaN, 'update_ok', false, 'update_err', '', ...
               'compare_total', NaN, 'compare_err', '', 'charts', 0, 'states', 0, 'transitions', 0, 'junctions', 0, 'data', 0, ...
               'state_max', 0, 'state_max_name', '', 'data_max', 0, 'data_max_name', '', 'label_line_max', 0, 'label_line_max_text', '', ...
               'action_line_max', 0, 'action_line_max_text', '', 'over', {{}}, 'public_pass', NaN, 'public_n', 3, 'hidden_pass', NaN, 'hidden_n', 14, ...
               'hidden_mismatch_ticks', NaN, 'hidden_fails', {{}}, 'png', '');
    warning('off', 'all'); bdclose('all'); Simulink.fileGenControl('reset');
    old = cd(sideDir); c = onCleanup(@() cd(old));
    t0 = tic;
    try, run(fullfile(sideDir, 'build_Esm.m')); M.build_ok = true; catch e, M.build_err = e.message; end
    M.build_s = round(toc(t0));
    slx = fullfile(sideDir, [MDL '.slx']);
    if ~isfile(slx), M.build_err = [M.build_err ' | slx 없음']; warning('on','all'); return; end
    bdclose('all'); load_system(slx);
    try, set_param(MDL, 'SimulationCommand', 'update'); pause(1); M.update_ok = true; catch e, M.update_err = e.message; end
    dumpDir = fullfile(sideDir, '_덤프_독립');
    try
        emit_dump(MDL, dumpDir); emit_transtable(dumpDir);
        rep = compare_spec(fullfile(sideDir, 'Esm_사양.md'), dumpDir); M.compare_total = rep.total;
    catch e, M.compare_err = e.message; end
    rt = sfroot; mh = rt.find('-isa', 'Simulink.BlockDiagram', 'Name', MDL); charts = mh.find('-isa', 'Stateflow.Chart'); M.charts = numel(charts);
    for k = 1:numel(charts)
        ch = charts(k);
        st = ch.find('-isa', 'Stateflow.State'); tr = ch.find('-isa', 'Stateflow.Transition'); jn = ch.find('-isa', 'Stateflow.Junction'); dt = [ch.find('-isa', 'Stateflow.Data'); ch.find('-isa', 'Stateflow.Event')];
        M.states = M.states + numel(st); M.transitions = M.transitions + numel(tr); M.junctions = M.junctions + numel(jn); M.data = M.data + numel(dt);
        for i = 1:numel(st)
            n = st(i).Name; if numel(n) > M.state_max, M.state_max = numel(n); M.state_max_name = n; end; if numel(n) > 12, M.over{end+1} = ['State:' n]; end
            lines = strsplit(st(i).LabelString, newline);
            for j = 2:numel(lines), s = strtrim(lines{j}); if numel(s) > M.action_line_max, M.action_line_max = numel(s); M.action_line_max_text = s; end; if numel(s) > 40, M.over{end+1} = ['Action:' s]; end; end
        end
        for i = 1:numel(dt), n = dt(i).Name; if numel(n) > M.data_max, M.data_max = numel(n); M.data_max_name = n; end; if numel(n) > 8, M.over{end+1} = ['Data:' n]; end; end
        for i = 1:numel(tr)
            L = tr(i).LabelString; if isempty(L), continue; end
            lines = strsplit(L, newline);
            for j = 1:numel(lines), s = strtrim(lines{j}); if numel(s) > M.label_line_max, M.label_line_max = numel(s); M.label_line_max_text = s; end; if numel(s) > 40, M.over{end+1} = ['Trans:' s]; end; end
        end
        try, png = fullfile(sideDir, sprintf('Esm_chart%d.png', k)); sfprint(ch, 'png', png); M.png = [M.png png ';']; catch e2, M.png = [M.png 'ERR:' e2.message ';']; end
    end
    bdclose('all');
    % 채점 — 공개 3 · 숨은 14
    try
        Rp = run_hidden(slx, 'public', fullfile(sideDir, '채점_공개.md')); M.public_pass = sum([Rp.pass]); M.public_n = numel(Rp);
        Rh = run_hidden(slx, '', fullfile(sideDir, '채점_숨은.md')); M.hidden_pass = sum([Rh.pass]); M.hidden_n = numel(Rh);
        M.hidden_mismatch_ticks = sum([Rh.mismatch]); M.hidden_fails = {Rh(~[Rh.pass]).name};
    catch e, M.compare_err = [M.compare_err ' | 채점: ' e.message]; end
    fid = fopen(fullfile(sideDir, '독립측정.json'), 'w', 'n', 'UTF-8'); fwrite(fid, jsonencode(M, 'PrettyPrint', true), 'char'); fclose(fid);
    bdclose('all'); warning('on', 'all');
end
