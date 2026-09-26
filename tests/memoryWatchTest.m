function tests = memoryWatchTest
% memoryWatchTest checks lum.watchMemoryAfterSession: the sampler a desktop session starts
% at its end to record MATLAB's memory and busiest threads while MATLAB sits idle.
tests = functiontests(localfunctions);
end

function testTheSamplerListsTimersAndWritesARowASecond(testCase)
assumeTrue(testCase, ispc, 'The sampler is Windows only');
dataFile = fullfile(tempdir, sprintf('memoryWatchTest_%d.mat', feature('getpid')));
logFile = strrep(dataFile, '.mat', '_memory.csv');
cleanup = onCleanup(@() deleteIfThere(logFile));
probe = timer('Name', 'memoryWatchTest probe', 'Period', 5, 'ExecutionMode', 'fixedRate', ...
              'TimerFcn', @(~, ~) []);
start(probe);
stopProbe = onCleanup(@() delete(probe));
verifyEqual(testCase, lum.watchMemoryAfterSession(dataFile, 3), logFile);
stop(probe);
header = fileread(logFile);
verifySubstring(testCase, header, '# timer "memoryWatchTest probe" running on');
verifySubstring(testCase, header, 'MainThreadCPUSeconds');
deadline = tic;
rows = {};
while toc(deadline) < 30 && numel(rows) < 3
    pause(0.5);
    lines = splitlines(strtrim(fileread(logFile)));
    rows = lines(~startsWith(lines, '#') & ~startsWith(lines, 'Time'));
end
verifyGreaterThanOrEqual(testCase, numel(rows), 3, 'One row a second for 3 s');
fields = strsplit(rows{end}, ',');
verifyEqual(testCase, numel(fields), 8);
verifyGreaterThan(testCase, str2double(fields{3}), 0, 'MATLAB''s private memory, GB');
end

function testNothingIsWatchedWithoutADataFile(testCase)
verifyEqual(testCase, lum.watchMemoryAfterSession('', 3), '');
end

function deleteIfThere(file)
pause(1);  % The sampler's last row
if isfile(file)
    delete(file);
end
end
