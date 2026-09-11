function generator = withGeneratorDefaults(generator)
% lum.pattern.withGeneratorDefaults fills in any generator field that is missing.
%
% The generator struct has a field for every family, most of which any one family
% ignores. Settings files written before a field existed, and the short structs
% tests and scripts write by hand, would otherwise fail on the first field they
% lack. Present fields always win, including empty ones where empty is meaningful.
%
% Fields and their defaults (lum.defaultSettings uses the same values):
%   Family              'pure'
%   nGroups             2       Groups balanced across the session
%   Continuous          false   A new pattern for every trial instead of groups
%   BinDuration         0.01    Seconds per bin
%   Seed                1       Stream seed; the session draws a fresh one unless
%   NewSeedEachSession  true    ... this is false
%   PureChannel         'A'     pure, one group: which channel
%   OnFraction          1       pure: lit fraction, one value or one per group
%   Motif               [1 2]   sequence: joint states of one cycle
%   DutyCycle           [1 1]   sequence: lit fraction of a slot, [A B]
%   SlotWeights         []      sequence: relative slot lengths; [] = equal
%   NumCycles           2       sequence: motif repeats in the window
%   BPhase              []      sequence, more than two groups: B phase per group (deg)
%   AOnFraction         0.5     occupancy: A lit fraction, overlap included
%   BOnFraction         0.5     occupancy: B lit fraction, overlap included
%   Overlap             0.2     occupancy: fraction with both channels on
%   Beta                NaN     occupancy: B share of non-overlap light; NaN = use
%                               AOnFraction and BOnFraction; one per group sweeps it
%   Layout              'blocks' occupancy: 'blocks' or 'shuffle'
%   BlockOrder          [1 3 2 0] occupancy: order of the blocks
%   CycleBins           10      overlap_order: bins per cycle
%   PureWidth           2       overlap_order: bins of each pure block
%   ShortGuard          1       overlap_order: bins of the short overlap guard
%   Phase               NaN     overlap_order: cycle phase in bins; NaN = random in
%                               continuous mode, 0 otherwise
%   Pulses              zeros(0, 4) arbitrary: rows of [group channel start end]
%   AOffset, BOffset    0       Latency of each channel (s), one or one per group
%   OffsetMode          'circular' 'circular' wraps round the window, 'linear' drops
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.generate, lum.defaultSettings

defaults = struct( ...
    'Family', 'pure', 'nGroups', 2, 'Continuous', false, 'BinDuration', 0.01, ...
    'Seed', 1, 'NewSeedEachSession', true, ...
    'PureChannel', 'A', 'OnFraction', 1, ...
    'Motif', [1 2], 'DutyCycle', [1 1], 'SlotWeights', [], 'NumCycles', 2, 'BPhase', [], ...
    'AOnFraction', 0.5, 'BOnFraction', 0.5, 'Overlap', 0.2, 'Beta', NaN, ...
    'Layout', 'blocks', 'BlockOrder', [1 3 2 0], ...
    'CycleBins', 10, 'PureWidth', 2, 'ShortGuard', 1, 'Phase', NaN, ...
    'Pulses', zeros(0, 4), 'AOffset', 0, 'BOffset', 0, 'OffsetMode', 'circular');

if ~isstruct(generator) || ~isscalar(generator)
    generator = struct();
end
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(generator, names{i})
        generator.(names{i}) = defaults.(names{i});
    end
end
