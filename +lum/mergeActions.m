function actions = mergeActions(varargin)
% lum.mergeActions concatenates OutputActions lists, letting later values win.
%
% Bpod output actions persist until a later state changes them, so most states in
% the trial have to both switch something off and switch something else on — and
% those two lists routinely name the same channel. AddState rejects that outright
% ("Duplicate output actions detected in state: X. Only one value for PWM2 is
% allowed"), so the lists cannot simply be concatenated.
%
% This resolves them the way the intent reads: the last value given for a channel
% is the one that survives, and each channel appears once, in the order it was
% first mentioned. That makes {stopEverything, thenThisOne} a safe idiom.
%
% Arguments:
%   Any number of OutputActions cell arrays, each {channel, value, channel, value, ...}
%
% Returns one OutputActions cell array with no repeated channel.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% Example:
%   lum.mergeActions({'PWM2', 0}, {'PWM2', 100})   % -> {'PWM2', 100}
%
% See also: lum.buildTrialSM, lum.stim.Component

% Preallocated to the worst case — every pair distinct — and trimmed at the end.
capacity = sum(cellfun(@numel, varargin)) / 2;
channels = cell(1, ceil(capacity));
values = cell(1, ceil(capacity));
nChannels = 0;

for i = 1:numel(varargin)
    list = varargin{i};
    if isempty(list)
        continue
    end
    if mod(numel(list), 2) ~= 0
        error('lum:mergeActions:oddLength', ...
              ['Output actions must come in channel/value pairs; argument %d has %d '...
               'element(s).'], i, numel(list));
    end
    for k = 1:2:numel(list)
        channel = list{k};
        if ~ischar(channel) && ~isstring(channel)
            error('lum:mergeActions:badChannel', ...
                  'Output action channel names must be text; argument %d, element %d is not.', ...
                  i, k);
        end
        channel = char(channel);
        existing = find(strcmp(channels(1:nChannels), channel), 1);
        if isempty(existing)
            nChannels = nChannels + 1;
            channels{nChannels} = channel;
            values{nChannels} = list{k+1};
        else
            values{existing} = list{k+1};
        end
    end
end

actions = cell(1, 2 * nChannels);
actions(1:2:end) = channels(1:nChannels);
actions(2:2:end) = values(1:nChannels);
