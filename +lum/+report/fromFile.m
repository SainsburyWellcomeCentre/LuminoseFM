function report = fromFile(dataFile, varargin)
% lum.report.fromFile makes a saved behaviour session's plots and log from its data file.
%
%   report = lum.report.fromFile('D:\luminoseData\LUMS0014\LuminoseFM\Session Data\LUMS0014_LuminoseFM_20260927_130459.mat')
%
% For sessions recorded before the summary plots existed, or to draw a session again with
% the current version: the same summary plots and log the session writes as it ends
% (lum.report.write), and, if asked, the online figure's image beside the data file
% (<data file name>_plots.png) drawn again with the current lum.OnlinePlots
% (lum.report.replayOnlinePlots).
%
% The data file is only read: nothing in it is changed or saved. Files older than 0.9.6 are
% rescored in memory with the current lum.scoreTrial (a side poke after the response window
% was a choice up to 0.9.5), so their plots match what a session records today.
%
% Options:
%   'SummaryPlots'  true (default): 'Session Plots'
%   'Log'           true (default): 'Session Logs'
%   'OnlinePlots'   false (default): true replaces <data file name>_plots.png with the
%                   replayed figure
%
% Returns a struct: .Plots, .Log, .OnlinePlots (the image, or ''), .Rescored (trials whose
% outcome changed), .Problems, .Seconds.
%
% See also: lum.report.write, lum.report.replayOnlinePlots, lum.scoreTrial

p = inputParser;
p.FunctionName = 'lum.report.fromFile';
addParameter(p, 'SummaryPlots', true);
addParameter(p, 'Log', true);
addParameter(p, 'OnlinePlots', false);
parse(p, varargin{:});

timer = tic;
dataFile = char(dataFile);
report = struct('Plots', {{}}, 'Log', '', 'OnlinePlots', '', 'Rescored', 0, ...
                'Problems', {{}}, 'Seconds', 0);
loaded = load(dataFile, 'SessionData');
Data = loaded.SessionData;
if ~isfield(Data, 'Session') || ~isfield(Data.Session, 'Type') || ~strcmp(Data.Session.Type, 'Behaviour')
    error('lum:report:fromFile:notBehaviour', '%s is not a behaviour session.', dataFile);
end
[Data, report.Rescored] = rescoreIfOld(Data);

if p.Results.SummaryPlots
    try
        [report.Plots, problems] = lum.report.summaryPlots(Data, dataFile);
        report.Problems = [report.Problems, problems];
    catch plotError
        report.Problems{end+1} = sprintf('summary plots: %s', plotError.message);
    end
end
if p.Results.Log
    try
        report.Log = lum.report.sessionLog(Data, dataFile);
    catch logError
        report.Problems{end+1} = sprintf('log: %s', logError.message);
    end
end
if p.Results.OnlinePlots
    plots = [];
    try
        plots = lum.report.replayOnlinePlots(Data);
        [report.OnlinePlots, problem] = lum.gui.savePlotsImage(plots.Figure, dataFile);
        if ~isempty(problem)
            report.Problems{end+1} = sprintf('online plots: %s', problem);
        end
    catch replayError
        report.Problems{end+1} = sprintf('online plots: %s', replayError.message);
    end
    if ~isempty(plots)
        plots.close();
    end
end
report.Seconds = toc(timer);
end


function [Data, nChanged] = rescoreIfOld(Data)
% Score every trial again with the current lum.scoreTrial when the file predates 0.9.6.
nChanged = 0;
release = sscanf(regexprep(char(Data.Session.ProtocolVersion), '\+.*$', ''), '%d.%d.%d')';
if numel(release) < 3 || ~isVersionBefore(release, [0 9 6])
    return
end
rig = Data.Session.Rig;
for k = 1:Data.nTrials
    spec = struct('CorrectSide', Data.CorrectSide(k));
    result = lum.scoreTrial(Data.RawEvents.Trial{k}, spec, rig);
    if ~isequaln([result.Outcome result.Choice result.Rewarded], ...
                 [Data.Outcome(k) Data.Choice(k) Data.Rewarded(k)])
        nChanged = nChanged + 1;
    end
    Data.Outcome(k) = result.Outcome;
    Data.Choice(k) = result.Choice;
    Data.Correct(k) = result.Correct;
    Data.Rewarded(k) = result.Rewarded;
    Data.ReactionTime(k) = result.ReactionTime;
end
end


function tf = isVersionBefore(release, reference)
% release < reference, compared part by part.
difference = release(1:3) - reference;
first = find(difference ~= 0, 1);
tf = ~isempty(first) && difference(first) < 0;
end
