function results = runLuminoseTests(varargin)
% runLuminoseTests runs the LuminoseFM test suite.
%
% Most of the suite is pure functions and needs nothing installed. The state
% machine, window and session tests need Bpod, and start it in emulator mode; they
% refuse to run if a real state machine is connected, so the suite is safe to run on
% the rig computer while an experiment is not in progress.
%
% Usage, from WSL or a terminal:
%   matlab -batch "cd('<repo>'); addpath('tests'); runLuminoseTests"
%
% Options:
%   'Filter'  Run only the named test files, e.g. {'patternTest'}
%
% Returns the matlab.unittest results array.
%
% See also: ensureEmulator, makeTestContext

p = inputParser;
addParameter(p, 'Filter', {}, @(x) iscell(x) || ischar(x));
parse(p, varargin{:});

testsFolder = fileparts(mfilename('fullpath'));
root = fileparts(testsFolder);
addpath(root, fullfile(root, 'hardware'), testsFolder);

% Ordered so that the fast, hardware-free tests report first: if the pure functions
% are broken there is no point starting an emulated session.
files = {'lintTest', 'generateTest', 'patternTest', 'stimulusSetTest', 'cueTimingTest', ...
         'trialSpecTest', 'holdShapingTest', 'barcodeTest', 'settingsTest', ...
         'punishmentTest', 'trainingStageTest', 'scoreTrialTest', 'pulsePalTest', ...
         'sleepTest', 'stateMachineTest', 'windowsTest', 'emulatorSessionTest', ...
         'sleepSessionTest'};
if ~isempty(p.Results.Filter)
    wanted = cellstr(p.Results.Filter);
    files = files(ismember(files, wanted));
end

paths = cellfun(@(f) fullfile(testsFolder, [f '.m']), files, 'UniformOutput', false);
suite = testsuite(paths);

results = run(suite);
disp(table(results));

nFailed = sum([results.Failed]);
fprintf('\n%d of %d tests passed, %d failed, %d incomplete (%.1f s).\n', ...
        sum([results.Passed]), numel(results), nFailed, sum([results.Incomplete]), ...
        sum([results.Duration]));
if nFailed > 0 && ~isempty(getenv('LUMINOSE_TESTS_STRICT'))
    error('lum:tests:failed', '%d test(s) failed.', nFailed);
end
