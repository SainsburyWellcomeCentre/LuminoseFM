function headingText = heading(Data, T)
% lum.report.heading is the one line naming a session at the top of each summary plot.
%
%   'LUMS0014  |  2026-09-27 13:07  |  Habituation  |  Pure channel, 2 groups  |  307 trials in
%    87 min  |  LuminoseFM 0.9.7'
%
% Arguments:
%   Data  The session's data
%   T     lum.report.sessionTrials(Data)
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also lum.report.summaryPlots

S = T.S;
stage = 'unknown stage';
if S.Task.TrainingStage >= 1 && S.Task.TrainingStage <= numel(S.Task.TrainingStageNames)
    stage = S.Task.TrainingStageNames{S.Task.TrainingStage};
end
families = lum.pattern.families();
family = families(strcmp({families.Name}, T.stimulusSet.Family));
familyText = T.stimulusSet.Family;
if ~isempty(family)
    familyText = family.Label;
end
if ~S.Session.UseOpto
    familyText = sprintf('%s (light off)', familyText);
end
started = '';
if isfield(Data.Session, 'StartTime')
    started = Data.Session.StartTime(1:min(16, end));
end
versionText = '';
if isfield(Data.Session, 'ProtocolVersion')
    versionText = sprintf('  |  LuminoseFM %s', Data.Session.ProtocolVersion);
end
emulated = '';
if isfield(Data.Session, 'Emulated') && Data.Session.Emulated
    emulated = '  |  EMULATED';
end
subject = T.subject;
if isempty(subject)
    subject = '-';
end
headingText = sprintf('%s  |  %s  |  %s  |  %s, %d group(s)  |  %d trials in %.0f min%s%s', subject, ...
               started, stage, familyText, T.stimulusSet.nGroups, T.n, max(T.finish) / 60, ...
               versionText, emulated);
