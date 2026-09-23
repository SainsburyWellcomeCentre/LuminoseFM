function [pLeft, typedFor] = typedPLeft(pLeft, typedFor, labels)
% lum.pattern.typedPLeft decides whether P(left) typed for some groups still applies.
%
% A family knows which side each of its groups is meant to pay, and the session uses
% that unless the operator types their own P(left) (S.Task.GroupPLeft, empty for the
% family's). Typed values belong to the groups they were typed for, so the setup
% dialog and the stimulus designer keep them only while the groups stay the same, and
% go back to the family's as soon as the groups change: another family, other levels,
% another count. Values whose groups are not known — from a settings file, or back from
% the designer — are kept when there is one per group.
%
% Arguments:
%   pLeft     P(left) as typed; empty for the family's contingency
%   typedFor  Labels of the groups they were typed for; {} when not known
%   labels    Labels of the groups the stimulus set has now
%
% Returns pLeft, emptied when it no longer applies, and the labels it now belongs to
% ({} when emptied).
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.applyContingency, lum.gui.SetupDialog, lum.gui.StimulusDesigner

if isempty(pLeft)
    pLeft = [];
    typedFor = {};
    return
end
if isempty(typedFor)
    keep = numel(pLeft) == numel(labels);
else
    keep = isequal(reshape(cellstr(typedFor), 1, []), reshape(cellstr(labels), 1, []));
end
if keep
    typedFor = labels;
else
    pLeft = [];
    typedFor = {};
end
