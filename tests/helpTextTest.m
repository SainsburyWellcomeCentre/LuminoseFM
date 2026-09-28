function tests = helpTextTest
% helpTextTest holds every file's help text and comments to the repository's standard.
%
% MATLAB shows a file's help with help, doc and the help browser, lists a package's
% files by their H1 lines (help lum, help lum.pattern), and links the names on a See also
% line. This checks the parts of that a program can check (docs/code-style.md):
%
%   help      every file starts with help text, right after its function or classdef line
%   H1        the first help line names the file (lum.dev.PulsePal for a file in +lum/+dev,
%             TestSyncLine for one in hardware/), says what it does in one sentence ending
%             in a full stop, and fits on one line: the next help line is blank
%   See also  every file outside tests/ ends its help with one, written See also (no
%             colon), and every name on it that belongs to this repository exists: a
%             file, a class, or a method of one
%   comments  no line longer than 100 characters, ASCII only (a Windows console drops
%             anything else from help and printed text), and no Markdown emphasis
%
% Whether a comment is true, and whether it is needed, is for the author and the reviewer:
% docs/code-style.md says how to judge both. Pure: reads files and asks MATLAB where names
% are; no Bpod.
%
% See also lintTest, runLuminoseTests
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
testCase.TestData.root = root;
testCase.TestData.files = repositoryFiles(root);
end

function testEveryFileStartsWithHelpText(testCase)
problems = {};
for f = testCase.TestData.files
    help = helpLines(f.path);
    if isempty(help) || isempty(strtrim(help{1}))
        problems{end+1} = f.relative; %#ok<AGROW>
    end
end
verifyEmpty(testCase, problems, sprintf('No help text right after the declaration:\n  %s', ...
            strjoin(problems, sprintf('\n  '))));
end

function testEveryH1NamesItsFileInOneSentenceOnOneLine(testCase)
problems = {};
for f = testCase.TestData.files
    help = helpLines(f.path);
    if isempty(help)
        continue
    end
    h1 = strtrim(help{1});
    raw = firstHelpLine(f.path);
    if ~startsWith(h1, [f.name ' '])
        problems{end+1} = sprintf('%s: does not start with "%s"', f.relative, f.name); %#ok<AGROW>
    elseif ~endsWith(h1, '.')
        problems{end+1} = sprintf('%s: does not end with a full stop', f.relative); %#ok<AGROW>
    elseif strlength(raw) > 100
        problems{end+1} = sprintf('%s: %d characters, more than 100', f.relative, strlength(raw)); %#ok<AGROW>
    elseif numel(help) > 1 && ~isempty(strtrim(help{2}))
        problems{end+1} = sprintf('%s: runs on to a second line', f.relative); %#ok<AGROW>
    end
end
verifyEmpty(testCase, problems, sprintf('H1 lines:\n  %s', strjoin(problems, sprintf('\n  '))));
end

function testEveryFileOutsideTestsHasASeeAlsoLine(testCase)
problems = {};
for f = testCase.TestData.files
    if startsWith(f.relative, 'tests/')
        continue
    end
    if isempty(seeAlsoItems(helpLines(f.path)))
        problems{end+1} = f.relative; %#ok<AGROW>
    end
end
verifyEmpty(testCase, problems, sprintf('No "See also" line in the help:\n  %s', ...
            strjoin(problems, sprintf('\n  '))));
end

function testSeeAlsoIsWrittenAsMATLABWritesIt(testCase)
problems = {};
for f = testCase.TestData.files
    text = fileread(f.path);
    if ~isempty(regexp(text, '^\s*%\s*See also:', 'once', 'lineanchors'))
        problems{end+1} = f.relative; %#ok<AGROW>
    end
end
verifyEmpty(testCase, problems, sprintf('"See also:" with a colon; write "See also":\n  %s', ...
            strjoin(problems, sprintf('\n  '))));
end

function testEveryRepositoryNameOnASeeAlsoLineExists(testCase)
local = [{testCase.TestData.files.name}, {'lum'}];
problems = {};
for f = testCase.TestData.files
    for item = seeAlsoItems(helpLines(f.path))
        name = item{1};
        isOurs = startsWith(name, 'lum.') || ismember(name, local);
        if isOurs && ~nameExists(name)
            problems{end+1} = sprintf('%s: %s', f.relative, name); %#ok<AGROW>
        end
    end
end
verifyEmpty(testCase, problems, sprintf('See also names that do not exist:\n  %s', ...
            strjoin(problems, sprintf('\n  '))));
end

function testNoCommentLineIsLongerThan100Characters(testCase)
problems = eachCommentLine(testCase, @(line) strlength(line) > 100);
verifyEmpty(testCase, problems, sprintf('Comment lines over 100 characters:\n  %s', ...
            strjoin(problems, sprintf('\n  '))));
end

function testCommentsAreASCII(testCase)
problems = eachCommentLine(testCase, @(line) any(double(char(line)) > 127));
verifyEmpty(testCase, problems, sprintf(['Comments with characters outside ASCII (a Windows '...
            'console drops them from help):\n  %s'], strjoin(problems, sprintf('\n  '))));
end

function testCommentsCarryNoMarkdownEmphasis(testCase)
emphasis = @(line) ~isempty(regexp(line, '\*\*\w|(?<![\w*])\*[A-Za-z][A-Za-z'' ]*[A-Za-z]\*(?![\w*])', ...
                                   'once'));
problems = eachCommentLine(testCase, emphasis);
verifyEmpty(testCase, problems, sprintf(['Markdown emphasis in comments (help prints the '...
            'asterisks):\n  %s'], strjoin(problems, sprintf('\n  '))));
end


function files = repositoryFiles(root)
% Every .m file the suite and the help cover, with the name MATLAB knows it by.
listing = [dir(fullfile(root, '*.m')); dir(fullfile(root, 'hardware', '*.m'));
           dir(fullfile(root, '+lum', '**', '*.m')); dir(fullfile(root, 'tests', '*.m'))];
files = struct('path', {}, 'relative', {}, 'name', {});
for k = 1:numel(listing)
    path = fullfile(listing(k).folder, listing(k).name);
    relative = strrep(extractAfter(path, strlength(root) + 1), '\', '/');
    parts = strsplit(extractBefore(relative, strlength(relative) - 1), '/');
    packages = parts(startsWith(parts, '+'));
    name = strjoin([erase(packages, '+'), parts(end)], '.');
    files(end+1) = struct('path', path, 'relative', relative, 'name', name); %#ok<AGROW>
end
end

function lines = helpLines(path)
% The help text: the comment lines straight after the first line, without their '%'.
lines = {};
text = splitlines(string(fileread(path)));
for k = 2:numel(text)
    line = strtrim(text(k));
    if ~startsWith(line, '%')
        break
    end
    lines{end+1} = char(extractAfter(line, 1)); %#ok<AGROW>
end
end

function line = firstHelpLine(path)
% The first help line as written, indent and all.
text = splitlines(string(fileread(path)));
line = '';
if numel(text) >= 2
    line = char(text(2));
end
end

function items = seeAlsoItems(help)
% The names on the help's See also line and the lines that continue it.
items = {};
start = find(startsWith(strtrim(help), 'See also'), 1);
if isempty(start)
    return
end
text = regexprep(strtrim(help{start}), '^See also:?', '');
for k = start + 1:numel(help)
    if isempty(strtrim(help{k}))
        break
    end
    text = [text ' ' strtrim(help{k})]; %#ok<AGROW>
end
items = strtrim(strsplit(text, ','));
items = items(~cellfun(@isempty, items));
end

function tf = nameExists(name)
% A function or class on the path, a namespace, or a method of a class.
tf = ~isempty(which(name)) || exist(name, 'class') == 8 ...
     || ~isempty(meta.package.fromName(name));
if tf
    return
end
owner = regexprep(name, '\.[^.]+$', '');
method = regexp(name, '[^.]+$', 'match', 'once');
tf = exist(owner, 'class') == 8 && any(strcmp(method, methods(owner)));
end

function problems = eachCommentLine(testCase, isProblem)
% 'file:line' for every comment line (a whole-line comment) for which isProblem is true.
problems = {};
for f = testCase.TestData.files
    text = splitlines(string(fileread(f.path)));
    for k = 1:numel(text)
        line = text(k);
        if startsWith(strtrim(line), '%') && isProblem(line)
            problems{end+1} = sprintf('%s:%d', f.relative, k); %#ok<AGROW>
        end
    end
end
end
