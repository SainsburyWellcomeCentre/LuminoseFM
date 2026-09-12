function choices = stepChoices(testPulses)
% lum.sleep.stepChoices lists what a test-pulse schedule may contain.
%
% The one list of step kinds, channel choices and probe modes, read by the schedule
% compiler (lum.sleep.testPulsePlan), the test-pulse designer and the tests, so the
% three cannot disagree about what a step may be.
%
% Arguments:
%   testPulses  Optional S.Sleep.TestPulses; its train names become step kinds
%
% Returns a struct:
%   .Kinds       {'Probe', <each train's Name>, 'Rest'}
%   .Channels    {'A and B', 'A', 'B', 'Alternate A and B'}: both channels together,
%                one of them, or successive epochs switching between A and B
%   .ProbeModes  {'Paired', 'Single'}
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sleep.testPulsePlan, lum.gui.TestPulseDesigner

choices = struct();
choices.Channels = {'A and B', 'A', 'B', 'Alternate A and B'};
choices.ProbeModes = {'Paired', 'Single'};
trainNames = {};
if nargin >= 1 && isstruct(testPulses) && isfield(testPulses, 'Trains') && ~isempty(testPulses.Trains)
    trainNames = {testPulses.Trains.Name};
end
choices.Kinds = [{'Probe'}, reshape(trainNames, 1, []), {'Rest'}];
