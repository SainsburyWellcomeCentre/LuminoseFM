function subject = launchSubject(launchedSubject, selectedSubject, dataFile)
% lum.launchSubject is the subject the operator launched the session for in Bpod's launch manager.
%
%   subject = lum.launchSubject(BpodSystem.GUIData.SubjectName, ...
%                               BpodSystem.Status.CurrentSubjectName, ...
%                               BpodSystem.Path.CurrentDataFile)
%
% Bpod keeps the subject in three places, and only one is always set. The launch
% manager's Launch button writes GUIData.SubjectName every time. Status.CurrentSubjectName
% is written only when the subject list's selection changes, so a subject left selected
% as the launch manager opened comes through empty — which left the subject blank in
% sessions up to 0.6.1. The data file is always in <DataFolder>\<subject>\<protocol>\
% Session Data\. They are tried in that order, the data file's folder only when its path
% has that shape, and '' is returned when none gives a name.
%
% Arguments (each may be empty, or not text):
%   launchedSubject  BpodSystem.GUIData.SubjectName
%   selectedSubject  BpodSystem.Status.CurrentSubjectName
%   dataFile         BpodSystem.Path.CurrentDataFile
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: LuminoseFM, lum.gui.ExperimentForm

subject = textOf(launchedSubject);
if ~isempty(subject)
    return
end
subject = textOf(selectedSubject);
if ~isempty(subject)
    return
end
dataFile = textOf(dataFile);
if isempty(dataFile)
    return
end
parts = strsplit(strrep(dataFile, '\', '/'), '/');
if numel(parts) >= 4 && strcmp(parts{end-1}, 'Session Data')
    subject = parts{end-3};
end


function text = textOf(value)
% Trimmed text, or '' for anything that is not text.
text = '';
if (ischar(value) && (isrow(value) || isempty(value))) || (isstring(value) && isscalar(value))
    text = strtrim(char(value));
end
