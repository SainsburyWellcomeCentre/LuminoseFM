function G = generate(generator, duration, nTrials)
% lum.pattern.generate synthesises a session of two-channel light patterns.
%
% Two optical channels, A and B, are each commanded on or off over the stimulus
% window, which is cut into equal bins. At any bin the pair is in one of four joint
% states:
%
%   0  dark      neither channel on
%   1  A only
%   2  B only
%   3  A and B   the two channels overlap
%
% A session is a set of groups (conditions) balanced across its trials. The family
% decides what the patterns look like, and so what the animal has to tell apart
% (lum.pattern.families; docs/stimulus_family.md has the full definitions):
%
%   pure       Which channel is lit? One channel from onset, for one or more lit
%              fractions: A pays left, B right.
%   mixture    How much of the mixture is A? Both channels, each lit for an amount. The
%              relative rules pay by A's share of the light, u_A / (u_A + u_B) (rule
%              'share', its groups mixture ratios), or by A minus B ('difference'),
%              against a boundary that can move; each is given at several totals of
%              light, so neither amount alone tells the side. The controls 'A alone' and
%              'B alone' cross every level with every level, one channel deciding (a
%              vertical or horizontal boundary). By default each amount is spread over
%              the window in cycles, both channels starting every cycle, so the mixture
%              is present throughout the window ('spread'); 'onset' and 'centred' light
%              each amount in one stretch. Per trial: amounts drawn anew.
%   count      Which channel flashes more often? Slots holding one flash of A, one of
%              B, or nothing; a group is a pair of counts. Per trial: a new order of
%              the flashes (the default).
%   order      Which channel comes first? A and B take turns, meeting in an overlap. The
%              guarded cycle adds a long overlap, and per trial a random phase.
%   motif      Which word is it? Words of letters A, B, X (both) and - (dark), one
%              flash per letter, listed for each side.
%   arbitrary  Pulses typed in by hand: [group, channel, start, end] rows.
%
% Every family also takes a latency offset for each channel, one value or one per
% group, circular (wrapping round the window, so each channel keeps its light) or
% linear (light pushed off the end is lost).
%
% Families that offer it (lum.pattern.families, PerTrial) give every trial a pattern
% of its own when generator.Continuous is true; each pattern still belongs to a group,
% and the groups are balanced over the session as always.
%
% Randomness comes only from a private stream seeded with generator.Seed, so a
% session's patterns and trial order are fixed by its settings: the setup dialog's
% preview is exactly what the session runs, and the global rng is left alone.
%
% The bin is adjusted, if need be, to divide the window into whole bins (a 10 ms bin
% in a 0.333 s window becomes 33 bins of 10.09 ms); fractions of the window (levels,
% slots, overlaps) are shared out over whole bins, the remainder spread one bin at a
% time, so no parameter has to divide anything exactly.
%
% Arguments:
%   generator  S.Stimulus.Generator; lum.pattern.withGeneratorDefaults documents every
%              field
%   duration   Stimulus window in seconds, S.Stimulus.Duration
%   nTrials    Trials to produce an order for, S.Session.MaxTrials
%
% Returns a struct:
%   .Family        Family name, as above
%   .Duration      Stimulus window, seconds
%   .BinDuration   Bin width, seconds, as used (see above)
%   .nBins         Bins per window
%   .nTrials       Trials in the order
%   .Continuous    True when every trial has a pattern of its own
%   .nGroups       Groups
%   .Seed          The seed the stream was built from
%   .States        nBins x nPatterns uint8 joint states: one pattern per group, or one
%                  per trial when Continuous
%   .PatternGroup  1 x nPatterns group of each pattern
%   .TrialPattern  1 x nTrials pattern each trial delivers, in session order
%   .GroupLabels   1 x nGroups cell of short labels
%   .FamilyPLeft   1 x nGroups chance the left port pays, as the family intends it; the
%                  session uses it unless S.Task.GroupPLeft gives values of its own
%   .EvidenceName  What the family's decision variable is, for the psychometric axis;
%                  '' when the groups are categories with nothing in between
%   .Evidence      1 x nPatterns value of the decision variable (NaN when unnamed)
%   .Boundary      Where the contingency divides the plane of u_A and u_B (the
%                  fractions of the window A and B are lit): .Kind 'diagonal',
%                  'vertical', 'horizontal', 'line' or 'none'; .Value, the amount a
%                  vertical or horizontal boundary sits at; .Slope and .Intercept of a
%                  line u_B = Slope * u_A + Intercept (the diagonal's are 1 and 0); NaN
%                  where they do not apply
%   .Descriptors   Struct of 1 x nPatterns rows: AOn, BOn, Overlap, Dark (seconds of
%                  each), BShare (the fraction of all light that is B), and ASegments,
%                  BSegments (separate stretches of light on each channel)
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.stimulusSet, lum.pattern.fromStates, lum.pattern.families,
%           lum.pattern.familyDefaults, lum.gui.StimulusDesigner

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
if ~(isscalar(bin) && isnumeric(bin) && isfinite(bin) && bin > 0)
    error('lum:pattern:generate:badBin', 'The bin must be a positive number of seconds.');
end
nBins = max(1, round(duration / bin));
bin = duration / nBins;  % Whole bins in the window

seed = g.Seed;
if ~(isscalar(seed) && isnumeric(seed) && isfinite(seed) && seed >= 0 && seed < 2^32 ...
        && mod(seed, 1) == 0)
    error('lum:pattern:generate:badSeed', ...
          'The seed must be an integer in [0, 2^32). Draw one with lum.pattern.newSeed.');
end
stream = RandStream('mt19937ar', 'Seed', seed);
perTrial = ~isempty(familyList(strcmp(knownFamilies, family)).PerTrial) ...
           && isequal(logical(g.Continuous), true);

switch family
    case 'pure'
        d = pureDesign(g, nBins);
    case 'mixture'
        if perTrial
            d = mixturePerTrial(g, nBins, nTrials, bin, stream);
        else
            d = mixtureGroups(g, nBins, bin);
        end
    case 'count'
        d = countDesign(g, nBins, nTrials, perTrial, stream);
    case 'order'
        d = orderDesign(g, nBins, nTrials, perTrial, stream);
    case 'motif'
        d = motifDesign(g, nBins);
    case 'arbitrary'
        d = arbitraryDesign(g, nBins, bin, duration);
end

nGroups = numel(d.GroupLabels);
if d.Continuous
    trialPattern = 1:nTrials;
else
    trialPattern = balancedAssignments(nTrials, nGroups, stream);
end

states = applyOffsets(d.States, g, bin, d.PatternGroup, nGroups);

%% Descriptors: how much of each joint state every pattern contains
lightA = bitand(states, uint8(1)) ~= 0;
lightB = bitand(states, uint8(2)) ~= 0;
descriptors = struct();
descriptors.AOn = sum(lightA, 1) * bin;
descriptors.BOn = sum(lightB, 1) * bin;
descriptors.Overlap = sum(lightA & lightB, 1) * bin;
descriptors.Dark = sum(~lightA & ~lightB, 1) * bin;
totalLight = descriptors.AOn + descriptors.BOn;
descriptors.BShare = 0.5 * ones(1, size(states, 2));
lit = totalLight > 0;
descriptors.BShare(lit) = descriptors.BOn(lit) ./ totalLight(lit);
descriptors.ASegments = sum(diff([false(1, size(states, 2)); lightA], 1, 1) == 1, 1);
descriptors.BSegments = sum(diff([false(1, size(states, 2)); lightB], 1, 1) == 1, 1);

G = struct('Family', family, 'Duration', duration, 'BinDuration', bin, 'nBins', nBins, ...
           'nTrials', nTrials, 'Continuous', d.Continuous, 'nGroups', nGroups, 'Seed', seed, ...
           'States', states, 'PatternGroup', d.PatternGroup, 'TrialPattern', trialPattern, ...
           'GroupLabels', {d.GroupLabels}, 'FamilyPLeft', d.FamilyPLeft, ...
           'EvidenceName', d.EvidenceName, 'Evidence', d.Evidence, 'Boundary', d.Boundary, ...
           'Descriptors', descriptors);


%% Families -------------------------------------------------------------------
% Each returns a design: States (nBins x nPatterns), PatternGroup, GroupLabels,
% FamilyPLeft (one per group), EvidenceName, Evidence (one per pattern), Boundary and
% Continuous (true when the patterns are one per trial, already in session order).

function d = pureDesign(g, nBins)
% One channel lit from the start of the window, for each lit fraction.
switch lower(strtrim(char(g.PureChannels)))
    case {'a and b', 'ab', 'both', 'balanced'}
        channels = [1 2];
    case 'a'
        channels = 1;
    case 'b'
        channels = 2;
    otherwise
        error('lum:pattern:generate:badPureChannels', ...
              'The pure channels must be ''A and B'', ''A'' or ''B''.');
end
fractions = g.PureFractions(:)';
if isempty(fractions) || ~isnumeric(fractions) || any(~isfinite(fractions)) ...
        || any(fractions <= 0 | fractions > 1)
    error('lum:pattern:generate:badPureFractions', ...
          'Lit fractions must be one or more numbers in (0, 1], e.g. 1 or 0.25 0.5 1.');
end
fractions = unique(fractions, 'stable');

nGroups = numel(fractions) * numel(channels);
states = zeros(nBins, nGroups, 'uint8');
labels = cell(1, nGroups);
pLeft = 0.5 * ones(1, nGroups);  % One channel only: nothing to tell apart
k = 0;
for fraction = fractions
    for channel = channels
        k = k + 1;
        states(1:binsFor(fraction, nBins), k) = channel;
        if isscalar(fractions) && fraction == 1
            labels{k} = sprintf('%s only', channelName(channel));
        else
            labels{k} = sprintf('%s %g%%', channelName(channel), round(100 * fraction, 1));
        end
        if numel(channels) == 2
            pLeft(k) = double(channel == 1);
        end
    end
end
d = design(states, 1:nGroups, labels, pLeft, '', NaN(1, nGroups), boundary('diagonal'), false);


function d = mixtureGroups(g, nBins, bin)
% Pairs of amounts, one group per pair. Relative rules: each mixture ratio (A share) or
% each difference (A minus B) at each total of light. Alone rules: every level of A with
% every level of B.
m = mixtureParameters(g, nBins);
switch m.rule
    case 'share'
        amounts = zeros(0, 2);   % [A B], fractions of the window
        for total = m.totals
            for r = 1:size(m.ratios, 1)
                share = m.ratios(r, 1) / sum(m.ratios(r, :));
                amounts(end+1, :) = [share, 1 - share] * total; %#ok<AGROW>
                if any(amounts(end, :) > 1 + 1e-9)
                    error('lum:pattern:generate:badMixtureAmounts', ...
                          ['The ratio %g:%g at a total light of %g would light a channel for %.3g '...
                           'of the window; a channel is lit for at most the whole window. Use '...
                           'lower totals.'], m.ratios(r, 1), m.ratios(r, 2), total, max(amounts(end, :)));
                end
            end
        end
    case 'difference'
        amounts = zeros(0, 2);
        for total = m.totals
            for delta = m.differences
                amounts(end+1, :) = [total + delta, total - delta] / 2; %#ok<AGROW>
                if any(amounts(end, :) < -1e-9) || any(amounts(end, :) > 1 + 1e-9)
                    error('lum:pattern:generate:badMixtureAmounts', ...
                          ['A minus B of %g at a total light of %g would need an amount below 0 '...
                           'or above the whole window. Use totals of at least |A minus B| and at '...
                           'most 2 - |A minus B|.'], delta, total);
                end
            end
        end
    otherwise
        n = numel(m.levels);
        [deciding, other] = ndgrid(1:n, 1:n);
        deciding = deciding';
        other = other';
        pairs = [deciding(:), other(:)];   % Level indices, the deciding channel's first
        if strcmp(m.rule, 'B alone')
            pairs = pairs(:, [2 1]);
        end
        amounts = m.levels(pairs);
        amounts = reshape(amounts, [], 2);
end
nGroups = size(amounts, 1);
aBins = amountBins(amounts(:, 1)', nBins);
bBins = amountBins(amounts(:, 2)', nBins);
states = zeros(nBins, nGroups, 'uint8');
labels = cell(1, nGroups);
evidence = zeros(1, nGroups);
pLeft = zeros(1, nGroups);
for k = 1:nGroups
    [states(:, k), fits] = mixtureColumn(aBins(k), bBins(k), nBins, m);
    if ~fits
        error('lum:pattern:generate:cyclesTooShort', ...
              ['A %g ms, B %g ms cannot be spread over %d cycles: a channel needs at least one '...
               'bin of light in every cycle. Use fewer cycles or a finer bin.'], ...
              round(1000 * aBins(k) * bin, 1), round(1000 * bBins(k) * bin, 1), m.cycles);
    end
    labels{k} = sprintf('A %g : B %g ms', round(1000 * aBins(k) * bin, 1), ...
                        round(1000 * bBins(k) * bin, 1));
    [evidence(k), pLeft(k)] = mixtureEvidence(m, aBins(k), bBins(k), nBins);
end
if ismember(m.rule, {'A alone', 'B alone'})
    % By level, not by bins, so that an odd middle level pays either side exactly.
    deciding = pairs(:, 1 + strcmp(m.rule, 'B alone'))';
    middle = (numel(m.levels) + 1) / 2;
    highPays = double(strcmp(m.rule, 'A alone'));
    pLeft = 0.5 * ones(1, nGroups);
    pLeft(deciding > middle) = highPays;
    pLeft(deciding < middle) = 1 - highPays;
end
[~, first] = unique([aBins(:), bBins(:)], 'rows', 'stable');
if numel(first) < nGroups
    same = setdiff(1:nGroups, first);
    twin = find(aBins == aBins(same(1)) & bBins == bBins(same(1)), 1);
    error('lum:pattern:generate:groupsTooClose', ...
          ['Groups %d and %d come to the same light, %s, in %d bins of %g ms. Use a finer bin '...
           'or amounts further apart.'], twin, same(1), labels{same(1)}, nBins, ...
          round(1000 * bin, 2));
end
[name, edge] = mixtureAxis(m);
d = design(states, 1:nGroups, labels, pLeft, name, evidence, edge, false);


function d = mixturePerTrial(g, nBins, nTrials, bin, stream)
% New amounts for every trial, drawn within the listed range on the side of the boundary
% the trial's group pays: the measure evenly, the total evenly on a log scale (share,
% alone rules) or evenly (difference).
m = mixtureParameters(g, nBins);
categories = balancedAssignments(nTrials, 2, stream);
states = zeros(nBins, nTrials, 'uint8');
evidence = zeros(1, nTrials);
for t = 1:nTrials
    paysLeft = categories(t) == 1;
    accepted = false;
    for attempt = 1:10000
        switch m.rule
            case 'share'
                share = drawOnSide(stream, m.shareRange, m.criterion, paysLeft);
                total = drawLogUniform(stream, m.totalRange);
                amounts = [share, 1 - share] * total;
            case 'difference'
                delta = drawOnSide(stream, m.differenceRange, m.criterion, paysLeft);
                total = m.totalRange(1) + rand(stream) * diff(m.totalRange);
                amounts = [total + delta, total - delta] / 2;
            case 'A alone'
                amounts = [drawLogOnSide(stream, m.levels([1 end]), m.criterion, paysLeft), ...
                           drawLogUniform(stream, m.levels([1 end]))];
            case 'B alone'
                amounts = [drawLogUniform(stream, m.levels([1 end])), ...
                           drawLogOnSide(stream, m.levels([1 end]), m.criterion, ~paysLeft)];
        end
        if any(amounts < 0) || any(amounts > 1)
            continue
        end
        aBins = amountBins(amounts(1), nBins);
        bBins = amountBins(amounts(2), nBins);
        [value, pays] = mixtureEvidence(m, aBins, bBins, nBins);
        [column, fits] = mixtureColumn(aBins, bBins, nBins, m);
        if pays == double(paysLeft) && fits   % Rounded to bins, still on its side
            accepted = true;
            break
        end
    end
    if ~accepted
        error('lum:pattern:generate:levelsTooClose', ...
              ['No whole-bin amounts fall on one side of the boundary within the ranges given%s. '...
               'Use a finer bin, or values further from the boundary.'], ...
              spreadClause(m));
    end
    states(:, t) = column;
    evidence(t) = value;
end
[name, edge] = mixtureAxis(m);
switch m.rule
    case 'share'
        if abs(m.criterion - 0.5) < 1e-12
            labels = {'More A', 'More B'};
        else
            labels = {sprintf('A share above %g%%', round(100 * m.criterion, 1)), ...
                      sprintf('A share below %g%%', round(100 * m.criterion, 1))};
        end
    case 'difference'
        if abs(m.criterion) < 1e-12
            labels = {'More A', 'More B'};
        else
            limit = round(1000 * m.criterion * nBins * bin, 1);
            labels = {sprintf('A minus B above %g ms', limit), sprintf('A minus B below %g ms', limit)};
        end
    case 'A alone'
        labels = {'A high', 'A low'};
    case 'B alone'
        labels = {'B low', 'B high'};
end
d = design(states, categories, labels, [1 0], name, evidence, edge, true);


function m = mixtureParameters(g, nBins)
% The mixture family's settings, checked for the rule in use.
rules = {'share', 'difference', 'A alone', 'B alone'};
rule = strtrim(char(g.MixtureRule));
if strcmpi(rule, 'compare')
    rule = 'share';   % Its first name: A share against 50%
end
match = rules(strcmpi(rule, rules));
if isempty(match)
    error('lum:pattern:generate:badMixtureRule', ...
          'The mixture rule must be ''share'', ''difference'', ''A alone'' or ''B alone''.');
end
m = struct('rule', match{1});
switch lower(strtrim(char(g.MixtureLayout)))
    case 'spread'
        m.layout = 'spread';
    case 'onset'
        m.layout = 'onset';
    case {'centred', 'centered'}
        m.layout = 'centred';
    otherwise
        error('lum:pattern:generate:badMixtureLayout', ...
              'The mixture layout must be ''spread'', ''onset'' or ''centred''.');
end
m.cycles = 1;
if strcmp(m.layout, 'spread')
    cycles = g.MixtureCycles;
    if ~(isscalar(cycles) && isnumeric(cycles) && cycles >= 1 && mod(cycles, 1) == 0)
        error('lum:pattern:generate:badMixtureCycles', ...
              'The mixture is spread over a whole number of cycles, 1 or more.');
    end
    if cycles > nBins
        error('lum:pattern:generate:badMixtureCycles', ...
              'The window has %d bins, fewer than the %d cycles. Use a finer bin or fewer cycles.', ...
              nBins, cycles);
    end
    m.cycles = cycles;
end
switch m.rule
    case 'share'
        ratios = g.MixtureRatios;
        if isempty(ratios) || ~isnumeric(ratios) || size(ratios, 2) ~= 2 ...
                || any(~isfinite(ratios(:))) || any(ratios(:) < 0) || any(sum(ratios, 2) <= 0)
            error('lum:pattern:generate:badMixtureRatios', ...
                  ['Mixture ratios are pairs of parts, A:B, e.g. 2:1 1:2 or 80:20 60:40 40:60 '...
                   '20:80, each with a part above 0.']);
        end
        edge = g.MixtureShareBoundary;
        if ~isnumeric(edge) || numel(edge) ~= 2 || any(~isfinite(edge)) || any(edge <= 0)
            error('lum:pattern:generate:badMixtureBoundary', ...
                  'The boundary is a ratio A:B with both parts above 0, e.g. 1:1 or 60:40.');
        end
        m.ratios = ratios;
        m.criterion = edge(1) / sum(edge);
        m.totals = mixtureTotals(g.MixtureShareTotals);
        shares = ratios(:, 1)' ./ sum(ratios, 2)';
        m.shareRange = [min(shares), max(shares)];
        m.totalRange = [min(m.totals), max(m.totals)];
    case 'difference'
        differences = g.MixtureDifferences(:)';
        if isempty(differences) || ~isnumeric(differences) || any(~isfinite(differences)) ...
                || any(abs(differences) > 1)
            error('lum:pattern:generate:badMixtureDifferences', ...
                  ['A minus B values are fractions of the window, from -1 to 1, e.g. '...
                   '0.1 -0.1.']);
        end
        edge = g.MixtureDifferenceBoundary;
        if ~(isscalar(edge) && isnumeric(edge) && isfinite(edge) && abs(edge) < 1)
            error('lum:pattern:generate:badMixtureBoundary', ...
                  'The boundary is one value of A minus B, a fraction of the window, e.g. 0.');
        end
        m.differences = differences;
        m.criterion = edge;
        m.totals = mixtureTotals(g.MixtureDifferenceTotals);
        m.differenceRange = [min(differences), max(differences)];
        m.totalRange = [min(m.totals), max(m.totals)];
    otherwise
        levels = g.MixtureLevels(:)';
        if ~isnumeric(levels) || any(~isfinite(levels)) || any(levels <= 0 | levels > 1)
            error('lum:pattern:generate:badMixtureLevels', ...
                  'Amount levels are fractions of the window, each in (0, 1], e.g. 0.1 0.2 0.4 0.8.');
        end
        levels = unique(levels);
        if numel(levels) < 2
            error('lum:pattern:generate:badMixtureLevels', 'Give at least two amount levels.');
        end
        levelBins = binsFor(levels, nBins);
        if numel(unique(levelBins)) < numel(levels)
            error('lum:pattern:generate:levelsTooClose', ...
                  ['Two amount levels come to the same number of bins. Use a finer bin or '...
                   'levels further apart.']);
        end
        m.levels = levels;
        m.criterion = middleLevel(levels);
end


function totals = mixtureTotals(totals)
% The totals of light a relative rule roves over, checked.
totals = totals(:)';
if isempty(totals) || ~isnumeric(totals) || any(~isfinite(totals)) || any(totals <= 0) ...
        || any(totals > 2)
    error('lum:pattern:generate:badMixtureTotals', ...
          ['Total light is how long A and B are lit, added, as a fraction of the window: '...
           'numbers above 0 and up to 2, e.g. 0.3 0.6 1.2.']);
end


function [value, pays] = mixtureEvidence(m, aBins, bBins, nBins)
% The rule's measure of one pair of amounts, and the side it pays: 1 left, 0 right,
% 0.5 either (on the boundary).
switch m.rule
    case 'share'
        value = 0.5;
        if aBins + bBins > 0
            value = aBins / (aBins + bBins);
        end
        above = value - m.criterion;
    case 'difference'
        value = (aBins - bBins) / nBins;
        above = value - m.criterion;
    case 'A alone'
        value = aBins / nBins;
        above = value - m.criterion;
    case 'B alone'
        value = bBins / nBins;
        above = m.criterion - value;   % More B pays right
end
tolerance = 1e-9;
if above > tolerance
    pays = 1;
elseif above < -tolerance
    pays = 0;
else
    pays = 0.5;
end


function [name, edge] = mixtureAxis(m)
% The rule's evidence and the boundary it draws in the plane of u_A and u_B.
switch m.rule
    case 'share'
        name = 'A share of the light';
        edge = lineBoundary((1 - m.criterion) / m.criterion, 0);
    case 'difference'
        name = 'A minus B, fraction of the window';
        edge = lineBoundary(1, 0 - m.criterion);
    case 'A alone'
        name = 'A lit, fraction of the window';
        edge = boundary('vertical', m.criterion);
    case 'B alone'
        name = 'B lit, fraction of the window';
        edge = boundary('horizontal', m.criterion);
end


function [column, fits] = mixtureColumn(aBins, bBins, nBins, m)
% Both channels lit for their amounts: spread over the window in cycles, from onset, or
% centred. Spread, the window is cut into m.cycles cycles of (near) equal length, each
% channel's amount is shared out over them in proportion to their length, and in every
% cycle both channels start together, so the mixture is present throughout the window
% and the dark is a gap at the end of each cycle. fits is false when a lit channel would
% have no light in some cycle (too few bins to go round).
column = zeros(nBins, 1, 'uint8');
fits = true;
switch m.layout
    case 'spread'
        widths = allocateBins(ones(1, m.cycles), nBins);
        starts = [0, cumsum(widths(1:end-1))];
        litA = spreadBins(aBins, widths, starts);
        litB = spreadBins(bBins, widths, starts);
        fits = (aBins == 0 || aBins >= m.cycles) && (bBins == 0 || bBins >= m.cycles);
    case 'centred'
        litA = floor((nBins - aBins) / 2) + (1:aBins);
        litB = floor((nBins - bBins) / 2) + (1:bBins);
    otherwise
        litA = 1:aBins;
        litB = 1:bBins;
end
column(litA) = column(litA) + 1;
column(litB) = column(litB) + 2;


function lit = spreadBins(amount, widths, starts)
% The bins a channel lights when its amount is shared over cycles, from each cycle's start.
lit = zeros(1, 0);
if amount <= 0
    return
end
perCycle = allocateBins(widths, amount);
for k = 1:numel(widths)
    lit = [lit, starts(k) + (1:perCycle(k))]; %#ok<AGROW>
end


function text = spreadClause(m)
% A clause for errors about amounts that must also go round the cycles.
text = '';
if strcmp(m.layout, 'spread')
    text = sprintf(' and with light in each of the %d cycles', m.cycles);
end


function level = middleLevel(levels)
% Where the alone rules divide the levels: halfway between the two middle ones, or the
% middle one itself.
n = numel(levels);
if mod(n, 2) == 0
    level = (levels(n / 2) + levels(n / 2 + 1)) / 2;
else
    level = levels((n + 1) / 2);
end


function n = amountBins(fraction, nBins)
% Bins lit by an amount: none for nothing, otherwise at least one and at most all.
n = zeros(size(fraction));
lit = fraction > 1e-12;
n(lit) = min(nBins, max(1, round(fraction(lit) * nBins)));


function value = drawOnSide(stream, range, criterion, above)
% A value evenly within the range, on one side of the criterion.
low = range(1);
high = range(2);
if above
    low = max(low, criterion);
else
    high = min(high, criterion);
end
if ~(high > low)
    error('lum:pattern:generate:noRoomOnOneSide', ...
          ['New values every trial need the listed values on both sides of the boundary; '...
           'these leave no room on one side.']);
end
value = low + rand(stream) * (high - low);


function value = drawLogUniform(stream, range)
% A value evenly spread on a log scale within the range.
value = exp(log(range(1)) + rand(stream) * (log(range(2)) - log(range(1))));


function value = drawLogOnSide(stream, range, criterion, above)
% A value evenly spread on a log scale within the range, on one side of the criterion.
low = range(1);
high = range(2);
if above
    low = max(low, criterion);
else
    high = min(high, criterion);
end
value = exp(log(low) + rand(stream) * (log(high) - log(low)));


function d = countDesign(g, nBins, nTrials, perTrial, stream)
% Slots holding one flash of A, one of B, or nothing; one group per pair of counts.
slots = g.CountSlots;
if ~(isscalar(slots) && isnumeric(slots) && slots >= 1 && mod(slots, 1) == 0)
    error('lum:pattern:generate:badCountSlots', 'The number of slots must be a whole number, 1 or more.');
end
pairs = g.CountPairs;
if isempty(pairs) || ~isnumeric(pairs) || size(pairs, 2) ~= 2 || any(~isfinite(pairs(:))) ...
        || any(pairs(:) < 0) || any(mod(pairs(:), 1) ~= 0)
    error('lum:pattern:generate:badCountPairs', ...
          'Counts are pairs of whole numbers of A and B flashes, written A:B, e.g. 3:2 2:3.');
end
tooMany = find(sum(pairs, 2) > slots, 1);
if ~isempty(tooMany)
    error('lum:pattern:generate:badCountPairs', ...
          'The count %d:%d needs %d slots, but the window has %d.', pairs(tooMany, 1), ...
          pairs(tooMany, 2), sum(pairs(tooMany, :)), slots);
end
[starts, lit] = slotLayout(slots, g.CountFill, nBins, 'slot');

nGroups = size(pairs, 1);
labels = compose('%d A : %d B', pairs(:, 1), pairs(:, 2))';
pLeft = 0.5 * ones(1, nGroups);
pLeft(pairs(:, 1) > pairs(:, 2)) = 1;
pLeft(pairs(:, 1) < pairs(:, 2)) = 0;
groupEvidence = (pairs(:, 1) - pairs(:, 2))';

if perTrial
    groups = balancedAssignments(nTrials, nGroups, stream);
else
    groups = 1:nGroups;
end
states = zeros(nBins, numel(groups), 'uint8');
for k = 1:numel(groups)
    counts = pairs(groups(k), :);
    letters = [ones(1, counts(1)), 2 * ones(1, counts(2)), zeros(1, slots - sum(counts))];
    letters = letters(randperm(stream, slots));
    states(:, k) = flashColumn(letters, starts, lit, nBins);
end
d = design(states, groups, labels, pLeft, 'A flashes minus B flashes', groupEvidence(groups), ...
           boundary('diagonal'), perTrial);


function d = orderDesign(g, nBins, nTrials, perTrial, stream)
% A and B taking turns, meeting in an overlap; the category is which comes first.
designName = lower(strtrim(char(g.OrderDesign)));
if ~ismember(designName, {'simple', 'guarded'})
    error('lum:pattern:generate:badOrderDesign', 'The order design must be ''simple'' or ''guarded''.');
end
cycles = g.OrderCycles;
if ~(isscalar(cycles) && isnumeric(cycles) && cycles >= 1 && mod(cycles, 1) == 0)
    error('lum:pattern:generate:badOrderCycles', 'The number of turns must be a whole number, 1 or more.');
end
widths = allocateBins(ones(1, cycles), nBins);

if strcmp(designName, 'simple')
    overlap = g.OrderOverlap;
    if ~(isscalar(overlap) && isnumeric(overlap) && overlap >= 0 && overlap < 1)
        error('lum:pattern:generate:badOrderOverlap', ...
              'The overlap is a fraction of a turn, from 0 up to (not including) 1.');
    end
    aFirst = zeros(nBins, 1, 'uint8');
    cursor = 0;
    for c = 1:cycles
        parts = allocateBins([(1 - overlap) / 2, overlap, (1 - overlap) / 2], widths(c));
        if parts(1) < 1 || parts(3) < 1
            error('lum:pattern:generate:orderTooShort', ...
                  ['A turn of %d bin(s) leaves no time for a channel alone. Use fewer turns, a '...
                   'finer bin or a smaller overlap.'], widths(c));
        end
        aFirst(cursor + (1:widths(c))) = repelem(uint8([1 3 2]), parts);
        cursor = cursor + widths(c);
    end
    labels = {'A first', 'B first'};
    perTrial = false;  % A random phase would hide which came first
else
    short = g.OrderShortOverlap;
    long = g.OrderLongOverlap;
    if ~(isscalar(short) && isscalar(long) && short > 0 && long > short && short + long < 1)
        error('lum:pattern:generate:badOrderGuards', ...
              ['The guarded cycle needs a short overlap above 0, a long overlap longer than '...
               'it, and the two together under 1 (they are fractions of a turn).']);
    end
    alone = (1 - short - long) / 2;
    aFirst = zeros(nBins, 1, 'uint8');
    cursor = 0;
    for c = 1:cycles
        parts = allocateBins([alone, short, alone, long], widths(c));
        if any(parts < 1) || parts(4) <= parts(2)
            error('lum:pattern:generate:orderTooShort', ...
                  ['A turn of %d bin(s) is too short for the guarded cycle. Use fewer turns or '...
                   'a finer bin.'], widths(c));
        end
        aFirst(cursor + (1:widths(c))) = repelem(uint8([1 3 2 3]), parts);
        cursor = cursor + widths(c);
    end
    labels = {'A leads', 'B leads'};
end
templates = [aFirst, swapChannels(aFirst)];

if perTrial
    % A random phase every trial: each channel on its own is then the same stretch of
    % light at a random place, whichever leads.
    groups = balancedAssignments(nTrials, 2, stream);
    states = zeros(nBins, nTrials, 'uint8');
    for t = 1:nTrials
        states(:, t) = circshift(templates(:, groups(t)), randi(stream, widths(1)) - 1);
    end
else
    groups = [1 2];
    states = templates;
end
d = design(states, groups, labels, [1 0], '', NaN(1, numel(groups)), boundary('none'), perTrial);


function d = motifDesign(g, nBins)
% One group per word, one flash per letter.
leftWords = parseWords(g.MotifLeftWords);
rightWords = parseWords(g.MotifRightWords);
words = [leftWords, rightWords];
if isempty(words)
    error('lum:pattern:generate:noWords', 'List at least one word, for the left or the right port.');
end
lengths = cellfun(@numel, words);
if any(lengths ~= lengths(1))
    error('lum:pattern:generate:badWords', ...
          'Every word must have the same number of letters; these have %s.', ...
          strjoin(compose('%d', unique(lengths)), ', '));
end
[starts, lit] = slotLayout(lengths(1), g.MotifFill, nBins, 'letter');

nGroups = numel(words);
states = zeros(nBins, nGroups, 'uint8');
codes = containers.Map({'-', 'A', 'B', 'X'}, {0, 1, 2, 3});
for k = 1:nGroups
    letters = cellfun(@(c) codes(c), num2cell(words{k}));
    states(:, k) = flashColumn(letters, starts, lit, nBins);
end
pLeft = [ones(1, numel(leftWords)), zeros(1, numel(rightWords))];
d = design(states, 1:nGroups, words, pLeft, '', NaN(1, nGroups), boundary('none'), false);


function words = parseWords(text)
% Words typed as text, separated by spaces or commas; '.', '_' and '0' also mean dark.
if iscell(text)
    text = strjoin(cellfun(@char, text, 'UniformOutput', false), ' ');
end
text = upper(strtrim(char(text)));
if isempty(text)
    words = {};
    return
end
words = strsplit(text, {' ', ',', ';', sprintf('\t')});
words = words(~cellfun(@isempty, words));
words = regexprep(words, '[._0]', '-');
bad = words(~cellfun(@isempty, regexp(words, '[^AB X-]', 'once')));
if ~isempty(bad)
    error('lum:pattern:generate:badWords', ...
          'Words use the letters A, B, X (both) and - (dark): "%s" does not.', bad{1});
end


function d = arbitraryDesign(g, nBins, bin, duration)
% Pulses typed in by hand, one row per pulse: [group, channel, start, end].
nGroups = g.nGroups;
if ~(isscalar(nGroups) && isnumeric(nGroups) && nGroups >= 1 && mod(nGroups, 1) == 0)
    error('lum:pattern:generate:badGroupCount', 'The number of groups must be a positive integer.');
end
pulses = g.Pulses;
if isempty(pulses)
    pulses = zeros(0, 4);
end
if size(pulses, 2) ~= 4 || any(~isfinite(pulses(:)))
    error('lum:pattern:generate:badPulses', ...
          'Pulses must be rows of [group, channel, start (s), end (s)].');
end
states = zeros(nBins, nGroups, 'uint8');
edges = (0:nBins)' * bin;
binStart = edges(1:end-1);
binEnd = edges(2:end);
tolerance = bin * 1e-6;
for row = 1:size(pulses, 1)
    group = pulses(row, 1);
    channel = pulses(row, 2);
    pulseStart = pulses(row, 3);
    pulseEnd = pulses(row, 4);
    if group < 1 || group > nGroups || mod(group, 1) ~= 0
        error('lum:pattern:generate:badPulses', ...
              'Pulse %d is for group %g, but there are %d groups.', row, group, nGroups);
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
labels = compose('Custom %d', 1:nGroups);
d = design(states, 1:nGroups, labels, lum.pattern.defaultPLeft(nGroups), '', ...
           NaN(1, nGroups), boundary('none'), false);


%% Offsets --------------------------------------------------------------------

function states = applyOffsets(states, g, bin, patternGroup, nGroups)
% Shift each channel's light in time, per group or for every pattern.
shiftA = offsetBins(g.AOffset, bin, patternGroup, nGroups, 'A');
shiftB = offsetBins(g.BOffset, bin, patternGroup, nGroups, 'B');
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


function shifts = offsetBins(offset, bin, patternGroup, nGroups, channel)
% An offset in seconds as whole bins, one per pattern, through each pattern's group.
offset = offset(:)';
if isempty(offset)
    offset = 0;
end
if ~isnumeric(offset) || any(~isfinite(offset))
    error('lum:pattern:generate:badOffset', 'Channel %s offsets must be finite.', channel);
end
if isscalar(offset)
    offset = repmat(offset, 1, nGroups);
elseif numel(offset) ~= nGroups
    error('lum:pattern:generate:badOffset', ...
          'Channel %s needs one offset, or one per group (%d).', channel, nGroups);
end
shifts = round(offset(max(patternGroup, 1)) / bin);


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

function d = design(states, patternGroup, labels, pLeft, evidenceName, evidence, edge, perTrial)
% The fields every family returns.
d = struct('States', states, 'PatternGroup', patternGroup, 'GroupLabels', {labels}, ...
           'FamilyPLeft', pLeft, 'EvidenceName', evidenceName, 'Evidence', evidence, ...
           'Boundary', edge, 'Continuous', perTrial);


function edge = boundary(kind, value)
% Where the contingency divides the plane of u_A and u_B: 'diagonal', 'vertical' or
% 'horizontal' at Value, 'line' (u_B = Slope * u_A + Intercept, see lineBoundary) or 'none'.
if nargin < 2
    value = NaN;
end
edge = struct('Kind', kind, 'Value', value, 'Slope', NaN, 'Intercept', NaN);


function edge = lineBoundary(slope, intercept)
% A boundary u_B = slope * u_A + intercept (fractions of the window): the diagonal when it
% is the identity line.
if abs(slope - 1) < 1e-12 && abs(intercept) < 1e-12
    edge = boundary('diagonal');
else
    edge = boundary('line');
end
edge.Slope = slope;
edge.Intercept = intercept;


function [starts, lit] = slotLayout(nSlots, fill, nBins, what)
% Where each slot starts (bins before it) and how many of its bins its flash lights.
% A flash shorter than its slot leaves at least one dark bin after it, so two flashes
% on one channel in neighbouring slots stay two flashes.
if ~(isscalar(fill) && isnumeric(fill) && fill > 0 && fill <= 1)
    error('lum:pattern:generate:badFill', 'The %s fill must be a fraction in (0, 1].', what);
end
if nSlots > nBins
    error('lum:pattern:generate:tooManySlots', ...
          'The window has %d bins, fewer than the %d %ss. Use a finer bin.', nBins, nSlots, what);
end
widths = allocateBins(ones(1, nSlots), nBins);
starts = [0, cumsum(widths(1:end-1))];
if fill >= 1
    lit = widths;
    return
end
if any(widths < 2)
    error('lum:pattern:generate:slotsTooShort', ...
          ['Each %s has only %d bin, too short for a flash and a gap after it. Use fewer '...
           '%ss, a finer bin, or a fill of 1.'], what, min(widths), what);
end
lit = min(widths - 1, max(1, round(fill * widths)));


function column = flashColumn(letters, starts, lit, nBins)
% One flash per slot: 1 A, 2 B, 3 both, 0 nothing.
column = zeros(nBins, 1, 'uint8');
for s = 1:numel(letters)
    if letters(s) > 0
        column(starts(s) + (1:lit(s))) = letters(s);
    end
end


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
