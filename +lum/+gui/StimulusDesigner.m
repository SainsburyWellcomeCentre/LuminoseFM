function [S, accepted, app] = StimulusDesigner(S, rig, varargin)
% lum.gui.StimulusDesigner designs a session's light patterns and trial order.
%
% The generator (lum.pattern.generate) makes a whole session at once: a family of
% two-channel patterns, the groups of the session, and a balanced, shuffled order of
% trials. This window puts every one of its parameters in front of the operator,
% recompiles on each edit, and shows the result the way the session will run it: a
% table of groups, with how many trials each gets, how many global timers its busiest
% pattern costs and the chance it pays the left port, and a browser to scroll through
% every trial.
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
%             .status() and .controls
%
% See also: lum.pattern.generate, lum.pattern.stimulusSet, lum.gui.SetupDialog,
%           lum.gui.PatternBrowser

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
baseline = lum.pattern.withGeneratorDefaults(S.Stimulus.Generator);

fig = uifigure('Name', 'LuminoseFM - stimulus designer', 'Position', [70 50 1300 840], ...
               'Color', t.Background, 'Visible', p.Results.Visible);
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

main = uigridlayout(outer, [1 2], 'ColumnWidth', {420, '1x'}, 'Padding', 0, ...
                    'ColumnSpacing', 12, 'BackgroundColor', t.Background);
left = uigridlayout(main, [5 1], 'RowHeight', {panelHeight(6), 112, 250, panelHeight(3), '1x'}, ...
                    'Padding', 0, 'RowSpacing', 10, 'BackgroundColor', t.Background, ...
                    'Scrollable', 'on');
controls = struct();

form = formPanel(left, 'Window and groups', 6, t);
label(form, 'Stimulus window (s)', t);
controls.Window = numberField(form, S.Stimulus.Duration, [0.001 60], true, @refresh);
label(form, 'Bin (s)', t);
controls.Bin = numberField(form, baseline.BinDuration, [0.0001 10], false, @refresh);
label(form, 'Groups', t);
controls.nGroups = numberField(form, baseline.nGroups, [1 64], false, @refresh);
controls.nGroups.RoundFractionalValues = 'on';
label(form, 'Continuous', t);
controls.Continuous = uicheckbox(form, 'Text', 'a new pattern for every trial', ...
    'Value', baseline.Continuous, 'ValueChangedFcn', @(~, ~) refresh());
label(form, 'Seed', t);
seedRow = uigridlayout(form, [1 2], 'ColumnWidth', {'1x', 60}, 'Padding', 0, ...
                       'ColumnSpacing', 6, 'BackgroundColor', t.Panel);
controls.Seed = numberField(seedRow, baseline.Seed, [0 2^32 - 1], false, @refresh);
controls.Seed.RoundFractionalValues = 'on';
uibutton(seedRow, 'Text', 'New', 'Tooltip', 'Same patterns, a new shuffle', ...
         'ButtonPushedFcn', @(~, ~) newSeed());
label(form, 'Each session', t);
controls.NewSeedEachSession = uicheckbox(form, 'Text', 'draws a new seed', ...
    'Value', baseline.NewSeedEachSession, 'ValueChangedFcn', @(~, ~) refresh());

panel = uipanel(left, 'Title', 'Family', 'FontWeight', 'bold', 'BackgroundColor', t.Panel, ...
                'ForegroundColor', t.Accent);
familyGrid = uigridlayout(panel, [2 1], 'RowHeight', {26, '1x'}, 'Padding', [10 8 10 8], ...
                          'RowSpacing', 6, 'BackgroundColor', t.Panel);
controls.Family = uidropdown(familyGrid, 'Items', {families.Label}, 'ItemsData', {families.Name}, ...
                             'Value', baseline.Family, 'ValueChangedFcn', @(~, ~) refresh());
controls.FamilyNote = uilabel(familyGrid, 'Text', '', 'WordWrap', 'on', 'FontColor', t.Muted, ...
                              'FontSize', 11, 'VerticalAlignment', 'top');

host = uipanel(left, 'Title', 'Family parameters', 'FontWeight', 'bold', ...
               'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
hostGrid = uigridlayout(host, [1 1], 'Padding', 0, 'BackgroundColor', t.Panel);
controls.FamilyPanels = struct();

[form, controls.FamilyPanels.pure] = familyForm(hostGrid, 2, t);
label(form, 'Channel (one group)', t);
controls.PureChannel = uidropdown(form, 'Items', {'A', 'B'}, 'Value', baseline.PureChannel, ...
                                  'ValueChangedFcn', @(~, ~) refresh());
label(form, 'Lit fraction(s)', t);
controls.OnFraction = textField(form, baseline.OnFraction, @refresh);

[form, controls.FamilyPanels.sequence] = familyForm(hostGrid, 6, t);
label(form, 'Motif (joint states)', t);
controls.Motif = textField(form, baseline.Motif, @refresh);
label(form, 'Duty cycle, A', t);
controls.DutyA = numberField(form, baseline.DutyCycle(1), [0.01 1], false, @refresh);
label(form, 'Duty cycle, B', t);
controls.DutyB = numberField(form, baseline.DutyCycle(end), [0.01 1], false, @refresh);
label(form, 'Cycles in the window', t);
controls.NumCycles = numberField(form, baseline.NumCycles, [1 1000], false, @refresh);
controls.NumCycles.RoundFractionalValues = 'on';
label(form, 'Slot weights', t);
controls.SlotWeights = textField(form, baseline.SlotWeights, @refresh);
label(form, 'B phase per group (deg)', t);
controls.BPhase = textField(form, baseline.BPhase, @refresh);

[form, controls.FamilyPanels.occupancy] = familyForm(hostGrid, 6, t);
label(form, 'A lit fraction', t);
controls.AOnFraction = numberField(form, baseline.AOnFraction, [0 1], false, @refresh);
label(form, 'B lit fraction', t);
controls.BOnFraction = numberField(form, baseline.BOnFraction, [0 1], false, @refresh);
label(form, 'Overlap fraction', t);
controls.Overlap = numberField(form, baseline.Overlap, [0 1], false, @refresh);
label(form, 'Beta (blank: fractions)', t);
controls.Beta = textField(form, baseline.Beta, @refresh);
label(form, 'Layout', t);
controls.Layout = uidropdown(form, 'Items', {'blocks', 'shuffle'}, 'Value', baseline.Layout, ...
                             'ValueChangedFcn', @(~, ~) refresh());
label(form, 'Block order', t);
controls.BlockOrder = textField(form, baseline.BlockOrder, @refresh);

[form, controls.FamilyPanels.overlap_order] = familyForm(hostGrid, 4, t);
label(form, 'Bins per cycle', t);
controls.CycleBins = numberField(form, baseline.CycleBins, [4 10000], false, @refresh);
controls.CycleBins.RoundFractionalValues = 'on';
label(form, 'Pure block (bins)', t);
controls.PureWidth = numberField(form, baseline.PureWidth, [1 10000], false, @refresh);
controls.PureWidth.RoundFractionalValues = 'on';
label(form, 'Short guard (bins)', t);
controls.ShortGuard = numberField(form, baseline.ShortGuard, [1 10000], false, @refresh);
controls.ShortGuard.RoundFractionalValues = 'on';
label(form, 'Phase (bins; blank: random)', t);
controls.Phase = textField(form, baseline.Phase, @refresh);

[form, controls.FamilyPanels.tiled_order] = familyForm(hostGrid, 1, t);
form.RowHeight = {'1x'};
form.ColumnWidth = {'1x'};
uilabel(form, 'Text', ['No parameters: A and B alternate bin by bin. Use one group, or two to '...
                       'have the B-first form as well. The bin sets how fast they alternate.'], ...
        'WordWrap', 'on', 'FontColor', t.Muted, 'VerticalAlignment', 'top');

pulsesPanel = uipanel(hostGrid, 'BorderType', 'none', 'BackgroundColor', t.Panel);
pulsesPanel.Layout.Row = 1;
pulsesPanel.Layout.Column = 1;
controls.FamilyPanels.arbitrary = pulsesPanel;
pulsesGrid = uigridlayout(pulsesPanel, [2 1], 'RowHeight', {'1x', 28}, 'Padding', [10 8 10 8], ...
                          'RowSpacing', 6, 'BackgroundColor', t.Panel);
controls.Pulses = uitable(pulsesGrid, 'Data', pulsesToCells(baseline.Pulses), ...
    'ColumnName', {'Group', 'Channel', 'Start (s)', 'End (s)'}, ...
    'ColumnEditable', true(1, 4), 'ColumnFormat', {'numeric', {'A', 'B'}, 'numeric', 'numeric'}, ...
    'CellEditCallback', @(~, ~) refresh());
pulseButtons = uigridlayout(pulsesGrid, [1 2], 'Padding', 0, 'ColumnSpacing', 8, ...
                            'BackgroundColor', t.Panel);
uibutton(pulseButtons, 'Text', 'Add pulse', 'ButtonPushedFcn', @(~, ~) addPulse());
uibutton(pulseButtons, 'Text', 'Remove last', 'ButtonPushedFcn', @(~, ~) removePulse());

form = formPanel(left, 'Channel offsets', 3, t);
label(form, 'A offset (s)', t);
controls.AOffset = textField(form, baseline.AOffset, @refresh);
label(form, 'B offset (s)', t);
controls.BOffset = textField(form, baseline.BOffset, @refresh);
label(form, 'Offset mode', t);
controls.OffsetMode = uidropdown(form, 'Items', {'circular', 'linear'}, ...
                                 'Value', baseline.OffsetMode, 'ValueChangedFcn', @(~, ~) refresh());

uilabel(left, 'Text', ['Lists take one value, or one per group: "0 0.05 0.1". An offset '...
                       'delays a channel''s light; circular wraps it round the window, linear '...
                       'lets it run off the end. Joint states: 0 dark, 1 A only, 2 B only, '...
                       '3 A and B.'], 'WordWrap', 'on', 'FontColor', t.Muted, 'FontSize', 11, ...
        'VerticalAlignment', 'top');

right = uigridlayout(main, [2 1], 'RowHeight', {250, '1x'}, 'Padding', 0, 'RowSpacing', 10, ...
                     'BackgroundColor', t.Background);
panel = uipanel(right, 'Title', 'Groups and contingency', 'FontWeight', 'bold', ...
                'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
groupGrid = uigridlayout(panel, [2 1], 'RowHeight', {'1x', 'fit'}, 'Padding', [10 8 10 8], ...
                         'RowSpacing', 6, 'BackgroundColor', t.Panel);
controls.GroupTable = uitable(groupGrid, 'ColumnName', {'Group', 'Label', 'Trials', 'Timers', 'P(left)'}, ...
    'ColumnEditable', [false false false false true], 'ColumnWidth', {50, 'auto', 60, 60, 70}, ...
    'Data', placeholderRows(S.Task.GroupPLeft), 'CellEditCallback', @(~, ~) refresh());
uilabel(groupGrid, 'Text', ['P(left) is the chance that the left port pays on that group''s '...
                            'trials: 1 or 0 for a fixed contingency, in between for a '...
                            'psychometric one. In continuous mode the two rows are the A-led '...
                            'and B-led patterns. Timers is what the busiest pattern of the group '...
                            'costs; every stretch of light on a channel takes one.'], ...
        'WordWrap', 'on', 'FontColor', t.Muted, 'FontSize', 11);

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

fig.WindowKeyPressFcn = @(~, event) controls.Browser.onKey(event);
refresh();
app = struct('Figure', fig, 'collect', @collect, 'refresh', @refresh, 'apply', @apply, ...
             'cancel', @onCancel, 'status', @() controls.Status.Text, 'controls', controls);
if p.Results.Wait
    uiwait(fig);
end


    function candidate = collect()
        % The settings as the window shows them.
        c = controls;
        g = baseline;
        g.Family = c.Family.Value;
        g.nGroups = round(c.nGroups.Value);
        g.Continuous = c.Continuous.Value;
        g.BinDuration = c.Bin.Value;
        g.Seed = round(c.Seed.Value);
        g.NewSeedEachSession = c.NewSeedEachSession.Value;
        g.PureChannel = c.PureChannel.Value;
        g.OnFraction = numbers(c.OnFraction, 'Lit fraction', 1);
        g.Motif = numbers(c.Motif, 'Motif', []);
        g.DutyCycle = [c.DutyA.Value, c.DutyB.Value];
        g.NumCycles = round(c.NumCycles.Value);
        g.SlotWeights = numbers(c.SlotWeights, 'Slot weights', []);
        g.BPhase = numbers(c.BPhase, 'B phase', []);
        g.AOnFraction = c.AOnFraction.Value;
        g.BOnFraction = c.BOnFraction.Value;
        g.Overlap = c.Overlap.Value;
        g.Beta = numbers(c.Beta, 'Beta', NaN);
        g.Layout = c.Layout.Value;
        g.BlockOrder = numbers(c.BlockOrder, 'Block order', [1 3 2 0]);
        g.CycleBins = round(c.CycleBins.Value);
        g.PureWidth = round(c.PureWidth.Value);
        g.ShortGuard = round(c.ShortGuard.Value);
        phase = numbers(c.Phase, 'Phase', NaN);
        g.Phase = phase(1);
        g.Pulses = readPulses(c.Pulses.Data);
        g.AOffset = numbers(c.AOffset, 'A offset', 0);
        g.BOffset = numbers(c.BOffset, 'B offset', 0);
        g.OffsetMode = c.OffsetMode.Value;

        candidate = S;
        candidate.Stimulus.Generator = g;
        candidate.Stimulus.Duration = c.Window.Value;
        nGroups = g.nGroups;
        if g.Continuous
            nGroups = 2;
        end
        candidate.Task.GroupPLeft = lum.pattern.defaultPLeft(nGroups, readPLeft(c.GroupTable.Data));
    end

    function refresh()
        family = families(strcmp({families.Name}, controls.Family.Value));
        names = fieldnames(controls.FamilyPanels);
        for i = 1:numel(names)
            controls.FamilyPanels.(names{i}).Visible = onOff(strcmp(names{i}, family.Name));
        end
        controls.FamilyNote.Text = family.Description;
        controls.nGroups.Enable = onOff(~controls.Continuous.Value);
        try
            candidate = collect();
            budget = lum.timerBudget(candidate, rig);
            stimulusSet = lum.pattern.stimulusSet(candidate, budget, rig.Opto.nChannels);
        catch designError
            setStatus(designError.message, false);
            return
        end
        showSet(stimulusSet);
        setStatus(sprintf(['%d group(s) over %d trials; the busiest pattern uses %d of the %d '...
                           'global timers left for light.'], stimulusSet.nGroups, ...
                          stimulusSet.nTrials, max([0 stimulusSet.nTimers]), budget), true);
    end

    function showSet(stimulusSet)
        nGroups = stimulusSet.nGroups;
        groupOfTrial = stimulusSet.PatternGroup(stimulusSet.TrialPattern);
        data = cell(nGroups, 5);
        for g = 1:nGroups
            members = stimulusSet.PatternGroup == g;
            data(g, :) = {g, stimulusSet.GroupLabels{g}, sum(groupOfTrial == g), ...
                          max([0 stimulusSet.nTimers(members)]), stimulusSet.GroupPLeft(g)};
        end
        if ~isequal(controls.GroupTable.Data, data)
            controls.GroupTable.Data = data;
        end
        controls.Browser.show(stimulusSet);
    end

    function [ok, candidate] = apply()
        ok = false;
        candidate = S;
        try
            candidate = collect();
            budget = lum.timerBudget(candidate, rig);
            lum.pattern.stimulusSet(candidate, budget, rig.Opto.nChannels);
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


function data = placeholderRows(pLeft)
% Group rows before the first compile.
data = cell(numel(pLeft), 5);
for g = 1:numel(pLeft)
    data(g, :) = {g, sprintf('Group %d', g), [], [], pLeft(g)};
end
end


function [grid, panel] = familyForm(hostGrid, nRows, t)
% One family's parameters: a borderless panel stacked in the shared cell of the host,
% shown only while its family is chosen.
panel = uipanel(hostGrid, 'BorderType', 'none', 'BackgroundColor', t.Panel);
panel.Layout.Row = 1;
panel.Layout.Column = 1;
grid = uigridlayout(panel, [nRows 2], 'ColumnWidth', {180, '1x'}, ...
                    'RowHeight', repmat({26}, 1, nRows), 'Padding', [10 8 10 8], ...
                    'RowSpacing', 6, 'ColumnSpacing', 10, 'BackgroundColor', t.Panel);
end


function grid = formPanel(parent, title, nRows, t)
% A titled panel holding a label/field form of nRows rows.
panel = uipanel(parent, 'Title', title, 'FontWeight', 'bold', 'BackgroundColor', t.Panel, ...
                'ForegroundColor', t.Accent);
grid = uigridlayout(panel, [nRows 2], 'ColumnWidth', {180, '1x'}, ...
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
values = values(~isnan(values));
field = uieditfield(parent, 'text', 'Value', strjoin(compose('%g', values), ' '), ...
                    'ValueChangedFcn', @(~, ~) onEdit());
end


function label(parent, text, t)
uilabel(parent, 'Text', text, 'FontColor', t.Ink);
end


function height = panelHeight(nRows)
height = 44 + nRows * 32;
end


function state = onOff(tf)
state = matlab.lang.OnOffSwitchState(tf);
end
