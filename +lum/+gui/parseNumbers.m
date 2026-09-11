function values = parseNumbers(text, what)
% lum.gui.parseNumbers reads a list of numbers typed into a text field.
%
% Several generator parameters are either one number or one per group — lit
% fractions, offsets, phases — and a motif is a list by nature, so the windows take
% them as text: '0.2 0.4 0.6', '1, 3, 2, 0', or blank for "not set". Spaces, commas
% and semicolons all separate, and a repeated separator is not an empty value.
%
% Arguments:
%   text  The typed text, or a numeric value passed straight through
%   what  What the field is, for the error message
%
% Returns a row vector; empty for blank text. 'NaN' is accepted, and means "not
% set" wherever a generator field documents it.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.gui.StimulusDesigner, lum.pattern.withGeneratorDefaults

if isnumeric(text) || islogical(text)
    values = double(text(:)');
    return
end
text = strtrim(char(text));
if isempty(text)
    values = [];
    return
end
tokens = strsplit(text, {' ', ',', ';', sprintf('\t')});
tokens = tokens(~cellfun(@isempty, tokens));
values = str2double(tokens);
bad = isnan(values) & ~strcmpi(tokens, 'nan');
if any(bad)
    error('lum:gui:parseNumbers:notNumbers', '%s: "%s" is not a list of numbers.', what, text);
end
