function report = write(Data, dataFile)
% lum.report.write writes a behaviour session's summary plots and log as the session ends.
%
%   report = lum.report.write(BpodSystem.Data, BpodSystem.Path.CurrentDataFile)
%
% Called by LuminoseFM's teardown once the data are saved, the video stopped and the
% devices released, so it adds nothing to the time the rig is held and changes nothing in
% the data file: lum.report.summaryPlots into 'Session Plots', lum.report.sessionLog into
% 'Session Logs', beside 'Session Data'. It takes a few seconds (about 0.3 s a plot), which
% the session prints as it starts.
%
% Returns a struct: .Plots (files written), .Log (file, or ''), .Problems (one message per
% thing not written) and .Seconds. Never throws: the session is already saved, and a plot
% that cannot be drawn must not stop the teardown.
%
% See also: lum.report.summaryPlots, lum.report.sessionLog, lum.report.fromFile

timer = tic;
report = struct('Plots', {{}}, 'Log', '', 'Problems', {{}}, 'Seconds', 0);
try
    [report.Plots, report.Problems] = lum.report.summaryPlots(Data, dataFile);
catch plotError
    report.Problems{end+1} = sprintf('summary plots: %s', plotError.message);
end
try
    report.Log = lum.report.sessionLog(Data, dataFile);
catch logError
    report.Problems{end+1} = sprintf('log: %s', logError.message);
end
report.Seconds = toc(timer);
end
