function target = folder(dataFile, kind)
% lum.report.folder is where a session's summary plots or log go.
%
%   target = lum.report.folder(dataFile, 'Plots')   % <subject>\LuminoseFM\Session Plots
%   target = lum.report.folder(dataFile, 'Logs')    % <subject>\LuminoseFM\Session Logs
%
% Beside Bpod's 'Session Data' folder, as 'Session Videos' is (lum.dev.Cameras.videoFolder),
% or inside the data file's folder when it is not in one (a test, a file saved by hand).
% The folder is not created here.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.report.summaryPlots, lum.report.sessionLog

names = struct('Plots', 'Session Plots', 'Logs', 'Session Logs');
if ~isfield(names, kind)
    error('lum:report:folder:unknownKind', 'The kind of folder must be Plots or Logs, not %s.', kind);
end
dataFolder = fileparts(char(dataFile));
[parent, name] = fileparts(dataFolder);
if strcmpi(name, 'Session Data')
    target = fullfile(parent, names.(kind));
else
    target = fullfile(dataFolder, names.(kind));
end
