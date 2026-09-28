function tag = fileTag(dataFile, subject)
% lum.report.fileTag is the part of a summary plot's name that says which session it is.
%
%   tag = lum.report.fileTag('...\LUMS0014_LuminoseFM_20260927_130459.mat', 'LUMS0014')
%   % 'LUMS0014_20260927_130459'
%
% The subject and the date and time Bpod put in the data file's name, so plots of one kind
% sort by date within a subject's folder. A data file named otherwise gives its own name.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also lum.report.summaryPlots

[~, name] = fileparts(char(dataFile));
stamp = regexp(name, '\d{8}_\d{6}$', 'match', 'once');
if isempty(stamp)
    tag = name;
    return
end
if isempty(subject)
    subject = regexprep(name, '_LuminoseFM_\d{8}_\d{6}$', '');
end
tag = sprintf('%s_%s', subject, stamp);
