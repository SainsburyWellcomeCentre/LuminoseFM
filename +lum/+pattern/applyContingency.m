function stimulusSet = applyContingency(stimulusSet, groupPLeft, reversed)
% lum.pattern.applyContingency says which side each group of a stimulus set pays.
%
% The contingency is the one part of a stimulus set that changes without the patterns
% changing, so it is applied in a step of its own: lum.pattern.stimulusSet ends with it,
% and the setup dialog and the stimulus designer re-apply it to a compiled set when only
% P(left) or the reversal was edited.
%
% Arguments:
%   stimulusSet  A set from lum.pattern.stimulusSet (with its States, for the check
%                below; a set without them is not checked)
%   groupPLeft   P(left) per group, as typed (S.Task.GroupPLeft); empty for the
%                family's own contingency (stimulusSet.FamilyPLeft)
%   reversed     True to swap the sides: P(left) becomes 1 - P(left)
%
% Returns the set with GroupPLeft, BasePLeft, PLeftFromFamily, Reversed, PatternPLeft
% and Shortcuts set.
%
% Errors when groupPLeft does not have one value in [0, 1] per group, or when two
% groups deliver identical light but pay different sides.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.stimulusSet, lum.pattern.shortcuts

if nargin < 3 || isempty(reversed)
    reversed = false;
end
nGroups = stimulusSet.nGroups;
fromFamily = isempty(groupPLeft);
if fromFamily
    base = stimulusSet.FamilyPLeft(:)';
else
    base = double(groupPLeft(:)');
    if numel(base) ~= nGroups
        error('lum:pattern:stimulusSet:contingencyMismatch', ...
              ['P(left) has %d value(s), but the stimulus set has %d group(s): %s. Leave it '...
               'empty for the family''s own contingency.'], numel(base), nGroups, ...
              strjoin(stimulusSet.GroupLabels, ', '));
    end
    if any(~isfinite(base)) || any(base < 0 | base > 1)
        error('lum:pattern:stimulusSet:badPLeft', 'Every P(left) must lie in [0, 1].');
    end
end
pLeft = base;
if reversed
    pLeft = 1 - base;
end

patternPLeft = 0.5 * ones(1, stimulusSet.nPatterns);
decided = stimulusSet.PatternGroup > 0;
patternPLeft(decided) = pLeft(stimulusSet.PatternGroup(decided));

%% Groups the animal could not tell apart
% Identical light paying different sides is a task with no solution: performance
% sits at chance however well the animal learns, and nothing afterwards can tell
% that apart from an untrained animal. Identical groups paying the same side are
% only redundant, and allowed.
if ~stimulusSet.Continuous && isfield(stimulusSet, 'States')
    states = stimulusSet.States;
    for a = 1:stimulusSet.nPatterns
        for b = a + 1:stimulusSet.nPatterns
            if patternPLeft(a) ~= patternPLeft(b) && isequal(states(:, a), states(:, b))
                labels = stimulusSet.GroupLabels;
                error('lum:pattern:stimulusSet:indistinguishable', ...
                      ['Groups %d (%s) and %d (%s) deliver identical light but pay the left '...
                       'port with P = %g and %g, so nothing tells the animal which side is '...
                       'correct. Change the family''s parameters, or give them the same P(left).'], ...
                      a, labels{a}, b, labels{b}, patternPLeft(a), patternPLeft(b));
            end
        end
    end
end

stimulusSet.GroupPLeft = pLeft;
stimulusSet.BasePLeft = base;
stimulusSet.PLeftFromFamily = fromFamily;
stimulusSet.Reversed = logical(reversed);
stimulusSet.PatternPLeft = patternPLeft;
stimulusSet.Shortcuts = lum.pattern.shortcuts(stimulusSet);
