function pLeft = defaultPLeft(nGroups, previous)
% lum.pattern.defaultPLeft proposes a contingency for a given number of groups.
%
% One group is a session with nothing to discriminate, so it pays either side
% equally. Two groups give the classic fixed contingency, the first paying left
% and the second right. More groups sweep evenly from left to right, which is a
% psychometric session. Values the operator already chose are kept wherever the
% group still exists, so adding a group does not undo their edits.
%
% Arguments:
%   nGroups   Number of groups (2 in continuous mode: A-led and B-led)
%   previous  Existing P(left) values to keep where they fit (optional)
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.stimulusSet, lum.gui.StimulusDesigner

if nGroups <= 1
    pLeft = 0.5;
else
    pLeft = linspace(1, 0, nGroups);
end
if nargin > 1 && ~isempty(previous) && numel(previous) ~= nGroups
    kept = min(numel(previous), nGroups);
    % Only keep old values when the count changed by adding or removing groups at
    % the end; a fresh sweep is better than a half-kept one when it shrank to two.
    if nGroups > 2 && numel(previous) > 2
        pLeft(1:kept) = previous(1:kept);
    end
elseif nargin > 1 && numel(previous) == nGroups
    pLeft = previous(:)';
end
