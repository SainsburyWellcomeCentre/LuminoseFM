function [S, accepted, app] = StimulusDesigner(S, rig, varargin)
% lum.gui.StimulusDesigner designs a session's light patterns and trial order.
%
% The generator (lum.pattern.generate) makes a whole session at once: a family of
% two-channel patterns, the groups of the session, and a balanced, shuffled order of
% trials. The family is the question the animal answers (which channel, how much of the
% mixture is A, which flashes more often, which comes first, which word), and choosing
% one loads its defaults, ready to run (lum.pattern.familyDefaults). This window puts
% the family's settings in front of the operator, recompiles on each edit, and shows
% the result the way the session will run it: a table of groups, with how many trials
% each gets, how many global timers its busiest pattern costs and the chance it pays
% the left port; how well one cue alone could do (lum.pattern.shortcuts); and a browser
% to scroll through every trial. docs/stimulus_family.md describes every family.
%
% P(left) follows the family until the operator types their own in the table; typed
% values are kept while the groups stay the same, and the family's come back when they
% change (lum.pattern.typedPLeft).
%
% It opens from the setup dialog's Stimulus tab, and on its own for designing away
% from the rig:
%
%   S = lum.gui.StimulusDesigner();            % defaults, the connected machine's budget
%   S = lum.gui.StimulusDesigner(S, RigConfig);
%
% Only S.Stimulus.Generator, S.Stimulus.Duration and S.Task.GroupPLeft are changed.
% Nothing leaves the window until the patterns compile within the timer budget.
%
% Options:
%   'Wait'     false to return at once with the window open (for tests); default true
%   'Visible'  'on' (default) or 'off'
%
% Returns:
%   S         The settings, with the design applied if accepted
%   accepted  True if the operator chose 'Use these stimuli'
%   app       With 'Wait' false: .Figure, .collect(), .refresh(), .apply(), .cancel(),
%             .status(), .chooseFamily(name), .editPLeft(values), .familyPLeft(),
%             .stimulusSet() and .controls
%
% See also: lum.pattern.generate, lum.pattern.stimulusSet, lum.pattern.families,
%           lum.gui.SetupDialog, lum.gui.PatternBrowser

if nargin < 1 || isempty(S)
    S = lum.pattern.prepareSeed(lum.defaultSettings);
end
if nargin < 2 || isempty(rig)
    rig = RigConfig;
end
p = inputParser;
p.FunctionName = 'lum.gui.StimulusDesigner';
addParameter(p, 'Wait', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'Visible', 'on');
parse(p, varargin{:});

accepted = false;
t = lum.gui.theme();
families = lum.pattern.families();
generator = lum.pattern.withGeneratorDefaults(S.Stimulus.Generator);
pLeftTyped = S.Task.GroupPLeft;  % Empty: the family's contingency
pLeftFor = {};                   % The groups typed values belong to; {} when not known
shownSet = [];

fig = uifigure('Name', 'LuminoseFM - stimulus designer', 'Position', [70 50 1320 860], ...
               'Color', t.Background, 'Visible', p.Results.Visible);
lum.gui.Form.waitForView(fig);  % Before any content (see waitForView)
outer = uigridlayout(fig, [3 1], 'RowHeight', {54, '1x', 34}, 'Padding', [14 10 14 12], ...
                     'RowSpacing', 8, 'BackgroundColor', t.Background);

header = uigridlayout(outer, [1 2], 'ColumnWidth', {48, '1x'}, 'Padding', 0, ...
                      'ColumnSpacing', 12, 'BackgroundColor', t.Background);
logoImage = lum.gui.logo(96);
if isempty(logoImage)
    uilabel(header, 'Text', '');
else
    uiimage(header, 'ImageSource', logoImage, 'ScaleMethod', 'fit');
end
titles = uigridlayout(header, [2 1], 'RowHeight', {26, 20}, 'Padding', 0, 'RowSpacing', 0, ...
                      'BackgroundColor', t.Background);
uilabel(titles, 'Text', 'Stimulus designer', 'FontSize', 18, 'FontWeight', 'bold', ...
        'FontColor', t.Ink);
uilabel(titles, 'Text', sprintf(['Light patterns on channels A and B, and the order of %d '...
                                 'trials  |  %s with %d global timers'], S.Session.MaxTrials, ...
                                rig.MachineModel, rig.Limits.GlobalTimers), 'FontColor', t.Muted);

main = uigridlayout(outer, [1 2], 'ColumnWidth', {460, '1x'}, 'Padding', 0, ...
                    'ColumnSpacing', 12, 'BackgroundColor', t.Background);
left = uigridlayout(main, [4 1], 'RowHeight', {panelHeight(4), 170, 330, panelHeight(3)}, ...
                    'Padding', 0, 'RowSpacing', 10, 'BackgroundColor', t.Background, ...
                    'Scrollable', 'on');
controls = struct();

%% Window and trial order
form = formPanel(left, 'Window and trial order', 4, t);
label(form, 'Stimulus window (s)', t);
controls.Window = numberField(form, S.Stimulus.Duration, [0.001 60], true, @refresh);
controls.Window.Tooltip = 'How long the light pattern lasts, from stimulus onset.';
label(form, 'Bin (s)', t);
controls.Bin = numberField(form, generator.BinDuration, [0.0001 10], false, @refresh);
controls.Bin.Tooltip = ['The time step patterns are drawn on: every edge of the light falls '...
                        'on a bin. Adjusted, if need be, so that the window holds whole bins.'];
label(form, 'Seed', t);
seedRow = uigridlayout(form, [1 2], 'ColumnWidth', {'1x', 90}, 'Padding', 0, ...
                       'ColumnSpacing', 6, 'BackgroundColor', t.Panel);
controls.Seed = numberField(seedRow, generator.Seed, [0 2^32 - 1], false, @refresh);
controls.Seed.RoundFractionalValues = 'on';
controls.Seed.ValueDisplayFormat = '%.0f';
controls.Seed.Tooltip = ['Fixes the trial order, and whatever the family draws at random '...
                         '(the order of the flashes, per-trial amounts, the phase). Saved with '...
                         'the data: type an earlier session''s seed to repeat its trials.'];
uibutton(seedRow, 'Text', 'Randomise', 'ButtonPushedFcn', @(~, ~) newSeed(), ...
         'Tooltip', ['Draw a new seed: every trial drawn again, the order and whatever the family '...
                     'draws at random']);
label(form, 'Each session', t);
controls.NewSeedEachSession = uicheckbox(form, 'Text', 'a new seed (untick to keep this one)', ...
    'Value', generator.NewSeedEachSession, 'ValueChangedFcn', @(~, ~) refresh(), ...
    'Tooltip', ['On (the default), each session of this animal starts with a new seed, so no '...
                'two sessions deliver the same trials. Off, the next session keeps this seed.']);

%% Family
panel = uipanel(left, 'Title', 'Family: what the animal tells apart', 'FontWeight', 'bold', ...
                'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
familyGrid = uigridlayout(panel, [3 1], 'RowHeight', {26, 20, '1x'}, 'Padding', [10 8 10 8], ...
                          'RowSpacing', 4, 'BackgroundColor', t.Panel);
familyRow = uigridlayout(familyGrid, [1 2], 'ColumnWidth', {'1x', 120}, 'Padding', 0, ...
                         'ColumnSpacing', 8, 'BackgroundColor', t.Panel);
controls.Family = uidropdown(familyRow, 'Items', {families.Label}, 'ItemsData', {families.Name}, ...
                             'Value', choice(generator.Family, {families.Name}), ...
                             'ValueChangedFcn', @(source, ~) chooseFamily(source.Value), ...
                             'Tooltip', 'Choosing a family loads its defaults, ready to run');
uibutton(familyRow, 'Text', 'Restore defaults', 'ButtonPushedFcn', ...
         @(~, ~) chooseFamily(controls.Family.Value), ...
         'Tooltip', 'Put this family''s settings back to its defaults');
controls.Question = uilabel(familyGrid, 'Text', '', 'FontWeight', 'bold', 'FontColor', t.Ink);
controls.FamilyNote = uilabel(familyGrid, 'Text', '', 'WordWrap', 'on', 'FontColor', t.Muted, ...
                              'FontSize', 11, 'VerticalAlignment', 'top');

%% Each family's settings, stacked in one cell; only the chosen family's is shown
host = uipanel(left, 'Title', 'Family settings', 'FontWeight', 'bold', ...
               'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
hostGrid = uigridlayout(host, [1 1], 'Padding', 0, 'BackgroundColor', t.Panel);
controls.FamilyPanels = struct();

[form, controls.FamilyPanels.pure] = familyForm(hostGrid, 2, t);
label(form, 'Channels', t);
controls.PureChannels = uidropdown(form, 'Items', {'A and B', 'A only', 'B only'}, ...
    'ItemsData', {'A and B', 'A', 'B'}, 'ValueChangedFcn', @(~, ~) refresh(), ...
    'Tooltip', 'A and B: A pays left, B right. One channel alone pays either side.');
label(form, 'Lit fraction(s)', t);
controls.PureFractions = textField(form, [], @refresh);
controls.PureFractions.Tooltip = ['Fractions of the window the channel is lit for, from '...
                                  'onset: 1, or several (0.25 0.5 1) to vary the duration'];
controls.PureNote = familyNote(form, ['One group per lit fraction and channel. With several '...
    'fractions each channel is lit for different durations, so only which channel is lit '...
    'tells the side.'], t);

[form, controls.FamilyPanels.mixture] = familyForm(hostGrid, 6, t);
label(form, 'Decision rule', t);
controls.MixtureRule = uidropdown(form, ...
    'Items', {'Relative: A share of the mixture', 'Relative: A minus B', ...
              'A alone decides (control)', 'B alone decides (control)'}, ...
    'ItemsData', {'share', 'difference', 'A alone', 'B alone'}, ...
    'ValueChangedFcn', @(~, ~) refresh(), ...
    'Tooltip', ['A share: A''s part of the light, u_A / (u_A + u_B), its relative abundance in '...
                'the mixture; more A than the boundary ratio pays left. A minus B: the same '...
                'with the difference. A alone or B alone: one channel''s amount decides and the '...
                'other is a distractor.']);
% The rule's own settings take rows 2 to 4, one stacked panel per kind of rule.
controls.MixtureRulePanels = struct();
[rows, controls.MixtureRulePanels.share] = ruleRows(form, 2, 3, t);
label(rows, 'Mixture ratios, A:B', t);
controls.MixtureRatios = uieditfield(rows, 'text', 'ValueChangedFcn', @(~, ~) refresh(), ...
    'Tooltip', ['One group per mixture ratio at each total, e.g. 2:1 1:2, or 80:20 60:40 40:60 '...
                '20:80 for a psychometric curve']);
label(rows, 'Sides change at, A:B', t);
controls.MixtureShareBoundary = uieditfield(rows, 'text', 'ValueChangedFcn', @(~, ~) refresh(), ...
    'Tooltip', ['The boundary ratio: more A than this pays left, less pays right, equal either '...
                'side. 1:1 asks which is more; 60:40 asks whether A is more than 60% of the mixture']);
label(rows, 'Total light (rove)', t);
controls.MixtureShareTotals = textField(rows, [], @refresh);
controls.MixtureShareTotals.Tooltip = ['How long A and B are lit, added, as fractions of the '...
    'window; every ratio is given at each. Totals that grow by the ratio between the mixtures '...
    '(x2 for 2:1 and 1:2) leave neither amount alone telling the side.'];
[rows, controls.MixtureRulePanels.difference] = ruleRows(form, 2, 3, t);
label(rows, 'A minus B (of the window)', t);
controls.MixtureDifferences = textField(rows, [], @refresh);
controls.MixtureDifferences.Tooltip = ['One group per difference at each total, as fractions of '...
                                       'the window, e.g. 0.1 -0.1'];
label(rows, 'Sides change at A minus B', t);
controls.MixtureDifferenceBoundary = numberField(rows, 0, [-0.99 0.99], false, @refresh);
controls.MixtureDifferenceBoundary.Tooltip = ['A minus B above this pays left, below it right. '...
                                              '0 asks which is more.'];
label(rows, 'Total light (rove)', t);
controls.MixtureDifferenceTotals = textField(rows, [], @refresh);
controls.MixtureDifferenceTotals.Tooltip = ['How long A and B are lit, added, as fractions of the '...
    'window. Totals twice the difference apart (0.3 0.5 0.7 0.9 for +-0.1) leave neither amount '...
    'alone telling the side.'];
[rows, controls.MixtureRulePanels.alone] = ruleRows(form, 2, 3, t);
label(rows, 'Amount levels', t);
controls.MixtureLevels = textField(rows, [], @refresh);
controls.MixtureLevels.Tooltip = ['Fractions of the window a channel can be lit for, e.g. '...
                                  '0.1 0.2 0.4 0.8; every level of A is given with every level of B'];
placed(label(form, 'Placement', t), 5, 1);
placement = placed(uigridlayout(form, [1 3], 'ColumnWidth', {'1x', 56, 44}, 'Padding', 0, ...
                                'ColumnSpacing', 6, 'BackgroundColor', t.Panel), 5, 2);
controls.MixtureLayout = uidropdown(placement, 'Items', {'Spread over the window', ...
    'Both from stimulus onset', 'Both centred in the window'}, ...
    'ItemsData', {'spread', 'onset', 'centred'}, 'ValueChangedFcn', @(~, ~) refresh(), ...
    'Tooltip', ['Where in the window each amount is lit. Spread: shared over cycles, both '...
                'channels starting every cycle, so the mixture lasts the whole window and the '...
                'dark is a gap in each cycle. From onset or centred: one stretch per channel, '...
                'so a small total leaves most of the window dark.']);
controls.MixtureCycles = numberField(placement, 5, [1 100], false, @refresh);
controls.MixtureCycles.RoundFractionalValues = 'on';
controls.MixtureCycles.Tooltip = ['Cycles the amounts are spread over. Each costs a global timer '...
                                  'per channel, and each needs a bin of the smallest amount.'];
label(placement, 'cycles', t);
placed(label(form, 'Every trial', t), 6, 1);
controls.MixtureContinuous = placed(uicheckbox(form, 'Text', 'new amounts each trial', ...
    'ValueChangedFcn', @(~, ~) refresh(), ...
    'Tooltip', ['Draw the amounts afresh for every trial, within the values and totals listed '...
                '(or between the lowest and highest level), instead of a fixed set of groups']), 6, 2);
controls.MixtureNote = familyNote(form, '', t);

[form, controls.FamilyPanels.count] = familyForm(hostGrid, 5, t);
label(form, 'Slots in the window', t);
controls.CountSlots = numberField(form, 5, [1 100], false, @refresh);
controls.CountSlots.RoundFractionalValues = 'on';
controls.CountSlots.Tooltip = 'Each slot holds one flash of A, one of B, or nothing';
label(form, 'Counts, A:B', t);
controls.CountPairs = uieditfield(form, 'text', 'ValueChangedFcn', @(~, ~) refresh(), ...
    'Tooltip', ['One group per count of A and B flashes, e.g. 3:2 2:3. More A pays left, '...
                'more B right, equal counts either side.']);
label(form, 'Fill in counts for', t);
countButtons = uigridlayout(form, [1 2], 'Padding', 0, 'ColumnSpacing', 6, ...
                            'BackgroundColor', t.Panel);
uibutton(countButtons, 'Text', 'every slot lit', 'ButtonPushedFcn', @(~, ~) fillCounts('full'), ...
         'Tooltip', 'Every split of the slots between A and B, from all A to all B');
uibutton(countButtons, 'Text', 'both channels needed', ...
         'ButtonPushedFcn', @(~, ~) fillCounts('ladder'), ...
         'Tooltip', ['Counts one apart with the total roving (1:0 0:1 2:1 1:2 ...), so neither '...
                     'count alone tells the side']);
label(form, 'Flash length (of a slot)', t);
controls.CountFill = numberField(form, 0.5, [0.01 1], false, @refresh);
controls.CountFill.Tooltip = ['How much of its slot a flash lasts. Below 1, two flashes on one '...
                              'channel in a row stay two flashes.'];
label(form, 'Every trial', t);
controls.CountContinuous = uicheckbox(form, 'Text', 'a new order of the flashes', ...
    'ValueChangedFcn', @(~, ~) refresh(), ...
    'Tooltip', 'Untick to give each group one fixed order, which the animal could learn by heart');
controls.CountNote = familyNote(form, ['Each flash costs a global timer, so the slots the '...
    'machine can light are limited by its timers (the status line says how many are left).'], t);

[form, controls.FamilyPanels.order] = familyForm(hostGrid, 5, t);
label(form, 'Design', t);
controls.OrderDesign = uidropdown(form, 'Items', {'Simple: A then B, or B then A', ...
    'Guarded cycle: only relative timing tells'}, 'ItemsData', {'simple', 'guarded'}, ...
    'ValueChangedFcn', @(~, ~) orderDesignChosen(), ...
    'Tooltip', ['Guarded: a short and a long overlap and a random phase, so each channel on '...
                'its own looks the same whichever leads']);
label(form, 'Turns in the window', t);
controls.OrderCycles = numberField(form, 1, [1 100], false, @refresh);
controls.OrderCycles.RoundFractionalValues = 'on';
controls.OrderCycles.Tooltip = 'How many times the channels take turns within the window';
label(form, 'Overlap (of a turn)', t);
controls.OrderOverlap = numberField(form, 0.2, [0 0.95], false, @refresh);
controls.OrderOverlap.Tooltip = ['Simple design: the fraction of a turn both channels are on, '...
                                 'at the handover'];
label(form, 'Short, long overlap', t);
overlapRow = uigridlayout(form, [1 2], 'Padding', 0, 'ColumnSpacing', 6, ...
                          'BackgroundColor', t.Panel);
controls.OrderShortOverlap = numberField(overlapRow, 0.1, [0.001 0.95], false, @refresh);
controls.OrderShortOverlap.Tooltip = ['Guarded cycle: the overlap as the leading channel hands '...
                                      'over'];
controls.OrderLongOverlap = numberField(overlapRow, 0.3, [0.001 0.95], false, @refresh);
controls.OrderLongOverlap.Tooltip = ['Guarded cycle: the overlap at the end of each turn; longer '...
                                     'than the short one'];
label(form, 'Every trial', t);
controls.OrderContinuous = uicheckbox(form, 'Text', 'a random phase (guarded cycle)', ...
    'ValueChangedFcn', @(~, ~) refresh(), ...
    'Tooltip', 'Start each trial at a random point of the cycle');
controls.OrderNote = familyNote(form, '', t);

[form, controls.FamilyPanels.motif] = familyForm(hostGrid, 3, t);
label(form, 'Words paying left', t);
controls.MotifLeftWords = uieditfield(form, 'text', 'ValueChangedFcn', @(~, ~) refresh(), ...
    'Tooltip', 'Words separated by spaces, e.g. AAB BAB');
label(form, 'Words paying right', t);
controls.MotifRightWords = uieditfield(form, 'text', 'ValueChangedFcn', @(~, ~) refresh(), ...
    'Tooltip', 'Words separated by spaces, e.g. ABA BBA');
label(form, 'Flash length (of a letter)', t);
controls.MotifFill = numberField(form, 0.5, [0.01 1], false, @refresh);
controls.MotifFill.Tooltip = 'How much of its letter''s slot each flash lasts';
controls.MotifNote = familyNote(form, ['Letters: A, B, X (A and B together) and - (dark), one '...
    'flash each; every word the same length. One group per word.'], t);

pulsesPanel = uipanel(hostGrid, 'BorderType', 'none', 'BackgroundColor', t.Panel);
pulsesPanel.Layout.Row = 1;
pulsesPanel.Layout.Column = 1;
controls.FamilyPanels.arbitrary = pulsesPanel;
pulsesGrid = uigridlayout(pulsesPanel, [3 1], 'RowHeight', {26, '1x', 28}, 'Padding', [10 8 10 8], ...
                          'RowSpacing', 6, 'BackgroundColor', t.Panel);
groupsRow = uigridlayout(pulsesGrid, [1 2], 'ColumnWidth', {180, '1x'}, 'Padding', 0, ...
                         'ColumnSpacing', 10, 'BackgroundColor', t.Panel);
label(groupsRow, 'Groups', t);
controls.nGroups = numberField(groupsRow, 2, [1 64], false, @refresh);
controls.nGroups.RoundFractionalValues = 'on';
controls.nGroups.Tooltip = 'How many groups the table describes';
controls.Pulses = uitable(pulsesGrid, 'Data', cell(0, 4), ...
    'ColumnName', {'Group', 'Channel', 'Start (s)', 'End (s)'}, ...
    'ColumnEditable', true(1, 4), 'ColumnFormat', {'numeric', {'A', 'B'}, 'numeric', 'numeric'}, ...
    'CellEditCallback', @(~, ~) refresh());
pulseButtons = uigridlayout(pulsesGrid, [1 2], 'Padding', 0, 'ColumnSpacing', 8, ...
                            'BackgroundColor', t.Panel);
uibutton(pulseButtons, 'Text', 'Add pulse', 'ButtonPushedFcn', @(~, ~) addPulse());
uibutton(pulseButtons, 'Text', 'Remove last', 'ButtonPushedFcn', @(~, ~) removePulse());

%% Offsets, for every family
form = formPanel(left, 'Channel offsets, every family', 3, t);
label(form, 'A offset (s)', t);
controls.AOffset = textField(form, generator.AOffset, @refresh);
controls.AOffset.Tooltip = 'Delays channel A''s light: one value, or one per group';
label(form, 'B offset (s)', t);
controls.BOffset = textField(form, generator.BOffset, @refresh);
controls.BOffset.Tooltip = 'Delays channel B''s light: one value, or one per group';
label(form, 'Offset mode', t);
controls.OffsetMode = uidropdown(form, 'Items', {'circular', 'linear'}, ...
    'Value', generator.OffsetMode, 'ValueChangedFcn', @(~, ~) refresh(), ...
    'Tooltip', 'Circular wraps light pushed past the end round to the start; linear drops it');

%% Groups, contingency and every trial
right = uigridlayout(main, [2 1], 'RowHeight', {300, '1x'}, 'Padding', 0, 'RowSpacing', 10, ...
                     'BackgroundColor', t.Background);
panel = uipanel(right, 'Title', 'Groups and contingency', 'FontWeight', 'bold', ...
                'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
groupGrid = uigridlayout(panel, [3 1], 'RowHeight', {'1x', 'fit', 'fit'}, 'Padding', [10 8 10 8], ...
                         'RowSpacing', 6, 'BackgroundColor', t.Panel);
controls.GroupTable = uitable(groupGrid, 'ColumnName', {'Group', 'Label', 'Trials', 'Timers', 'P(left)'}, ...
    'ColumnEditable', [false false false false true], 'ColumnWidth', {50, 'auto', 60, 60, 70}, ...
    'ColumnFormat', {'shortG', 'char', 'shortG', 'shortG', 'shortG'}, ...
    'Data', cell(0, 5), 'CellEditCallback', @(~, ~) onTableEdit());
noteRow = uigridlayout(groupGrid, [1 2], 'ColumnWidth', {'1x', 150}, 'Padding', 0, ...
                       'ColumnSpacing', 8, 'BackgroundColor', t.Panel);
controls.PLeftNote = uilabel(noteRow, 'Text', '', 'WordWrap', 'on', 'FontColor', t.Muted, ...
                             'FontSize', 11);
controls.FamilyPLeft = uibutton(noteRow, 'Text', 'Family''s P(left)', ...
    'ButtonPushedFcn', @(~, ~) useFamilyPLeft(), ...
    'Tooltip', 'Forget the P(left) typed in the table, and use the family''s contingency');
controls.Shortcuts = uilabel(groupGrid, 'Text', '', 'WordWrap', 'on', 'FontColor', t.Ink, ...
                             'FontSize', 11, 'Tooltip', ['The best score an animal could reach '...
                             'reading only one cue: 100% means that cue alone solves the task, 50% '...
                             'that it tells nothing (docs/stimulus_family.md).']);

panel = uipanel(right, 'Title', 'Every trial of the session', 'FontWeight', 'bold', ...
                'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
browserGrid = uigridlayout(panel, [1 1], 'Padding', 8, 'BackgroundColor', t.Panel);
controls.Browser = lum.gui.PatternBrowser(browserGrid);

footer = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 110, 170}, 'Padding', 0, ...
                      'ColumnSpacing', 8, 'BackgroundColor', t.Background);
controls.Status = uilabel(footer, 'Text', '', 'WordWrap', 'on', 'FontSize', 12);
uibutton(footer, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
controls.Apply = uibutton(footer, 'Text', 'Use these stimuli', 'FontWeight', 'bold', ...
                          'BackgroundColor', t.Accent, 'FontColor', [1 1 1], ...
                          'ButtonPushedFcn', @(~, ~) apply());

showGenerator(generator);
fig.WindowKeyPressFcn = @(~, event) controls.Browser.onKey(event);
refresh();
app = struct('Figure', fig, 'collect', @collect, 'refresh', @refresh, 'apply', @apply, ...
             'cancel', @onCancel, 'status', @() controls.Status.Text, ...
             'chooseFamily', @chooseFamily, 'editPLeft', @editPLeft, ...
             'familyPLeft', @useFamilyPLeft, 'stimulusSet', @currentSet, 'controls', controls);
if p.Results.Wait
    uiwait(fig);
end


    function candidate = readControls()
        % The settings as the controls show them. Only the chosen family's settings are
        % read; the other families keep what they had, so a half-typed field there
        % cannot stop this one compiling.
        c = controls;
        g = generator;
        g.Family = c.Family.Value;
        g.BinDuration = c.Bin.Value;
        g.Seed = round(c.Seed.Value);
        g.NewSeedEachSession = c.NewSeedEachSession.Value;
        switch g.Family
            case 'pure'
                g.PureChannels = c.PureChannels.Value;
                g.PureFractions = numbers(c.PureFractions, 'Lit fractions', 1);
            case 'mixture'
                g.MixtureRule = c.MixtureRule.Value;
                switch g.MixtureRule
                    case 'share'
                        g.MixtureRatios = textToPairs(c.MixtureRatios.Value, 'Mixture ratios');
                        g.MixtureShareBoundary = textToPairs(c.MixtureShareBoundary.Value, ...
                                                             'The boundary ratio');
                        g.MixtureShareTotals = numbers(c.MixtureShareTotals, 'Total light', []);
                    case 'difference'
                        g.MixtureDifferences = numbers(c.MixtureDifferences, 'A minus B', []);
                        g.MixtureDifferenceBoundary = c.MixtureDifferenceBoundary.Value;
                        g.MixtureDifferenceTotals = numbers(c.MixtureDifferenceTotals, ...
                                                            'Total light', []);
                    otherwise
                        g.MixtureLevels = numbers(c.MixtureLevels, 'Amount levels', []);
                end
                g.MixtureLayout = c.MixtureLayout.Value;
                g.MixtureCycles = round(c.MixtureCycles.Value);
                g.Continuous = c.MixtureContinuous.Value;
            case 'count'
                g.CountSlots = round(c.CountSlots.Value);
                g.CountPairs = textToPairs(c.CountPairs.Value, 'Counts');
                g.CountFill = c.CountFill.Value;
                g.Continuous = c.CountContinuous.Value;
            case 'order'
                g.OrderDesign = c.OrderDesign.Value;
                g.OrderCycles = round(c.OrderCycles.Value);
                g.OrderOverlap = c.OrderOverlap.Value;
                g.OrderShortOverlap = c.OrderShortOverlap.Value;
                g.OrderLongOverlap = c.OrderLongOverlap.Value;
                g.Continuous = c.OrderContinuous.Value;
            case 'motif'
                g.MotifLeftWords = strtrim(c.MotifLeftWords.Value);
                g.MotifRightWords = strtrim(c.MotifRightWords.Value);
                g.MotifFill = c.MotifFill.Value;
            case 'arbitrary'
                g.nGroups = round(c.nGroups.Value);
                g.Pulses = readPulses(c.Pulses.Data);
        end
        g.AOffset = numbers(c.AOffset, 'A offset', 0);
        g.BOffset = numbers(c.BOffset, 'B offset', 0);
        g.OffsetMode = c.OffsetMode.Value;
        generator = g;

        candidate = S;
        candidate.Stimulus.Generator = g;
        candidate.Stimulus.Duration = c.Window.Value;
        candidate.Task.GroupPLeft = pLeftTyped;
    end

    function [stimulusSet, candidate] = compile(candidate)
        % The set with the family's contingency, then the typed one if it still applies.
        familyOwn = candidate;
        familyOwn.Task.GroupPLeft = [];
        budget = lum.timerBudget(candidate, rig);
        stimulusSet = lum.pattern.stimulusSet(familyOwn, budget, rig.Opto.nChannels);
        [pLeftTyped, pLeftFor] = lum.pattern.typedPLeft(pLeftTyped, pLeftFor, ...
                                                        stimulusSet.GroupLabels);
        if ~isempty(pLeftTyped)
            stimulusSet = lum.pattern.applyContingency(stimulusSet, pLeftTyped, ...
                                                       stimulusSet.Reversed);
        end
        candidate.Task.GroupPLeft = pLeftTyped;
    end

    function candidate = collect()
        % The settings as the window shows them, P(left) resolved against the groups.
        candidate = readControls();
        try
            [~, candidate] = compile(candidate);
        catch
            % Not compilable yet: the status line says why; P(left) is as typed.
        end
    end

    function refresh()
        family = families(strcmp({families.Name}, controls.Family.Value));
        names = fieldnames(controls.FamilyPanels);
        for i = 1:numel(names)
            controls.FamilyPanels.(names{i}).Visible = onOff(strcmp(names{i}, family.Name));
        end
        if isempty(family.Question)
            controls.Question.Text = '';
        else
            controls.Question.Text = sprintf('The animal tells: %s', family.Question);
        end
        controls.FamilyNote.Text = family.Description;
        updateFamilyControls();
        try
            candidate = readControls();
            budget = lum.timerBudget(candidate, rig);
            stimulusSet = compile(candidate);
        catch designError
            setStatus(designError.message, false);
            return
        end
        showSet(stimulusSet);
        message = sprintf(['%d group(s) over %d trials; the busiest pattern uses %d of the %d '...
                           'global timers left for light.'], stimulusSet.nGroups, ...
                          stimulusSet.nTrials, max([0 stimulusSet.nTimers]), budget);
        typedBin = candidate.Stimulus.Generator.BinDuration;
        if abs(stimulusSet.BinDuration - typedBin) > 1e-9 * typedBin
            message = sprintf('%s Bins are %.4g ms, so that the window holds %d whole bins.', ...
                              message, 1000 * stimulusSet.BinDuration, stimulusSet.nBins);
        end
        setStatus(message, true);
    end

    function updateFamilyControls()
        % Settings that only apply to one rule or design, and the notes that follow them.
        c = controls;
        rule = c.MixtureRule.Value;
        kind = rule;
        if ismember(rule, {'A alone', 'B alone'})
            kind = 'alone';
        end
        for name = fieldnames(c.MixtureRulePanels)'
            c.MixtureRulePanels.(name{1}).Visible = onOff(strcmp(name{1}, kind));
        end
        switch kind
            case 'share'
                c.MixtureNote.Text = ['Each group is a mixture ratio at one total of light: more A '...
                    'than the boundary ratio pays left. The totals rove, so each amount pays left in '...
                    'one group and right in another: only A against B tells the side.'];
            case 'difference'
                c.MixtureNote.Text = ['Each group is a difference, A minus B, at one total of '...
                    'light: above the boundary pays left. The totals rove, so each amount pays left '...
                    'in one group and right in another. The ratio of the amounts changes with the '...
                    'total here; with A share it does not.'];
            otherwise
                c.MixtureNote.Text = ['Every level of each channel with every level of the other. '...
                    'The deciding channel''s lower levels pay one side and its upper levels the '...
                    'other; the other channel tells nothing.'];
        end
        c.MixtureCycles.Enable = onOff(strcmp(c.MixtureLayout.Value, 'spread'));
        if c.MixtureContinuous.Value
            c.MixtureNote.Text = [c.MixtureNote.Text ' Every trial draws its amounts afresh, '...
                'on the side of the boundary its group needs.'];
        end
        guarded = strcmp(c.OrderDesign.Value, 'guarded');
        c.OrderOverlap.Enable = onOff(~guarded);
        c.OrderShortOverlap.Enable = onOff(guarded);
        c.OrderLongOverlap.Enable = onOff(guarded);
        c.OrderContinuous.Enable = onOff(guarded);
        if guarded
            c.OrderNote.Text = ['Each turn: the leading channel alone, a short overlap, the other '...
                'alone, a long overlap. With a random phase each channel alone is a stretch of '...
                'light at a random place, so only the timing between the two tells the side.'];
        else
            c.OrderNote.Text = ['Each turn: the first channel alone, both together for the '...
                'overlap, then the second alone. A first pays left, B first right.'];
        end
    end

    function showGenerator(g)
        % Put every family's settings into its controls.
        c = controls;
        c.Family.Value = choice(g.Family, c.Family.ItemsData);
        c.PureChannels.Value = pureChannelsValue(g.PureChannels);
        c.PureFractions.Value = listText(g.PureFractions);
        c.MixtureRule.Value = choice(regexprep(char(g.MixtureRule), '^compare$', 'share'), ...
                                     c.MixtureRule.ItemsData);
        c.MixtureRatios.Value = pairsToText(g.MixtureRatios);
        c.MixtureShareBoundary.Value = pairsToText(g.MixtureShareBoundary);
        c.MixtureShareTotals.Value = listText(g.MixtureShareTotals);
        c.MixtureDifferences.Value = listText(g.MixtureDifferences);
        c.MixtureDifferenceBoundary.Value = g.MixtureDifferenceBoundary;
        c.MixtureDifferenceTotals.Value = listText(g.MixtureDifferenceTotals);
        c.MixtureLevels.Value = listText(g.MixtureLevels);
        c.MixtureLayout.Value = choice(regexprep(char(g.MixtureLayout), 'centered', 'centred'), ...
                                       c.MixtureLayout.ItemsData);
        c.MixtureCycles.Value = g.MixtureCycles;
        c.CountSlots.Value = g.CountSlots;
        c.CountPairs.Value = pairsToText(g.CountPairs);
        c.CountFill.Value = g.CountFill;
        c.OrderDesign.Value = choice(g.OrderDesign, c.OrderDesign.ItemsData);
        c.OrderCycles.Value = g.OrderCycles;
        c.OrderOverlap.Value = g.OrderOverlap;
        c.OrderShortOverlap.Value = g.OrderShortOverlap;
        c.OrderLongOverlap.Value = g.OrderLongOverlap;
        c.MotifLeftWords.Value = char(g.MotifLeftWords);
        c.MotifRightWords.Value = char(g.MotifRightWords);
        c.MotifFill.Value = g.MotifFill;
        c.nGroups.Value = g.nGroups;
        c.Pulses.Data = pulsesToCells(g.Pulses);
        continuous = isequal(logical(g.Continuous), true);
        c.MixtureContinuous.Value = continuous && strcmp(g.Family, 'mixture');
        c.CountContinuous.Value = continuous || ~strcmp(g.Family, 'count');
        c.OrderContinuous.Value = continuous && strcmp(g.Family, 'order');
    end

    function chooseFamily(name)
        % Load a family's defaults, sized to this machine's timers and the window.
        try
            candidate = readControls();
            budget = lum.timerBudget(candidate, rig);
            window = candidate.Stimulus.Duration;
        catch
            budget = lum.timerBudget(S, rig);
            window = controls.Window.Value;
        end
        generator = lum.pattern.familyDefaults(generator, name, budget, window);
        showGenerator(generator);
        pLeftTyped = [];
        pLeftFor = {};
        refresh();
    end

    function orderDesignChosen()
        % The guarded cycle is meant to run with a random phase, the simple one without.
        controls.OrderContinuous.Value = strcmp(controls.OrderDesign.Value, 'guarded');
        refresh();
    end

    function fillCounts(kind)
        % Counts for every slot lit, or counts one apart with the total roving.
        slots = round(controls.CountSlots.Value);
        if strcmp(kind, 'full')
            pairs = [(slots:-1:0)', (0:slots)'];
        else
            pairs = zeros(0, 2);
            for k = 0:floor((slots - 1) / 2)
                pairs(end+1:end+2, :) = [k + 1, k; k, k + 1];
            end
        end
        controls.CountPairs.Value = pairsToText(pairs);
        refresh();
    end

    function showSet(stimulusSet)
        shownSet = stimulusSet;
        nGroups = stimulusSet.nGroups;
        groupOfTrial = stimulusSet.PatternGroup(stimulusSet.TrialPattern);
        data = cell(nGroups, 5);
        for g = 1:nGroups
            members = stimulusSet.PatternGroup == g;
            % BasePLeft: the cell is read back as typed, and a reversal (Task tab) is
            % applied on top of it, so showing reversed values would reverse them twice.
            data(g, :) = {g, stimulusSet.GroupLabels{g}, sum(groupOfTrial == g), ...
                          max([0 stimulusSet.nTimers(members)]), stimulusSet.BasePLeft(g)};
        end
        if ~isequal(controls.GroupTable.Data, data)
            controls.GroupTable.Data = data;
        end
        if stimulusSet.PLeftFromFamily
            source = 'P(left) is the family''s: type in the table to change it.';
        else
            source = 'P(left) as typed, kept while the groups stay the same.';
        end
        if stimulusSet.Reversed
            source = sprintf('%s The contingency is reversed (Task tab): each group pays the other side.', ...
                             source);
        end
        controls.PLeftNote.Text = source;
        controls.FamilyPLeft.Enable = onOff(~stimulusSet.PLeftFromFamily);
        controls.Shortcuts.Text = lum.pattern.describeShortcuts(stimulusSet.Shortcuts);
        controls.Browser.show(stimulusSet);
    end

    function current = currentSet()
        % The stimulus set as last compiled and shown.
        current = shownSet;
    end

    function onTableEdit()
        % P(left) typed in the table, for the groups the table shows.
        editPLeft(readPLeft(controls.GroupTable.Data));
    end

    function editPLeft(values)
        pLeftTyped = values;
        pLeftFor = controls.GroupTable.Data(:, 2)';
        refresh();
    end

    function useFamilyPLeft()
        pLeftTyped = [];
        pLeftFor = {};
        refresh();
    end

    function [ok, candidate] = apply()
        ok = false;
        candidate = S;
        try
            candidate = readControls();
            [~, candidate] = compile(candidate);
        catch designError
            setStatus(designError.message, false);
            uialert(fig, designError.message, 'Stimuli not usable');
            return
        end
        S = candidate;
        accepted = true;
        ok = true;
        delete(fig);
    end

    function onCancel()
        accepted = false;
        if isvalid(fig)
            delete(fig);
        end
    end

    function newSeed()
        controls.Seed.Value = lum.pattern.newSeed();
        refresh();
    end

    function addPulse()
        window = controls.Window.Value;
        controls.Pulses.Data = [controls.Pulses.Data; {1, 'A', 0, window / 2}];
        refresh();
    end

    function removePulse()
        if ~isempty(controls.Pulses.Data)
            controls.Pulses.Data(end, :) = [];
        end
        refresh();
    end

    function setStatus(message, isGood)
        controls.Status.Text = message;
        if isGood
            controls.Status.FontColor = t.Good;
        else
            controls.Status.FontColor = t.Bad;
        end
        controls.Apply.Enable = onOff(isGood);
    end
end


%% Pieces -----------------------------------------------------------------------

function values = numbers(field, what, default)
% A number list typed into a text field, or the default when the field is blank.
values = lum.gui.parseNumbers(field.Value, what);
if isempty(values)
    values = default;
end
end


function pairs = textToPairs(text, what)
% Pairs typed as A:B, e.g. '3:2 2:3' or '80:20 60:40', as rows of [A B].
tokens = strsplit(strtrim(char(text)), {' ', ',', ';', sprintf('\t')});
tokens = tokens(~cellfun(@isempty, tokens));
pairs = zeros(numel(tokens), 2);
for i = 1:numel(tokens)
    parts = str2double(strsplit(tokens{i}, ':'));
    if numel(parts) ~= 2 || any(isnan(parts))
        error('lum:gui:StimulusDesigner:badPairs', ...
              '%s are written A:B, e.g. 3:2 2:3; "%s" is not.', what, tokens{i});
    end
    pairs(i, :) = parts;
end
end


function text = pairsToText(pairs)
% Rows of [A B] as '3:2 2:3'.
text = strjoin(compose('%g:%g', pairs(:, 1), pairs(:, 2))', ' ');
end


function text = listText(values)
% A number list as the text fields show it; NaN shows as blank.
values = values(~isnan(values));
text = strjoin(compose('%g', values), ' ');
end


function value = choice(value, items)
% A stored choice as its dropdown item, matched regardless of case; the first item when
% the value is not one of them.
match = find(strcmpi(strtrim(char(value)), items), 1);
if isempty(match)
    match = 1;
end
value = items{match};
end


function value = pureChannelsValue(value)
% A stored channel choice as the dropdown's item.
switch lower(strtrim(char(value)))
    case 'a'
        value = 'A';
    case 'b'
        value = 'B';
    otherwise
        value = 'A and B';
end
end


function pLeft = readPLeft(data)
% P(left) per group, from the group table's last column.
if isempty(data)
    pLeft = [];
    return
end
pLeft = cellfun(@double, data(:, 5))';
end


function pulses = readPulses(data)
% The pulses table as rows of [group, channel, start, end].
pulses = zeros(size(data, 1), 4);
for row = 1:size(data, 1)
    pulses(row, :) = [double(data{row, 1}), 1 + strcmp(data{row, 2}, 'B'), ...
                      double(data{row, 3}), double(data{row, 4})];
end
end


function data = pulsesToCells(pulses)
% Pulse rows as table cells, with channels named A and B.
names = {'A', 'B'};
data = cell(size(pulses, 1), 4);
for row = 1:size(pulses, 1)
    data(row, :) = {pulses(row, 1), names{min(max(pulses(row, 2), 1), 2)}, ...
                    pulses(row, 3), pulses(row, 4)};
end
end


function [grid, panel] = familyForm(hostGrid, nRows, t)
% One family's settings: a borderless panel stacked in the shared cell of the host,
% shown only while its family is chosen. The last row is for a note.
panel = uipanel(hostGrid, 'BorderType', 'none', 'BackgroundColor', t.Panel);
panel.Layout.Row = 1;
panel.Layout.Column = 1;
grid = uigridlayout(panel, [nRows + 1 2], 'ColumnWidth', {170, '1x'}, ...
                    'RowHeight', [repmat({26}, 1, nRows), {'1x'}], 'Padding', [10 8 10 8], ...
                    'RowSpacing', 6, 'ColumnSpacing', 10, 'BackgroundColor', t.Panel);
end


function [grid, panel] = ruleRows(form, firstRow, nRows, t)
% Rows of a family's form that belong to one kind of rule: a borderless panel over those
% rows of the form, stacked with the other kinds' and shown only while its kind is chosen.
panel = uipanel(form, 'BorderType', 'none', 'BackgroundColor', t.Panel);
panel.Layout.Row = [firstRow, firstRow + nRows - 1];
panel.Layout.Column = [1 2];
grid = uigridlayout(panel, [nRows 2], 'ColumnWidth', {170, '1x'}, ...
                    'RowHeight', repmat({26}, 1, nRows), 'Padding', 0, 'RowSpacing', 6, ...
                    'ColumnSpacing', 10, 'BackgroundColor', t.Panel);
end


function component = placed(component, row, column)
% A component put in a given cell of its grid.
component.Layout.Row = row;
component.Layout.Column = column;
end


function note = familyNote(grid, text, t)
% A muted note across both columns of a family's form, in its last row.
note = uilabel(grid, 'Text', text, 'WordWrap', 'on', 'FontColor', t.Muted, 'FontSize', 11, ...
               'VerticalAlignment', 'top');
note.Layout.Row = numel(grid.RowHeight);
note.Layout.Column = [1 2];
end


function grid = formPanel(parent, title, nRows, t)
% A titled panel holding a label/field form of nRows rows.
panel = uipanel(parent, 'Title', title, 'FontWeight', 'bold', 'BackgroundColor', t.Panel, ...
                'ForegroundColor', t.Accent);
grid = uigridlayout(panel, [nRows 2], 'ColumnWidth', {170, '1x'}, ...
                    'RowHeight', repmat({26}, 1, nRows), 'Padding', [10 8 10 8], ...
                    'RowSpacing', 6, 'ColumnSpacing', 10, 'BackgroundColor', t.Panel);
end


function field = numberField(parent, value, limits, positive, onEdit)
% A numeric field that refreshes the design when it changes.
field = uieditfield(parent, 'numeric', 'Value', value, 'Limits', limits, ...
                    'ValueChangedFcn', @(~, ~) onEdit());
if positive
    field.LowerLimitInclusive = 'on';
end
end


function field = textField(parent, values, onEdit)
% A text field holding a number list; NaN shows as blank.
field = uieditfield(parent, 'text', 'Value', listText(values), ...
                    'ValueChangedFcn', @(~, ~) onEdit());
end


function handle = label(parent, text, t)
handle = uilabel(parent, 'Text', text, 'FontColor', t.Ink);
end


function height = panelHeight(nRows)
height = 44 + nRows * 32;
end


function state = onOff(tf)
state = matlab.lang.OnOffSwitchState(tf);
end
