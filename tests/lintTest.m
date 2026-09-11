function tests = lintTest
% lintTest runs MATLAB's Code Analyzer over the whole repository.
%
% MATLAB has no compile step, so a typo in a branch that a session happens not to
% take can sit in the repository indefinitely and then fail with an animal in the
% box. checkcode is the closest thing to a compiler available here, and the
% repository is kept at zero messages so that a new one is a signal rather than
% noise to scroll past.
tests = functiontests(localfunctions);
end

function testTheRepositoryHasNoCodeAnalyzerMessages(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
files = [dir(fullfile(root, '*.m'));
         dir(fullfile(root, 'hardware', '*.m'));
         dir(fullfile(root, '+lum', '**', '*.m'));
         dir(fullfile(root, 'tests', '*.m'))];

complaints = {};
for i = 1:numel(files)
    path = fullfile(files(i).folder, files(i).name);
    messages = checkcode(path, '-struct');
    for j = 1:numel(messages)
        complaints{end+1} = sprintf('%s:%d  %s', files(i).name, ...
                                    messages(j).line, messages(j).message); %#ok<AGROW>
    end
end

verifyEmpty(testCase, complaints, ...
            sprintf('Code Analyzer messages:\n  %s', strjoin(complaints, sprintf('\n  '))));
end
