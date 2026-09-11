function G = generate(generator, duration, nTrials)
% lum.pattern.generate synthesises a session of two-channel light patterns.
%
% This is the stimulus generator of the generatePattern library, rebuilt for the
% protocol. Two optical channels, A and B, are each commanded on or off over the
% stimulus window, which is cut into equal bins. At any bin the pair is in one of
% four joint states:
%
%   0  dark      neither channel on
%   1  A only
%   2  B only
%   3  A and B   the two channels overlap
%
% A session is a set of *groups* (conditions) balanced across its trials, or, in
% continuous mode, a fresh pattern for every trial. The family decides what the
% patterns look like:
%
%   pure           One channel on for a fraction of the window. Two groups give A
%                  against B; more groups sweep the lit fraction.
%   sequence       A motif of joint states repeated a number of cycles, with a duty
%                  cycle per channel. Two groups give the motif and its A/B mirror;
%                  more groups sweep the phase of B against A.
%   occupancy      The window divided between the four joint states in given
%                  proportions, as contiguous blocks or shuffled. More groups sweep
%                  beta, the share of the non-overlapping light that B gets.
%   overlap_order  Two pure blocks separated by a short and a long overlap guard,
%                  so that the two groups differ only in which channel leads across
%                  the short guard: no dark time, identical light per channel.
%   tiled_order    A and B alternating bin by bin, B the exact complement of A. A
%                  control for decoders that can read one channel alone.
%   arbitrary      Pulses typed in by hand: [group, channel, start, end] rows.
%
% Every family also takes a latency offset for each channel, circular (wrapping
% round the window, so each channel keeps its light) or linear (light pushed off
% the end is lost).
%
% Randomness comes only from a private stream seeded with generator.Seed, so a
% session's patterns and trial order are fixed by its settings: the setup dialog's
% preview is exactly what the session runs, and the global rng is left alone.
%
% Arguments:
%   generator  S.Stimulus.Generator; lum.defaultSettings documents every field
%   duration   Stimulus window in seconds, S.Stimulus.Duration
%   nTrials    Trials to produce an order for, S.Session.MaxTrials
%
% Returns a struct:
%   .Family        Family name, as above
%   .Duration      Stimulus window, seconds
%   .BinDuration   Bin width, seconds
%   .nBins         Bins per window
%   .nTrials       Trials in the order
%   .Continuous    True when every trial has a pattern of its own
%   .nGroups       Groups; in continuous mode the two categories A-led and B-led
%   .Seed          The seed the stream was built from
%   .States        nBins x nPatterns uint8 joint states. One pattern per group, or
%                  one per trial in continuous mode.
%   .PatternGroup  1 x nPatterns. The group of each pattern, or in continuous mode
%                  its category: 1 A-led, 2 B-led, 0 neither.
%   .TrialPattern  1 x nTrials. Which pattern each trial delivers, in session order.
%   .GroupLabels   1 x nGroups cell of short labels
%   .SweepName     What varies across groups, with units; '' when nothing does
%   .SweepValues   1 x nGroups; the group index when nothing is swept
%   .Descriptors   Struct of 1 x nPatterns rows: AOn, BOn, Overlap, Dark (seconds of
%                  each) and BShare, the fraction of all light that is B
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.stimulusSet, lum.pattern.fromStates, lum.pattern.families,
%           lum.gui.StimulusDesigner

g = lum.pattern.withGeneratorDefaults(generator);

family = lower(char(g.Family));
familyList = lum.pattern.families();
knownFamilies = {familyList.Name};
if ~ismember(family, knownFamilies)
    error('lum:pattern:generate:badFamily', 'Unknown family ''%s''. Use one of: %s.', ...
          family, strjoin(knownFamilies, ', '));
end
if ~(isscalar(duration) && isnumeric(duration) && isfinite(duration) && duration > 0)
    error('lum:pattern:generate:badDuration', ...
          'The stimulus window must be a positive number of seconds.');
end
if ~(isscalar(nTrials) && nTrials >= 1 && mod(nTrials, 1) == 0)
    error('lum:pattern:generate:badTrialCount', 'The trial count must be a positive integer.');
end

bin = g.BinDuration;
if ~(isscalar(bin) && isnumeric(bin) && isfinite(bin) && bin > 0 && bin <= duration)
    error('lum:pattern:generate:badBin', ...
          'The bin must be a positive number of seconds no longer than the %g s window.', ...
          duration);
end
ratio = duration / bin;
nBins = round(ratio);
if abs(ratio - nBins) > 1e-9 * max(1, ratio)
    error('lum:pattern:generate:binMismatch', ...
          ['A %g s bin does not divide the %g s window into whole bins. Choose a bin '...
           'that does, e.g. %g s.'], bin, duration, duration / max(1, floor(ratio)));
end

continuous = logical(g.Continuous);
nGroups = g.nGroups;
if ~continuous && ~(isscalar(nGroups) && nGroups >= 1 && mod(nGroups, 1) == 0)
    error('lum:pattern:generate:badGroupCount', 'The number of groups must be a positive integer.');
end
seed = g.Seed;
if ~(isscalar(seed) && isnumeric(seed) && isfinite(seed) && seed >= 0 && seed < 2^32 ...
        && mod(seed, 1) == 0)
    error('lum:pattern:generate:badSeed', ...
          'The seed must be an integer in [0, 2^32). Draw one with lum.pattern.newSeed.');
end
stream = RandStream('mt19937ar', 'Seed', seed);

if continuous
    nPatterns = nTrials;
else
    nPatterns = nGroups;
end

category = NaN(1, nPatterns);
sweepName = '';
sweepValues = [];
switch family
    case 'pure'
        [states, category, labels, sweepName, sweepValues] = ...
            pureFamily(g, nBins, nPatterns, continuous, stream);
    case 'sequence'
        [states, category, labels, sweepName, sweepValues] = ...
            sequenceFamily(g, nBins, nPatterns, continuous, stream);
    case 'occupancy'
        [states, category, labels, sweepName, sweepValues] = ...
            occupancyFamily(g, nBins, nPatterns, continuous, stream);
    case 'overlap_order'
        [states, category, labels, sweepName, sweepValues] = ...
            overlapOrderFamily(g, nBins, nPatterns, continuous, stream);
    case 'tiled_order'
        [states, category, labels] = tiledOrderFamily(nBins, nPatterns, continuous);
    case 'arbitrary'
        [states, labels] = arbitraryFamily(g, nBins, bin, duration, nPatterns, continuous);
end

states = applyOffsets(states, g, bin, nPatterns, continuous);

%% Descriptors: how much of each joint state every pattern contains
lightA = bitand(states, uint8(1)) ~= 0;
lightB = bitand(states, uint8(2)) ~= 0;
descriptors = struct();
descriptors.AOn = sum(lightA, 1) * bin;
descriptors.BOn = sum(lightB, 1) * bin;
descriptors.Overlap = sum(lightA & lightB, 1) * bin;
descriptors.Dark = sum(~lightA & ~lightB, 1) * bin;
totalLight = descriptors.AOn + descriptors.BOn;
descriptors.BShare = 0.5 * ones(1, nPatterns);
lit = totalLight > 0;
descriptors.BShare(lit) = descriptors.BOn(lit) ./ totalLight(lit);

%% Groups and trial order
if continuous
    % Each trial is its own pattern, so the groups the contingency needs are
    % categories: the family's own where it has one, otherwise whichever channel
    % carries more of the light.
    patternGroup = category;
    undecided = isnan(patternGroup);
    patternGroup(undecided & descriptors.BShare < 0.5) = 1;
    patternGroup(undecided & descriptors.BShare > 0.5) = 2;
    patternGroup(isnan(patternGroup)) = 0;
    nGroups = 2;
    labels = {'A-led', 'B-led'};
    trialPattern = 1:nTrials;
else
    patternGroup = 1:nGroups;
    trialPattern = balancedAssignments(nTrials, nGroups, stream);
end
if isempty(sweepValues)
    sweepValues = 1:nGroups;
end

G = struct('Family', family, 'Duration', duration, 'BinDuration', bin, 'nBins', nBins, ...
           'nTrials', nTrials, 'Continuous', continuous, 'nGroups', nGroups, 'Seed', seed, ...
           'States', states, 'PatternGroup', patternGroup, 'TrialPattern', trialPattern, ...
           'GroupLabels', {labels}, 'SweepName', sweepName, 'SweepValues', sweepValues, ...
           'Descriptors', descriptors);


%% Families -------------------------------------------------------------------

function [states, category, labels, sweepName, sweepValues] = ...
    pureFamily(g, nBins, nPatterns, continuous, stream)
% One channel lit from the start of the window for a fraction of it.
fractions = g.OnFraction(:)';
if isempty(fractions) || any(~isfinite(fractions)) || any(fractions <= 0 | fractions > 1)
    error('lum:pattern:generate:badOnFraction', 'Lit fractions must lie in (0, 1].');
end
states = zeros(nBins, nPatterns, 'uint8');
sweepName = '';
sweepValues = [];

if continuous
    category = balancedAssignments(nPatterns, 2, stream);
    onBins = binsFor(fractions(1), nBins);
    states(1:onBins, :) = repmat(uint8(category), onBins, 1);
    labels = {};
    return
end

switch nPatterns
    case 1
        channel = 1 + strcmpi(g.PureChannel, 'B');
        states(1:binsFor(fractions(1), nBins), 1) = channel;
        category = channel;
        labels = {sprintf('%s only', channelName(channel))};
    case 2
        onBins = binsFor(fractions(1), nBins);
        states(1:onBins, 1) = 1;
        states(1:onBins, 2) = 2;
        category = [1 2];
        labels = {'A only', 'B only'};
    otherwise
        if numel(fractions) ~= nPatterns
            fractions = linspace(0.2, 1, nPatterns);
        end
        category = 1 + mod(0:nPatterns-1, 2);
        labels = cell(1, nPatterns);
        for k = 1:nPatterns
            states(1:binsFor(fractions(k), nBins), k) = category(k);
            labels{k} = sprintf('%s %.0f%%', channelName(category(k)), 100 * fractions(k));
        end
        sweepName = 'Lit fraction';
        sweepValues = fractions;
end


function [states, category, labels, sweepName, sweepValues] = ...
    sequenceFamily(g, nBins, nPatterns, continuous, stream)
% A motif of joint states, repeated whole across the window.
motif = g.Motif(:)';
if isempty(motif) || any(mod(motif, 1) ~= 0) || any(motif < 0 | motif > 3) ...
        || ~any(motif == 1) || ~any(motif == 2)
    error('lum:pattern:generate:badMotif', ...
          ['The motif must be joint states 0-3 and contain both 1 (A only) and 2 (B only), '...
           'e.g. 1 2 or 1 3 2 0.']);
end
motif = uint8(motif);
nSlots = numel(motif);

duty = g.DutyCycle(:)';
if isscalar(duty)
    duty = [duty duty];
end
if numel(duty) ~= 2 || any(~isfinite(duty)) || any(duty <= 0 | duty > 1)
    error('lum:pattern:generate:badDutyCycle', ...
          'The duty cycle must be one value, or one per channel [A B], each in (0, 1].');
end

nCycles = g.NumCycles;
if ~(isscalar(nCycles) && nCycles >= 1 && mod(nCycles, 1) == 0) || mod(nBins, nCycles) ~= 0
    error('lum:pattern:generate:badCycleCount', ...
          ['%s cycles do not divide the window''s %d bins exactly. Choose a cycle count '...
           'that does, or change the bin.'], num2str(nCycles), nBins);
end
cycleBins = nBins / nCycles;
if cycleBins < nSlots
    error('lum:pattern:generate:cycleTooShort', ...
          'Each cycle has %d bins, too few for a motif of %d slots.', cycleBins, nSlots);
end

weights = g.SlotWeights(:)';
if isempty(weights)
    weights = ones(1, nSlots);
end
if numel(weights) ~= nSlots || any(weights <= 0)
    error('lum:pattern:generate:badSlotWeights', ...
          'Slot weights need one positive value per motif slot (%d).', nSlots);
end
slotBins = allocateBins(weights, cycleBins);

states = zeros(nBins, nPatterns, 'uint8');
category = NaN(1, nPatterns);
labels = {};
sweepName = '';
sweepValues = [];
motifText = strjoin(compose('%d', motif), ' ');

if continuous
    for k = 1:nPatterns
        column = zeros(nBins, 1, 'uint8');
        for cycle = 1:nCycles
            order = randperm(stream, nSlots);
            column((cycle - 1) * cycleBins + (1:cycleBins)) = ...
                cycleStates(motif(order), slotBins(order), duty);
        end
        states(:, k) = column;
    end
    return
end

forward = repmat(cycleStates(motif, slotBins, duty), nCycles, 1);
switch nPatterns
    case 1
        states(:, 1) = forward;
        labels = {sprintf('Motif %s', motifText)};
    case 2
        states(:, 1) = forward;
        states(:, 2) = repmat(cycleStates(swapChannels(motif), slotBins, duty), nCycles, 1);
        category = [1 2];
        labels = {sprintf('Motif %s', motifText), 'Mirror (A<->B)'};
    otherwise
        phases = g.BPhase(:)';
        if numel(phases) ~= nPatterns
            phases = (0:nPatterns-1) * 360 / nPatterns;
        end
        lightA = bitand(forward, uint8(1)) ~= 0;
        lightB = bitand(forward, uint8(2)) ~= 0;
        labels = cell(1, nPatterns);
        for k = 1:nPatterns
            shift = round(phases(k) / 360 * cycleBins);
            states(:, k) = uint8(lightA) + 2 * uint8(circshift(lightB, shift));
            labels{k} = sprintf('B phase %g deg', phases(k));
        end
        sweepName = 'B phase (deg)';
        sweepValues = phases;
end


function [states, category, labels, sweepName, sweepValues] = ...
    occupancyFamily(g, nBins, nPatterns, continuous, stream)
% The window shared between the four joint states in given proportions.
overlap = g.Overlap;
beta = g.Beta;
useBeta = ~isempty(beta) && all(isfinite(beta));
if useBeta && isscalar(beta)
    fractionA = (1 - overlap) * (1 - beta) + overlap;
    fractionB = (1 - overlap) * beta + overlap;
else
    fractionA = g.AOnFraction;
    fractionB = g.BOnFraction;
end
fractions = occupancyFractions(fractionA, fractionB, overlap);

layout = lower(char(g.Layout));
if ~ismember(layout, {'blocks', 'shuffle'})
    error('lum:pattern:generate:badLayout', 'The layout must be ''blocks'' or ''shuffle''.');
end
blockOrder = g.BlockOrder(:)';
if ~isequal(sort(blockOrder), 0:3)
    error('lum:pattern:generate:badBlockOrder', ...
          'The block order must list the joint states 0 to 3 once each, e.g. 1 3 2 0.');
end

states = zeros(nBins, nPatterns, 'uint8');
category = NaN(1, nPatterns);
labels = {};
sweepName = '';
sweepValues = [];

if continuous
    counts = allocateBins(fractions, nBins);
    for k = 1:nPatterns
        if strcmp(layout, 'shuffle')
            column = repelem(uint8(0:3), counts);
            states(:, k) = column(randperm(stream, nBins));
        else
            order = randperm(stream, 4) - 1;
            states(:, k) = repelem(uint8(order), counts(order + 1));
        end
    end
    return
end

switch nPatterns
    case 1
        states(:, 1) = layOut(blockOrder, allocateBins(fractions, nBins), layout, stream);
        labels = {'Occupancy'};
    case 2
        counts = allocateBins(fractions, nBins);
        states(:, 1) = layOut(blockOrder, counts, layout, stream);
        states(:, 2) = layOut(double(swapChannels(uint8(blockOrder))), counts, layout, stream);
        category = [1 2];
        labels = {'A block first', 'B block first'};
    otherwise
        if useBeta && numel(beta) == nPatterns
            betas = beta(:)';
        else
            betas = linspace(0.1, 0.9, nPatterns);
        end
        labels = cell(1, nPatterns);
        for k = 1:nPatterns
            groupFractions = [0, (1 - overlap) * (1 - betas(k)), (1 - overlap) * betas(k), overlap];
            states(:, k) = layOut(blockOrder, allocateBins(groupFractions, nBins), layout, stream);
            labels{k} = sprintf('beta %.2f', betas(k));
        end
        sweepName = 'B share, beta';
        sweepValues = betas;
end


function [states, category, labels, sweepName, sweepValues] = ...
    overlapOrderFamily(g, nBins, nPatterns, continuous, stream)
% Pure blocks separated by asymmetric overlap guards; the category is the order.
cycleBins = g.CycleBins;
pureWidth = g.PureWidth;
shortGuard = g.ShortGuard;
longGuard = cycleBins - 2 * pureWidth - shortGuard;
if ~(shortGuard > 0 && longGuard > shortGuard)
    error('lum:pattern:generate:badGuards', ...
          ['A cycle of %d bins with pure blocks of %d leaves a long guard of %d, which must '...
           'be longer than the short guard of %d.'], cycleBins, pureWidth, longGuard, shortGuard);
end
if mod(nBins, cycleBins) ~= 0
    error('lum:pattern:generate:badCycleBins', ...
          'A cycle of %d bins does not divide the window''s %d bins exactly.', cycleBins, nBins);
end
nCycles = nBins / cycleBins;

aLeads = repmat(uint8(3), cycleBins, 1);
aLeads(1:pureWidth) = 1;
aLeads(pureWidth + shortGuard + 1:2 * pureWidth + shortGuard) = 2;
bLeads = swapChannels(aLeads);
cycles = {aLeads, bLeads};

phase = g.Phase;
states = zeros(nBins, nPatterns, 'uint8');
sweepName = '';
sweepValues = [];

if continuous
    category = balancedAssignments(nPatterns, 2, stream);
    for k = 1:nPatterns
        if isempty(phase) || isnan(phase)
            shift = randi(stream, cycleBins) - 1;
        else
            shift = phase;
        end
        states(:, k) = repmat(circshift(cycles{category(k)}, shift), nCycles, 1);
    end
    labels = {};
    return
end

fixedPhase = 0;
if ~isempty(phase) && ~isnan(phase)
    fixedPhase = phase;
end
switch nPatterns
    case 1
        states(:, 1) = repmat(circshift(aLeads, fixedPhase), nCycles, 1);
        category = 1;
        labels = {'A leads'};
    case 2
        states(:, 1) = repmat(circshift(aLeads, fixedPhase), nCycles, 1);
        states(:, 2) = repmat(circshift(bLeads, fixedPhase), nCycles, 1);
        category = [1 2];
        labels = {'A leads', 'B leads'};
    otherwise
        category = 1 + mod(0:nPatterns-1, 2);
        shifts = round(floor((0:nPatterns-1) / 2) * cycleBins / ceil(nPatterns / 2));
        labels = cell(1, nPatterns);
        for k = 1:nPatterns
            states(:, k) = repmat(circshift(cycles{category(k)}, shifts(k)), nCycles, 1);
            labels{k} = sprintf('%s leads, phase %d', channelName(category(k)), shifts(k));
        end
        sweepName = 'Phase (bins)';
        sweepValues = shifts;
end


function [states, category, labels] = tiledOrderFamily(nBins, nPatterns, continuous)
% A and B alternating bin by bin: B is always the complement of A.
if continuous || nPatterns > 2
    error('lum:pattern:generate:tiledGroups', ...
          'The tiled order has only two forms; use one or two groups, not continuous mode.');
end
aFirst = repmat(uint8([1; 2]), ceil(nBins / 2), 1);
aFirst = aFirst(1:nBins);
states = aFirst;
category = 1;
labels = {'A first'};
if nPatterns == 2
    states = [aFirst, swapChannels(aFirst)];
    category = [1 2];
    labels = {'A first', 'B first'};
end


function [states, labels] = arbitraryFamily(g, nBins, bin, duration, nPatterns, continuous)
% Pulses typed in by hand, one row per pulse: [group, channel, start, end].
if continuous
    error('lum:pattern:generate:arbitraryContinuous', ...
          'Hand-typed pulses describe groups, not individual trials; turn continuous mode off.');
end
pulses = g.Pulses;
if isempty(pulses)
    pulses = zeros(0, 4);
end
if size(pulses, 2) ~= 4 || any(~isfinite(pulses(:)))
    error('lum:pattern:generate:badPulses', ...
          'Pulses must be rows of [group, channel, start (s), end (s)].');
end
states = zeros(nBins, nPatterns, 'uint8');
edges = (0:nBins)' * bin;
binStart = edges(1:end-1);
binEnd = edges(2:end);
tolerance = bin * 1e-6;
for row = 1:size(pulses, 1)
    group = pulses(row, 1);
    channel = pulses(row, 2);
    pulseStart = pulses(row, 3);
    pulseEnd = pulses(row, 4);
    if group < 1 || group > nPatterns || mod(group, 1) ~= 0
        error('lum:pattern:generate:badPulses', ...
              'Pulse %d is for group %g, but there are %d groups.', row, group, nPatterns);
    end
    if ~ismember(channel, [1 2])
        error('lum:pattern:generate:badPulses', ...
              'Pulse %d names channel %g; channels are 1 (A) and 2 (B).', row, channel);
    end
    if pulseStart < -tolerance || pulseEnd > duration + tolerance || pulseEnd <= pulseStart
        error('lum:pattern:generate:badPulses', ...
              'Pulse %d must start before it ends and lie within the %g s window.', row, duration);
    end
    lit = binStart < pulseEnd - tolerance & binEnd > pulseStart + tolerance;
    states(lit, group) = bitor(states(lit, group), uint8(channel));
end
labels = compose('Custom %d', 1:nPatterns);


%% Offsets --------------------------------------------------------------------

function states = applyOffsets(states, g, bin, nPatterns, continuous)
% Shift each channel's light in time, per group or for every trial.
shiftA = offsetBins(g.AOffset, bin, nPatterns, continuous, 'A');
shiftB = offsetBins(g.BOffset, bin, nPatterns, continuous, 'B');
if ~any(shiftA) && ~any(shiftB)
    return
end
mode = lower(char(g.OffsetMode));
if ~ismember(mode, {'circular', 'linear'})
    error('lum:pattern:generate:badOffsetMode', 'The offset mode must be ''circular'' or ''linear''.');
end
lightA = shiftColumns(bitand(states, uint8(1)) ~= 0, shiftA, mode);
lightB = shiftColumns(bitand(states, uint8(2)) ~= 0, shiftB, mode);
states = uint8(lightA) + 2 * uint8(lightB);


function shifts = offsetBins(offset, bin, nPatterns, continuous, channel)
% An offset in seconds as whole bins, one per pattern.
offset = offset(:)';
if isempty(offset)
    offset = 0;
end
if any(~isfinite(offset))
    error('lum:pattern:generate:badOffset', 'Channel %s offsets must be finite.', channel);
end
if isscalar(offset)
    offset = repmat(offset, 1, nPatterns);
elseif continuous || numel(offset) ~= nPatterns
    error('lum:pattern:generate:badOffset', ...
          'Channel %s needs one offset, or one per group (%d).', channel, nPatterns);
end
shifts = round(offset / bin);


function shifted = shiftColumns(light, shifts, mode)
% Shift each column of a logical matrix by its own number of bins.
[nBins, nColumns] = size(light);
shifted = false(nBins, nColumns);
for column = 1:nColumns
    s = shifts(column);
    if s == 0
        shifted(:, column) = light(:, column);
    elseif strcmp(mode, 'circular')
        shifted(:, column) = circshift(light(:, column), s);
    elseif abs(s) < nBins
        if s > 0
            shifted(s + 1:nBins, column) = light(1:nBins - s, column);
        else
            shifted(1:nBins + s, column) = light(1 - s:nBins, column);
        end
    end
end


%% Small pieces ---------------------------------------------------------------

function assignments = balancedAssignments(nTrials, nGroups, stream)
% Every group equally often, the remainder spread over random groups, shuffled.
if nGroups <= 1
    assignments = ones(1, nTrials);
    return
end
assignments = repmat(1:nGroups, 1, floor(nTrials / nGroups));
remainder = mod(nTrials, nGroups);
if remainder > 0
    assignments = [assignments, randperm(stream, nGroups, remainder)];
end
assignments = assignments(randperm(stream, nTrials));


function counts = allocateBins(weights, nBins)
% Share nBins out in proportion to weights, largest remainders first.
weights = max(weights(:)', 0);
if sum(weights) <= 0
    error('lum:pattern:generate:noWeight', 'At least one share must be positive.');
end
exact = nBins * weights / sum(weights);
counts = floor(exact);
[~, order] = sort(exact - counts, 'descend');
missing = nBins - sum(counts);
counts(order(1:missing)) = counts(order(1:missing)) + 1;


function column = cycleStates(motif, slotBins, duty)
% One cycle of a motif as joint states, each channel lit for its duty cycle of a slot.
column = zeros(sum(slotBins), 1, 'uint8');
cursor = 0;
for slot = 1:numel(motif)
    width = slotBins(slot);
    if bitand(motif(slot), uint8(1))
        column(cursor + (1:max(1, round(width * duty(1))))) = 1;
    end
    if bitand(motif(slot), uint8(2))
        lit = cursor + (1:max(1, round(width * duty(2))));
        column(lit) = column(lit) + 2;
    end
    cursor = cursor + width;
end


function column = layOut(order, counts, layout, stream)
% Joint states as contiguous blocks in the given order, or shuffled.
column = repelem(uint8(order), counts(order + 1));
column = column(:);
if strcmp(layout, 'shuffle')
    column = column(randperm(stream, numel(column)));
end


function fractions = occupancyFractions(fractionA, fractionB, overlap)
% [dark, A only, B only, both] from each channel's lit fraction and their overlap.
values = [fractionA, fractionB, overlap];
if numel(values) ~= 3 || any(~isfinite(values)) || any(values < 0 | values > 1)
    error('lum:pattern:generate:badOccupancy', ...
          'Lit fractions and the overlap must each be one value in [0, 1].');
end
fractions = [1 - fractionA - fractionB + overlap, fractionA - overlap, ...
             fractionB - overlap, overlap];
if any(fractions < -1e-12)
    error('lum:pattern:generate:badOccupancy', ...
          ['The overlap (%g) must be at least A + B - 1 (%g) and at most the smaller lit '...
           'fraction (%g).'], overlap, max(0, fractionA + fractionB - 1), min(fractionA, fractionB));
end
fractions = max(fractions, 0);


function states = swapChannels(states)
% The same joint states with A and B exchanged.
swapped = states;
swapped(states == 1) = 2;
swapped(states == 2) = 1;
states = swapped;


function n = binsFor(fraction, nBins)
% Bins lit by a fraction of the window: at least one, at most all.
n = min(nBins, max(1, round(fraction * nBins)));


function name = channelName(channel)
% 1 -> 'A', 2 -> 'B'.
names = 'AB';
name = names(channel);
