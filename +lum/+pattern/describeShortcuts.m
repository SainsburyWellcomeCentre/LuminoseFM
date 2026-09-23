function text = describeShortcuts(ceilings)
% lum.pattern.describeShortcuts says in one line how well one cue alone could do.
%
% The stimulus designer, the setup dialog and the session log show it, so that a set in
% which one channel alone tells the side is seen before a session is run on it.
%
% Example:
%   'One cue alone could score at most: A''s amount 67%, B''s amount 67%, total light
%    50%, A''s time course 67%, B''s time course 67% (the whole pattern: 100%).'
%
% Arguments:
%   ceilings  Struct from lum.pattern.shortcuts (StimulusSet.Shortcuts)
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.shortcuts

names = {'AAmount', 'BAmount', 'TotalLight', 'ATimeCourse', 'BTimeCourse'};
words = {'A''s amount', 'B''s amount', 'total light', 'A''s time course', 'B''s time course'};
parts = {};
for i = 1:numel(names)
    if isfield(ceilings, names{i}) && isfinite(ceilings.(names{i}))
        parts{end+1} = sprintf('%s %.0f%%', words{i}, 100 * ceilings.(names{i})); %#ok<AGROW>
    end
end
if isempty(parts)
    text = '';
    return
end
if strcmp(ceilings.Method, 'threshold')
    lead = 'One cue alone, read against a threshold, could score at most';
else
    lead = 'One cue alone could score at most';
end
text = sprintf('%s: %s (the whole pattern: %.0f%%).', lead, strjoin(parts, ', '), ...
               100 * ceilings.AllLight);
