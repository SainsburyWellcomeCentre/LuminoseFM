function tests = windowsTest
% windowsTest exercises the protocol's windows without showing them.
%
% The runtime window is what the trial loop syncs every trial, and the online plots
% are updated every trial, so both are tested for what they do rather than how they
% look: values going both ways, limits held, axes that keep the data on screen, a
% psychometric panel laid out for the stimulus set, panels where the operator reads
% them. The setup dialogs, the session type chooser and the stimulus designer are
% tested for reading back exactly what they were given; they need uifigure support,
% and are skipped where MATLAB cannot create one.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
ensureEmulator();
S = lum.defaultSettings;
S.Session.MaxTrials = 200;
testCase.TestData.S = S;
testCase.TestData.rig = RigConfig;
end

%% Runtime window ------------------------------------------------------------------

function testTheTabbedWindowHasATabPerRuntimeTab(testCase)
S = testCase.TestData.S;
window = lum.gui.RuntimeWindow(S, 'Mode', 'Tabbed', 'Visible', 'off');
cleanup = onCleanup(@() window.close());
tabs = findobj(window.Figure, 'Type', 'uitab');
verifyEqual(testCase, sort({tabs.Title}), sort(fieldnames(S.GUITabs))');
verifyNotEmpty(testCase, findobj(window.Figure, 'Style', 'text', 'String', 'Reward amount (uL)'), ...
               'Controls must carry their readable labels');
verifyNotEmpty(testCase, findobj(window.Figure, 'Tag', 'HoldWindow'));
delete(cleanup);
end

function testSyncTakesWhatTheOperatorTyped(testCase)
S = testCase.TestData.S;
window = lum.gui.RuntimeWindow(S, 'Mode', 'Tabbed', 'Visible', 'off');
cleanup = onCleanup(@() window.close());
set(findobj(window.Figure, 'Tag', 'RewardAmount'), 'String', '7');
S = window.sync(S);
verifyEqual(testCase, S.GUI.RewardAmount, 7);
set(findobj(window.Figure, 'Tag', 'OptoOn'), 'Value', 0);
S = window.sync(S);
verifyEqual(testCase, S.GUI.OptoOn, 0);
delete(cleanup);
end

function testSyncShowsWhatTheProtocolChanged(testCase)
S = testCase.TestData.S;
window = lum.gui.RuntimeWindow(S, 'Mode', 'Tabbed', 'Visible', 'off');
cleanup = onCleanup(@() window.close());
S.GUI.ITI = 4;
S = window.sync(S);
verifyEqual(testCase, S.GUI.ITI, 4);
verifyEqual(testCase, get(findobj(window.Figure, 'Tag', 'ITI'), 'String'), '4');
delete(cleanup);
end

function testTypedValuesAreHeldToTheirLimits(testCase)
S = testCase.TestData.S;
window = lum.gui.RuntimeWindow(S, 'Mode', 'Tabbed', 'Visible', 'off');
cleanup = onCleanup(@() window.close());
field = findobj(window.Figure, 'Tag', 'RewardAmount');
set(field, 'String', '1000');
S = window.sync(S);
verifyEqual(testCase, S.GUI.RewardAmount, 100);
set(field, 'String', 'lots');
S = window.sync(S);
verifyEqual(testCase, S.GUI.RewardAmount, 100, 'Text that is not a number is ignored');
delete(cleanup);
end

function testAClosedWindowLeavesTheSettingsAlone(testCase)
S = testCase.TestData.S;
window = lum.gui.RuntimeWindow(S, 'Mode', 'Tabbed', 'Visible', 'off');
window.close();
verifyEqual(testCase, window.sync(S), S);
end

%% Online plots --------------------------------------------------------------------

function testOnlinePlotsKeepEveryTrialOnScreen(testCase)
[S, stimulusSet] = sessionFixture(testCase, 'pure', 2, false);
plots = lum.OnlinePlots(S, stimulusSet, 'Visible', 'off', 'nTrialsToShow', 40);
cleanup = onCleanup(@() plots.close());
feed(plots, S, stimulusSet, 150);
outcomes = axesTitled(plots.Figure, 'Outcomes');
verifyGreaterThanOrEqual(testCase, outcomes.XLim(2), 150);
verifyLessThanOrEqual(testCase, outcomes.XLim(1), 111);
reaction = axesTitled(plots.Figure, 'Reaction time');
verifyGreaterThan(testCase, reaction.YLim(2), 1.2, 'The slowest reaction on screen must fit');
performance = axesTitled(plots.Figure, 'Performance');
verifyGreaterThanOrEqual(testCase, performance.XLim(2), 150);
verifySubstring(testCase, plots.summaryText(), 'Trial 150');
delete(cleanup);
end

function testThePanelsAreInThreeRows(testCase)
% Top: now and next, then the outcomes. Middle: performance, psychometric, evidence.
% Bottom: by side, side bias, reaction time. No centre hold panel.
[S, stimulusSet] = sessionFixture(testCase, 'pure', 2, false);
plots = lum.OnlinePlots(S, stimulusSet, 'Visible', 'off');
cleanup = onCleanup(@() plots.close());
rows = {{'Now and next', 'Outcomes'}, ...
        {'Performance', 'Psychometric', 'Evidence'}, ...
        {'By side', 'Side bias', 'Reaction time'}};
heights = zeros(1, 3);
for r = 1:3
    panels = cellfun(@(title) axesTitled(plots.Figure, title), rows{r}, 'UniformOutput', false);
    for k = 1:numel(panels)
        verifyNotEmpty(testCase, panels{k}, sprintf('No panel titled "%s"', rows{r}{k}));
    end
    y = cellfun(@(ax) ax.Position(2), panels);
    x = cellfun(@(ax) ax.Position(1), panels);
    verifyEqual(testCase, y, repmat(y(1), size(y)), 'AbsTol', 0.02, sprintf('Row %d shares a row', r));
    verifyTrue(testCase, issorted(x) && numel(unique(x)) == numel(x), ...
               sprintf('Row %d reads left to right', r));
    heights(r) = y(1);
end
verifyTrue(testCase, heights(1) > heights(2) && heights(2) > heights(3), 'Rows from the top down');
verifyEmpty(testCase, axesTitled(plots.Figure, 'Centre hold'), 'The centre hold panel is gone');
verifyEmpty(testCase, axesTitled(plots.Figure, 'By side and light'), 'Light on and off are not compared');
delete(cleanup);
end

function testEveryChoiceLandsAtTheLightItsTrialDelivered(testCase)
[S, stimulusSet] = sessionFixture(testCase, 'pure', 2, false);
plots = lum.OnlinePlots(S, stimulusSet, 'Visible', 'off', 'RefreshEvery', 1);
cleanup = onCleanup(@() plots.close());
feed(plots, S, stimulusSet, 40);

plane = axesTitled(plots.Figure, 'Evidence');
markers = findobj(plane, 'Type', 'line', 'LineStyle', 'none');
verifyNumElements(testCase, markers, 4, 'Correct and incorrect, each by side chosen');
x = [markers.XData];
y = [markers.YData];
shown = ~isnan(x);
verifyEqual(testCase, nnz(shown), 20, 'Every choice, and only choices');
verifyTrue(testCase, all(x(shown) >= -0.05 & x(shown) <= 1.05 & y(shown) >= -0.05 & y(shown) <= 1.05));
verifyTrue(testCase, all(min(abs([x(shown); y(shown)]), [], 1) <= 0.03), ...
           'A pure-channel pattern lights one channel only, so every choice sits on an axis');

bias = axesTitled(plots.Figure, 'Side bias');
chose = findobj(bias, 'Type', 'line', 'LineWidth', 2);
values = chose.YData(~isnan(chose.YData));
verifyNotEmpty(testCase, values);
verifyTrue(testCase, all(values >= 0 & values <= 1));
verifyGreaterThanOrEqual(testCase, bias.XLim(2), 40);

bars = axesTitled(plots.Figure, 'By side');
verifyEqual(testCase, cellstr(bars.XTickLabel)', {'left-rewarded', 'right-rewarded'});
delete(cleanup);
end

function testTheUpcomingTrialsShowBeforeAnyTrialEnds(testCase)
[S, stimulusSet] = sessionFixture(testCase, 'pure', 2, false);
plots = lum.OnlinePlots(S, stimulusSet, 'Visible', 'off');
cleanup = onCleanup(@() plots.close());
[spec, queue] = lum.nextTrialSpec(S, stimulusSet, stimulusSet.TrialPattern, ...
                                  lum.newHistory(S.Session.MaxTrials), 1);
plots.showNext(spec, queue);
labels = findobj(axesTitled(plots.Figure, 'Now and next'), 'Type', 'text');
strings = arrayfun(@(h) strjoin(cellstr(h.String), ' '), labels, 'UniformOutput', false);
verifyTrue(testCase, any(contains(strings, 'running #1')), 'Trial 1 must be shown as it starts');
verifyTrue(testCase, any(contains(strings, 'queued #4')), 'And the three after it');
delete(cleanup);
end

function testThePsychometricPanelFollowsTheSweep(testCase)
[S, stimulusSet] = sessionFixture(testCase, 'occupancy', 5, false);
plots = lum.OnlinePlots(S, stimulusSet, 'Visible', 'off');
cleanup = onCleanup(@() plots.close());
psychometric = axesTitled(plots.Figure, 'Psychometric');
verifyEqual(testCase, psychometric.XLabel.String, 'B share, beta');
points = findobj(psychometric, 'Type', 'errorbar');
verifyEqual(testCase, points.XData, sort(stimulusSet.SweepValues), 'AbsTol', 1e-12);
feed(plots, S, stimulusSet, 20);
delete(cleanup);
end

function testThePsychometricPanelBinsContinuousPatterns(testCase)
[S, stimulusSet] = sessionFixture(testCase, 'overlap_order', 2, true);
plots = lum.OnlinePlots(S, stimulusSet, 'Visible', 'off');
cleanup = onCleanup(@() plots.close());
psychometric = axesTitled(plots.Figure, 'Psychometric');
verifyEqual(testCase, psychometric.XLabel.String, 'B share of the light');
points = findobj(psychometric, 'Type', 'errorbar');
verifyNumElements(testCase, points.XData, 8);
feed(plots, S, stimulusSet, 30);
delete(cleanup);
end

function testSleepPlotsShowThePulsesSent(testCase)
S = testCase.TestData.S;
S.Sleep.DurationMinutes = 2;
plots = lum.sleep.Plots(S, 'Visible', 'off');
cleanup = onCleanup(@() plots.close());
n = 100;
onsets = NaN(1, 200);
widths = NaN(1, 200);
onsets(1:n) = 5 + (0:n - 1);
widths(1:n) = 0.05;
plots.update(struct('Onset', onsets, 'Width', widths, 'n', n), [], 100, 100);
pulses = findobj(axesTitled(plots.Figure, 'Pulses sent'), 'Type', 'line');
verifyEqual(testCase, sum(~isnan(pulses.YData)), n);
verifyEqual(testCase, max(pulses.XData), (n - 1) / 60, 'AbsTol', 1e-9);
trace = findobj(axesTitled(plots.Figure, 'Lines'), 'Type', 'line');
verifyEqual(testCase, max(trace.YData), 1, 'The trace must show the line high');
verifyGreaterThanOrEqual(testCase, min(trace.XData), -30);
verifySubstring(testCase, plots.summaryText(n, 100), '100 pulse(s)');
verifyEmpty(testCase, axesTitled(plots.Figure, 'Test-pulse schedule'), 'No test pulses, no schedule');
delete(cleanup);
end

function testSleepPlotsShowTheTestPulsesSent(testCase)
S = testCase.TestData.S;
S.Sleep.TestPulses.Enabled = true;
S.Sleep.TestPulses.PlasticityTrains = true;
S.Sleep.TestPulses.Schedule = struct('Kind', {'Probe', 'Theta burst', 'Probe'}, ...
                                     'Channels', {'A and B', 'A', 'B'}, 'Minutes', {1, 0, 1});
plan = lum.sleep.testPulsePlan(S.Sleep.TestPulses);
plots = lum.sleep.Plots(S, 'Visible', 'off', 'Plan', plan);
cleanup = onCleanup(@() plots.close());

% Everything up to the end of the theta burst, sent on time.
cycle = plan.CyclePeriod;
upTo = plan.Steps(3).Start;
syncPulses = lum.sleep.syncPulseTimes(S.Sleep.Sync, plan.Duration);
sync = struct('Onset', syncPulses(:, 1)' * cycle, 'Width', syncPulses(:, 2)' * cycle, ...
              'n', find(syncPulses(:, 1) * cycle < upTo, 1, 'last'));
light = struct('Onset', plan.Segments(:, 1)' * cycle, ...
               'n', find(plan.Segments(:, 1) * cycle < upTo, 1, 'last'));
plots.update(sync, light, upTo, upTo);

sent = findobj(axesTitled(plots.Figure, 'Epochs sent'), 'Type', 'bar', 'BarWidth', 0.4);
verifyEqual(testCase, sent.YData, [30 5 0], 'Thirty probes, then five trains');
epoch = axesTitled(plots.Figure, 'Latest epoch');
verifySubstring(testCase, epoch.Title.String, 'Theta burst');
pulses = findobj(epoch, 'Type', 'patch', 'FaceColor', 'flat', 'FaceAlpha', 1);
vertices = pulses.Vertices;
verifyEqual(testCase, nnz(vertices(2:4:end, 1) > vertices(1:4:end, 1)), 40, ...
            'Ten bursts of four pulses');
lines = findobj(axesTitled(plots.Figure, 'Lines'), 'Type', 'line', 'Color', lum.gui.theme().ChannelA);
verifyEqual(testCase, max(lines.YData), 2.1, 'AbsTol', 1e-9, 'Channel A drawn high in its lane');
verifySubstring(testCase, plots.summaryText(sync.n, upTo), '35 of 65 epoch(s)');
delete(cleanup);
end

%% Setup dialogs, session type and stimulus designer --------------------------------

function testTheSetupDialogReadsBackWhatItWasGiven(testCase)
assumeUIFigures(testCase);
S = testCase.TestData.S;
[~, accepted, app] = lum.gui.SetupDialog(S, testCase.TestData.rig, 'Wait', false, ...
                                         'Visible', 'off');
cleanup = onCleanup(@() closeIfOpen(app.Figure));
verifyFalse(testCase, accepted);
candidate = app.collect();
for group = {'Meta', 'Session', 'Task', 'Cue', 'Stimulus', 'Left', 'Right', 'Light', 'Sound', ...
             'Sync', 'Sleep', 'GUI'}
    verifyEqual(testCase, candidate.(group{1}), S.(group{1}), group{1});
end
verifySubstring(testCase, app.status(), 'Ready to start');
[ok, started] = app.start();
verifyTrue(testCase, ok);
verifyEqual(testCase, started.GUI, S.GUI);
delete(cleanup);
end

function testAnyGenotypeCanBeTyped(testCase)
assumeUIFigures(testCase);
S = testCase.TestData.S;
[~, ~, app] = lum.gui.SetupDialog(S, testCase.TestData.rig, 'Wait', false, 'Visible', 'off');
cleanup = onCleanup(@() closeIfOpen(app.Figure));
verifyFalse(testCase, any(contains(app.controls.Genotype.Items, 'OMP')), ...
            'OMP-Cre lines are no longer offered');
verifyEqual(testCase, app.controls.Genotype.Editable, matlab.lang.OnOffSwitchState('on'));
app.controls.Genotype.Value = 'Tbx21-Cre x Ai32';
verifyEqual(testCase, app.collect().Meta.Genotype, 'Tbx21-Cre x Ai32');
delete(cleanup);
end

function testRecordingsAreNamedNotDescribed(testCase)
assumeUIFigures(testCase);
[~, ~, app] = lum.gui.SetupDialog(testCase.TestData.S, testCase.TestData.rig, 'Wait', false, ...
                                  'Visible', 'off');
cleanup = onCleanup(@() closeIfOpen(app.Figure));
verifyEqual(testCase, app.controls.NPEnabled.Text, 'Neuropixels recording');
verifyEqual(testCase, app.controls.EEGEnabled.Text, 'EEG/EMG recording');
verifyEqual(testCase, app.controls.DrugEnabled.Text, 'Drug administration');
app.controls.NPEnabled.Value = true;
verifyTrue(testCase, app.collect().Meta.Neuropixels.Enabled);
delete(cleanup);
end

function testTheSetupDialogOffersWhatABrokenHoldDoes(testCase)
assumeUIFigures(testCase);
[~, ~, app] = lum.gui.SetupDialog(testCase.TestData.S, testCase.TestData.rig, 'Wait', false, ...
                                  'Visible', 'off');
cleanup = onCleanup(@() closeIfOpen(app.Figure));
verifyEqual(testCase, app.controls.OnHoldBreak.Value, 'Restart stimulus');
app.controls.OnHoldBreak.Value = 'End trial';
app.refresh();
verifyEqual(testCase, app.collect().Task.OnHoldBreak, 'End trial');
verifySubstring(testCase, app.controls.ShapingNote.Text, 'ends the trial');
verifySubstring(testCase, app.controls.HoldNote.Text, 'from the poke', ...
                'The hold length must be shown where the hold is set up');
delete(cleanup);
end

function testTheStimulusTabSetsTheLatencyFromThePoke(testCase)
assumeUIFigures(testCase);
[~, ~, app] = lum.gui.SetupDialog(testCase.TestData.S, testCase.TestData.rig, 'Wait', false, ...
                                  'Visible', 'off');
cleanup = onCleanup(@() closeIfOpen(app.Figure));
c = app.controls;
verifyEqual(testCase, c.StimulusLatency.Value, 0, 'The stimulus starts on the poke by default');
c.StimulusLatency.Value = 0.25;
app.refresh();
verifyEqual(testCase, app.collect().Stimulus.Latency, 0.25);
verifySubstring(testCase, c.HoldNote.Text, 'the latency (0.25 s)');
verifyEqual(testCase, numel(findobj(c.CueAxes, 'Type', 'rectangle')), 4, ...
            'The latency is drawn before the stimulus');
verifyNotEmpty(testCase, findobj(c.FlowAxes, 'Type', 'text', 'String', 'Latency'));
verifySubstring(testCase, app.status(), 'Ready to start');
delete(cleanup);
end

function testTheCueTabTimesEachPartFromThePoke(testCase)
assumeUIFigures(testCase);
[~, ~, app] = lum.gui.SetupDialog(testCase.TestData.S, testCase.TestData.rig, 'Wait', false, ...
                                  'Visible', 'off');
cleanup = onCleanup(@() closeIfOpen(app.Figure));
c = app.controls;
bars = @() numel(findobj(c.CueAxes, 'Type', 'rectangle'));
verifyEqual(testCase, bars(), 3, 'The stimulus, and the light before and after the poke');
c.CueThrough(1).Value = false;
c.CueDuration(1).Value = 0;
c.CueEnabled(2).Value = true;
app.refresh();
cue = app.collect().Cue.Components;
verifyEqual(testCase, [cue(1).ThroughStimulus, cue(1).Duration], [0 0]);
verifyTrue(testCase, cue(2).Enabled);
verifyEqual(testCase, bars(), 1 + 1 + 2, 'A light off at the poke, a tone through the stimulus');
verifyEqual(testCase, c.CueDuration(2).Enable, matlab.lang.OnOffSwitchState('off'), ...
            'A time is only asked for when the part stops before the stimulus ends');
delete(cleanup);
end

function testTheTrialTimelineStaysInsideItsAxes(testCase)
% The timeline was cut off at the right edge when its labels outgrew their blocks.
assumeUIFigures(testCase);
S = testCase.TestData.S;
S.GUI.ITI = 0.2;
S.GUI.PostStimulusHold = 0.3;
S.Task.HoldShaping = 'Both';
S.Stimulus.Latency = 0.3;
for width = [1150 760 520]
    fig = uifigure('Visible', 'off', 'Position', [20 20 width + 40 220]);
    cleanup = onCleanup(@() closeIfOpen(fig));
    ax = uiaxes(fig, 'Position', [20 20 width 180]);
    lum.gui.drawTrialFlow(ax, S);
    drawnow;
    for label = findobj(ax, 'Type', 'text')'
        extent = label.Extent;
        verifyGreaterThanOrEqual(testCase, extent(1), ax.XLim(1) - 1e-6, ...
            sprintf('"%s" starts left of the axes at %d px', label.String, width));
        verifyLessThanOrEqual(testCase, extent(1) + extent(3), ax.XLim(2) + 1e-6, ...
            sprintf('"%s" runs past the right of the axes at %d px', label.String, width));
    end
    delete(cleanup);
end
end

function testTheSessionTypeChooserReturnsTheChoice(testCase)
assumeUIFigures(testCase);
[choice, app] = lum.gui.SessionTypeDialog('Default', 'Sleep', 'Wait', false, 'Visible', 'off');
verifyEqual(testCase, choice, '', 'Nothing is chosen until a button is pressed');
app.choose('Sleep');
verifyEqual(testCase, app.choice(), 'Sleep');
verifyFalse(testCase, isvalid(app.Figure), 'Choosing closes the window');
[~, app] = lum.gui.SessionTypeDialog('Wait', false, 'Visible', 'off');
app.cancel();
verifyEqual(testCase, app.choice(), '');
end

function testTheSleepSetupDialogReadsBackWhatItWasGiven(testCase)
assumeUIFigures(testCase);
S = testCase.TestData.S;
[~, accepted, app] = lum.gui.SleepSetupDialog(S, testCase.TestData.rig, 'Wait', false, ...
                                              'Visible', 'off');
cleanup = onCleanup(@() closeIfOpen(app.Figure));
verifyFalse(testCase, accepted);
candidate = app.collect();
verifyEqual(testCase, candidate.Session.Type, 'Sleep');
for group = {'Meta', 'Sleep', 'Task', 'Stimulus', 'GUI'}
    verifyEqual(testCase, candidate.(group{1}), S.(group{1}), group{1});
end
verifyEqual(testCase, candidate.Sync.Barcode, S.Sync.Barcode);
verifySubstring(testCase, app.status(), 'Ready to start');

% With test pulses the recording lasts as long as their schedule, and the recording's
% own length comes back when they are switched off.
app.controls.TestPulsesEnabled.Value = true;
app.refresh();
verifyEqual(testCase, app.controls.Duration.Value, 240);
verifyEqual(testCase, app.controls.Duration.Enable, matlab.lang.OnOffSwitchState('off'));
verifySubstring(testCase, app.status(), 'Test pulses: 7200 epoch(s)');
verifySubstring(testCase, app.controls.TestPulseSummary.Text, 'paired 10 ms pulses');
candidate = app.collect();
verifyTrue(testCase, candidate.Sleep.TestPulses.Enabled);
verifyEqual(testCase, candidate.Sleep.DurationMinutes, S.Sleep.DurationMinutes);
app.controls.TestPulsesEnabled.Value = false;
app.refresh();
verifyEqual(testCase, app.controls.Duration.Value, S.Sleep.DurationMinutes);

app.controls.Interval.Value = 0.05;   % Shorter than the longest jittered pulse
app.refresh();
verifySubstring(testCase, app.status(), 'at least 1 ms');
verifyEqual(testCase, app.controls.Start.Enable, matlab.lang.OnOffSwitchState('off'));
app.controls.Interval.Value = 2;
app.refresh();
[ok, started] = app.start();
verifyTrue(testCase, ok);
verifyEqual(testCase, started.Sleep.Sync.Interval, 2);
delete(cleanup);
end

function testTheStimulusDesignerKeepsTheDesignItWasGiven(testCase)
assumeUIFigures(testCase);
S = testCase.TestData.S;
[~, ~, app] = lum.gui.StimulusDesigner(S, testCase.TestData.rig, 'Wait', false, ...
                                       'Visible', 'off');
cleanup = onCleanup(@() closeIfOpen(app.Figure));
candidate = app.collect();
verifyEqual(testCase, candidate.Stimulus.Generator, ...
            lum.pattern.withGeneratorDefaults(S.Stimulus.Generator));
verifyEqual(testCase, candidate.Task.GroupPLeft, S.Task.GroupPLeft);

app.controls.Family.Value = 'occupancy';
app.controls.nGroups.Value = 5;
app.refresh();
verifySubstring(testCase, app.status(), '5 group(s)');
verifyEqual(testCase, app.collect().Task.GroupPLeft, linspace(1, 0, 5), 'AbsTol', 1e-12);
[ok, applied] = app.apply();
verifyTrue(testCase, ok);
verifyEqual(testCase, applied.Stimulus.Generator.Family, 'occupancy');
delete(cleanup);
end


function testTheTestPulseDesignerKeepsTheDesignItWasGiven(testCase)
assumeUIFigures(testCase);
S = testCase.TestData.S;
[~, ~, app] = lum.gui.TestPulseDesigner(S, testCase.TestData.rig, 'Wait', false, 'Visible', 'off');
cleanup = onCleanup(@() closeIfOpen(app.Figure));
verifyEqual(testCase, app.collect().Sleep.TestPulses, S.Sleep.TestPulses);
verifySubstring(testCase, app.status(), 'Ready');
verifyEqual(testCase, app.controls.StepTable.Data{1, 5}, 7200, 'Epochs are counted per step');

app.preset('Probe, theta burst, probe');
design = app.collect().Sleep.TestPulses;
verifyTrue(testCase, design.PlasticityTrains, 'A preset with a train switches trains on');
verifyEqual(testCase, {design.Schedule.Kind}, {'Probe', 'Theta burst', 'Probe'});
verifySubstring(testCase, app.status(), 'Ready');

app.controls.TrainsEnabled.Value = false;
app.refresh();
verifySubstring(testCase, app.status(), 'plasticity trains are switched off');
verifyEqual(testCase, app.controls.Apply.Enable, matlab.lang.OnOffSwitchState('off'));
app.controls.TrainsEnabled.Value = true;

app.selectStep(2);
app.addStep();
verifyNumElements(testCase, app.collect().Sleep.TestPulses.Schedule, 4);
[ok, applied] = app.apply();
verifyTrue(testCase, ok);
verifyFalse(testCase, applied.Sleep.TestPulses.Enabled, ...
            'Switching test pulses on belongs to the sleep setup dialog');
verifyEqual(testCase, applied.Sleep.TestPulses.Schedule(2).Minutes, 100 / 60, 'AbsTol', 1e-9, ...
            'A train step carries the minutes its trains last');
delete(cleanup);
end


%% Helpers -----------------------------------------------------------------------

function [S, stimulusSet] = sessionFixture(testCase, family, nGroups, continuous)
% A stimulus set for the plots, which spend no timers: the budget is generous so a
% family's default cycle fits whatever the machine.
S = testCase.TestData.S;
S.Stimulus.Generator.Family = family;
S.Stimulus.Generator.nGroups = nGroups;
S.Stimulus.Generator.Continuous = continuous;
if continuous
    S.Task.GroupPLeft = [1 0];
else
    S.Task.GroupPLeft = lum.pattern.defaultPLeft(nGroups);
end
stimulusSet = lum.pattern.stimulusSet(S, 64, 2);
end

function feed(plots, S, stimulusSet, nTrials)
% Run synthetic trials through the plots: correct, incorrect, no response, early
% withdrawal in turn, with reaction times from 0.2 to 1.2 s.
history = lum.newHistory(S.Session.MaxTrials);
queue = stimulusSet.TrialPattern;
[spec, queue] = lum.nextTrialSpec(S, stimulusSet, queue, history, 1);
outcomes = [lum.Outcome.Correct, lum.Outcome.Incorrect, lum.Outcome.NoResponse, ...
            lum.Outcome.EarlyWithdrawal];
for trial = 1:nTrials
    outcome = outcomes(mod(trial, 4) + 1);
    result = struct('Outcome', outcome, 'Choice', NaN, 'Correct', NaN, ...
                    'Rewarded', double(outcome == lum.Outcome.Correct), ...
                    'ReactionTime', NaN, 'HoldBreaks', 0, 'HoldAttempts', 1);
    if outcome == lum.Outcome.Correct || outcome == lum.Outcome.Incorrect
        result.Correct = double(outcome == lum.Outcome.Correct);
        result.Choice = spec.CorrectSide;
        if outcome == lum.Outcome.Incorrect
            result.Choice = 3 - spec.CorrectSide;
        end
        result.ReactionTime = 0.2 + 0.25 * mod(trial, 5);
    end
    history = lum.updateHistory(history, trial, spec, result);
    [nextSpec, queue] = lum.nextTrialSpec(S, stimulusSet, queue, history, trial + 1);
    plots.update(trial, spec, result, nextSpec, queue, 3);
    spec = nextSpec;
end
end

function ax = axesTitled(figureHandle, prefix)
% The axes whose title starts with prefix, or [] when there is none.
candidates = findall(figureHandle, 'Type', 'axes');
ax = [];
for i = 1:numel(candidates)
    if startsWith(string(candidates(i).Title.String), prefix)
        ax = candidates(i);
        return
    end
end
end

function assumeUIFigures(testCase)
% Skip, rather than fail, where MATLAB cannot create a uifigure (some batch sessions).
try
    probe = uifigure('Visible', 'off');
    delete(probe);
catch uiError
    assumeFail(testCase, sprintf('uifigure is not available here: %s', uiError.message));
end
end

function closeIfOpen(figureHandle)
if ~isempty(figureHandle) && isvalid(figureHandle)
    delete(figureHandle);
end
end
