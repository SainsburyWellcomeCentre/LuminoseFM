function pLeft = defaultPLeft(nGroups, previous)
% lum.pattern.defaultPLeft proposes a contingency for groups that have no natural one.
%
% Every family but the hand-drawn one knows which side each of its groups is meant to
% pay (lum.pattern.generate, FamilyPLeft). Hand-drawn groups do not, so they get this:
% one group pays either side equally, since there is nothing to discriminate; two give
% the classic fixed contingency, the first paying left and the second right; more sweep
% evenly from left to right, a psychometric session. Values already chosen are kept
% wherever the group still exists, so adding a group does not undo them.
%
% Arguments:
%   nGroups   Number of groups
%   previous  Existing P(left) values to keep where they fit (optional)
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.stimulusSet, lum.pattern.applyContingency

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
