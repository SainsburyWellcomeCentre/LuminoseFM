function pattern = validate(pattern, timerBudget)
% lum.pattern.validate canonicalises a light pattern and errors if it is unusable.
%
% Arguments:
%   pattern      Light pattern struct
%   timerBudget  Global timers available for light segments
%
% Returns the canonical form.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.canonicalise, lum.pattern.check

pattern = lum.pattern.canonicalise(pattern);
problems = lum.pattern.check(pattern, timerBudget);
if ~isempty(problems)
    error('lum:pattern:invalid', 'Pattern "%s" is not usable:\n  - %s', ...
          pattern.Name, strjoin(problems, sprintf('\n  - ')));
end
