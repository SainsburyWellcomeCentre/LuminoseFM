function generator = familyDefaults(generator, family, budget, duration)
% lum.pattern.familyDefaults sets a generator up for one family, at that family's defaults.
%
% Choosing a family in the stimulus designer or the setup dialog calls this, so that
% the patterns load ready to run: every family's defaults compile without a warning
% or an error, and give the design its rationale (docs/stimulus_family.md). Only the
% chosen family's own fields are reset, with Family and Continuous; the other
% families' fields and the shared ones (seed, offsets) are left as they are. The bin is
% kept too, unless the defaults cannot be drawn in it: given the window, a bin too coarse
% for them (a mixture in three 100 ms bins, five sequence slots in three bins) is made
% finer, 10 ms, then 5, 2 or 1 ms, until they generate. It is never made coarser.
%
% The defaults fit the global timers the machine leaves for light: the sequence family
% uses five slots where five flashes fit, and three where they do not (the emulated
% state machine has four timers for light, three with the light clock, D21), the mixture
% fewer cycles, and the motif family two-letter words where three letters do not fit,
% so that choosing a family never produces a set the machine refuses.
%
% Arguments:
%   generator  S.Stimulus.Generator (fields it lacks are filled in first)
%   family     A name from lum.pattern.families
%   budget     Global timers left for light (lum.timerBudget); default Inf
%   duration   Stimulus window, seconds; default 1. Only hand-drawn pulses, which are
%              typed in seconds, depend on it.
%
% Returns the generator with the family chosen and its defaults in place.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.families, lum.pattern.withGeneratorDefaults, lum.gui.StimulusDesigner

if nargin < 3 || isempty(budget)
    budget = Inf;
end
if nargin < 4 || isempty(duration) || ~(duration > 0)
    duration = 1;
end
if ~isstruct(generator) || ~isscalar(generator)
    generator = struct();
end
family = lower(char(family));
known = {lum.pattern.families().Name};
if ~ismember(family, known)
    error('lum:pattern:familyDefaults:badFamily', 'Unknown family ''%s''. Use one of: %s.', ...
          family, strjoin(known, ', '));
end

if nargin < 4
    % withGeneratorDefaults calls this for every family without a window; generating here
    % would call it back, so the bin is left alone.
    generator = setFamily(generator, family, budget, duration);
    return
end
current = 0.01;
if isfield(generator, 'BinDuration') && isscalar(generator.BinDuration) ...
        && isnumeric(generator.BinDuration) && generator.BinDuration > 0
    current = generator.BinDuration;
end
finer = [0.01 0.005 0.002 0.001];
fitted = [];
for bin = [current, finer(finer < current)]
    candidate = generator;
    candidate.BinDuration = bin;
    candidate = setFamily(candidate, family, budget, duration);
    if isempty(fitted)
        fitted = candidate;   % If nothing finer works either, keep the operator's bin
    end
    if generates(candidate, duration)
        fitted = candidate;
        break
    end
end
generator = fitted;


function generator = setFamily(generator, family, budget, duration)
% The family chosen, at its defaults for this bin, budget and window.
generator.Family = family;
generator.Continuous = false;
switch family
    case 'pure'
        % A against B, each lit for the whole window.
        generator.PureChannels = 'A and B';
        generator.PureFractions = 1;
    case 'mixture'
        % A's share of the light: 2:1 against 1:2, the sides changing at 1:1, at totals
        % that double. Every pair is at the same ratio, so every trial is as hard as every
        % other, and each amount but the lowest and highest pays left in one group and
        % right in another, so neither amount alone tells the side and the total tells
        % nothing. The difference rule's defaults do the same for A minus B = +-0.1 of the
        % window, at totals 0.2 apart; the controls' levels span the same amounts.
        % Roving totals mean most pairs light less than the window, so the amounts are
        % spread over it in cycles, both channels starting each cycle: the mixture is
        % present throughout the window and the dark is a short gap in every cycle, not a
        % tail after the light. Each cycle costs a timer per channel, so five cycles where
        % ten timers are left for light, fewer where not (the emulator: two), and no more
        % than the smallest amount (0.1 of the window) has bins for.
        generator.MixtureRule = 'share';
        generator.MixtureRatios = [2 1; 1 2];
        generator.MixtureShareBoundary = [1 1];
        generator.MixtureShareTotals = [0.3 0.6 1.2];
        generator.MixtureDifferences = [0.1 -0.1];
        generator.MixtureDifferenceBoundary = 0;
        generator.MixtureDifferenceTotals = [0.3 0.5 0.7 0.9];
        generator.MixtureLevels = [0.1 0.2 0.4 0.8];
        generator.MixtureLayout = 'spread';
        generator.MixtureCycles = mixtureCycles(generator, budget, duration, 0.1);
    case 'count'
        % Every split of the slots between A and B, from all A to all B: a psychometric
        % sweep of the count difference, with a fresh order of the flashes every trial.
        % Each flash costs a global timer.
        slots = 5;
        if budget < slots
            slots = max(1, 2 * floor((min(budget, slots) - 1) / 2) + 1);  % Odd: no ties
        end
        generator.CountSlots = slots;
        generator.CountPairs = [(slots:-1:0)', (0:slots)'];
        generator.CountFill = 0.5;
        generator.Continuous = true;
    case 'order'
        % One turn: the first channel alone, both together, the second alone.
        generator.OrderDesign = 'simple';
        generator.OrderCycles = 1;
        generator.OrderOverlap = 0.2;
        generator.OrderShortOverlap = 0.1;
        generator.OrderLongOverlap = 0.3;
    case 'motif'
        % All eight three-letter words of A and B, split so that the side depends on the
        % whole word: no letter position, no repeat or change between letters and no
        % majority tells it (each position, and the count of A, is right 3 times in 4).
        % Each letter is a flash and costs a global timer: where fewer than three are left
        % (the emulator with the hold clock and the light clock), the four two-letter
        % words, same letter twice against a change, which no letter position decides.
        generator.MotifLeftWords = 'AAA AAB ABB BAB';
        generator.MotifRightWords = 'ABA BAA BBA BBB';
        if budget < 3
            generator.MotifLeftWords = 'AA BB';
            generator.MotifRightWords = 'AB BA';
        end
        generator.MotifFill = 0.5;
    case 'arbitrary'
        % Two groups that can be told apart: A, then B, in the first half of the window.
        generator.nGroups = 2;
        generator.Pulses = [1 1 0 duration / 2; 2 2 0 duration / 2];
end


function tf = generates(generator, duration)
% True when the generator draws a set in this window without an error.
try
    lum.pattern.generate(generator, duration, 1);
    tf = true;
catch
    tf = false;
end


function cycles = mixtureCycles(generator, budget, duration, smallest)
% Cycles for the spread mixture: five at most, two timers each within the budget, and
% no more than the bins of the smallest amount, so each cycle holds some of it.
bin = 0.01;
if isfield(generator, 'BinDuration') && isscalar(generator.BinDuration) ...
        && isnumeric(generator.BinDuration) && generator.BinDuration > 0
    bin = generator.BinDuration;
end
nBins = max(1, round(duration / bin));
cycles = min([5, floor(budget / 2), round(smallest * nBins)]);
cycles = max(1, cycles);
