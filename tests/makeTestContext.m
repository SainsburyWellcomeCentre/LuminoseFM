function context = makeTestContext(varargin)
% makeTestContext builds a lum.buildTrialSM context with null devices.
%
% Everything the trial builder needs, with no hardware attached: the device shims are
% the null implementations, so a state machine can be assembled and inspected on any
% machine. Settings are taken as given, so a test changes them first and then asks for
% a context — the components, the stimulus set and the trial spec all follow from them.
%
% Options (name/value), all defaulted:
%   'Settings'     Settings struct (default lum.defaultSettings)
%   'Spec'         Trial spec (default: the first group paying 'Side', light on)
%   'Side'         Rewarded side of the default spec: 1 left (default), 2 right
%   'SyncChannel'  Output channel to stand in for the sync TTL. The emulated r0.7-1.0
%                  has no Flex I/O, so a test that needs the sync line has to borrow
%                  a channel that exists, e.g. 'BNC2'.
%
% See also: lum.buildTrialSM, stateMachineTest

p = inputParser;
addParameter(p, 'Settings', lum.defaultSettings);
addParameter(p, 'Spec', []);
addParameter(p, 'Side', 1);
addParameter(p, 'SyncChannel', '');
parse(p, varargin{:});

S = p.Results.Settings;
S.Session.MaxTrials = min(S.Session.MaxTrials, 50);  % Nothing here needs a long order
rig = RigConfig;

devices = struct();
devices.emulated = true;
devices.pulsePal = lum.dev.NullPulsePal('test context');
devices.hifi = lum.dev.NullHiFi(rig.Sound.Module, S.Sound.SamplingRate, 'test context');
devices.flex = lum.dev.NullFlex('test context');

syncChannel = p.Results.SyncChannel;
if ~isempty(syncChannel)
    rig.Sync.Channel = syncChannel;
    rig.Available.Sync = true;
    devices.flex = lum.dev.Flex([], NaN, syncChannel, true);
end

stimulusSet = lum.pattern.stimulusSet(S, lum.timerBudget(S, rig), rig.Opto.nChannels);

spec = p.Results.Spec;
if isempty(spec)
    spec = lum.nextTrialSpec(S, stimulusSet, stimulusSet.TrialPattern, lum.newHistory(10), 1);
    side = p.Results.Side;
    group = min(side, stimulusSet.nGroups);
    spec.PatternIndex = find(stimulusSet.PatternGroup == group, 1);
    spec.StimulusGroup = group;
    spec.CorrectSide = side;
    spec.RewardedSides = side;
end

[cue, stimulus] = lum.stim.build(S);
context = struct('S', S, 'rig', rig, 'devices', devices, 'spec', spec, ...
                 'pattern', lum.pattern.patternAt(stimulusSet, spec.PatternIndex), ...
                 'sounds', testSoundMap(stimulusSet), 'cue', {cue}, ...
                 'stimulus', {stimulus}, 'valveTimes', [0.02 0.02]);


function sounds = testSoundMap(stimulusSet)
% The sound slots lum.loadSounds could have created, without a module to load them.
sounds = containers.Map('KeyType', 'char', 'ValueType', 'double');
sounds('Noise') = 1;
sounds('Cue') = 2;
for k = 1:stimulusSet.nGroups
    sounds(sprintf('Group%d', k)) = 2 + k;
end
sounds('LeftTone') = 3 + stimulusSet.nGroups;
sounds('RightTone') = 4 + stimulusSet.nGroups;
sounds('CueTail') = 5 + stimulusSet.nGroups;
