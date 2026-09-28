function [file, lines] = sessionLog(Data, dataFile, varargin)
% lum.report.sessionLog writes a behaviour session's log: its settings and how the animal did.
%
%   [file, lines] = lum.report.sessionLog(SessionData, dataFile)
%
% A plain Markdown file for the lab notebook, readable as text:
%
%   <subject>\LuminoseFM\Session Logs\<data file name>_log.md
%
% Sections: the session (when, how long, how it ended, the code), the animal and what else
% was recorded or given, the settings that shape a trial (stage, hold and shaping, stimulus,
% light, reward, timing, punishment, bias correction, components, sync, video), the
% behaviour (trials, score, choices, water, the hold, reaction time, bias, P(left) by group,
% 50-trial blocks), every runtime setting changed during the session, and the recordings
% (video frames, barcode, analog stream). Numbers come from lum.report.sessionTrials, so they
% match the summary plots.
%
% Arguments:
%   Data      The session's data (BpodSystem.Data, or a saved file's SessionData)
%   dataFile  The session's data file; names the log and places its folder
%
% Options:
%   'Folder'  Where to write (default lum.report.folder(dataFile, 'Logs'))
%   'Write'   false returns the lines without writing a file (file is then '')
%
% Returns the file written and its lines.
%
% See also lum.report.write, lum.report.sessionTrials, lum.report.summaryPlots

p = inputParser;
p.FunctionName = 'lum.report.sessionLog';
addParameter(p, 'Folder', '');
addParameter(p, 'Write', true);
parse(p, varargin{:});

T = lum.report.sessionTrials(Data);
S = T.S;
[~, dataName] = fileparts(char(dataFile));
L = {};

%% Session
stage = stageName(S);
subject = orDash(T.subject);
started = fieldOr(Data.Session, 'StartTime', '');
L{end+1} = sprintf('# %s, %s: behaviour, %s', subject, started(1:min(16, end)), stage);
L{end+1} = '';
L{end+1} = sprintf('- Data: `%s.mat`', dataName);
ended = fieldOr(Data.Session, 'EndTime', '');
L{end+1} = sprintf('- Ran %s to %s; %d trials in %.0f min (%.1f trials/min)', ...
                   timeOf(started), timeOf(ended), T.n, max(T.finish) / 60, ...
                   T.n / max(max(T.finish) / 60, eps));
reason = fieldOr(Data.Session, 'StoppedReason', '');
if ~isempty(reason)
    L{end+1} = sprintf('- Ended in an error: %s', reason);
elseif T.n < S.Session.MaxTrials
    L{end+1} = sprintf('- Stopped from the console after %d of %d trials', T.n, S.Session.MaxTrials);
else
    L{end+1} = sprintf('- Ran all %d trials', T.n);
end
L{end+1} = sprintf('- LuminoseFM %s%s', fieldOr(Data.Session, 'ProtocolVersion', '?'), ...
                   emulatedText(Data));
if ~isempty(strtrim(S.Meta.Notes))
    L{end+1} = sprintf('- Notes: %s', oneLine(S.Meta.Notes));
end

%% Animal and experiment
L = section(L, 'Animal and experiment');
L{end+1} = sprintf('- Subject %s, genotype %s', subject, orDash(fieldOr(S.Meta, 'Genotype', '')));
L{end+1} = sprintf('- Task %s; %s', orDash(fieldOr(S.Task, 'Variant', '')), lum.trainingStageNote(S));
if isfield(S.Meta, 'Neuropixels') && S.Meta.Neuropixels.Enabled
    np = S.Meta.Neuropixels;
    L{end+1} = sprintf('- Neuropixels: %s, %s implant, target %s, serial %s', np.Probe, ...
                       lower(np.Implant), orDash(np.Target), orDash(np.SerialNumber));
end
if isfield(S.Meta, 'EEG') && S.Meta.EEG.Enabled
    L{end+1} = sprintf('- EEG/EMG: %d EEG, %d EMG channels', S.Meta.EEG.EEGChannels, S.Meta.EEG.EMGChannels);
end
if isfield(S.Meta, 'Drug') && S.Meta.Drug.Enabled
    drug = S.Meta.Drug;
    L{end+1} = sprintf('- Drug: %s %g %s in %s, %s, %g min before the session', orDash(drug.Name), ...
                       drug.Dose, drug.DoseUnit, drug.Vehicle, drug.Delivery, drug.MinutesBeforeSession);
end

%% Settings
L = section(L, 'Settings (as the first trial started)');
L{end+1} = sprintf('- Centre hold: %s', lum.HoldShaping.describeHold(S));
L{end+1} = sprintf('- %s', lum.HoldShaping.describe(S));
L{end+1} = sprintf('- %s', lum.HoldShaping.describeBreak(S));
stimulusSet = T.stimulusSet;
L{end+1} = sprintf('- Stimulus: %s; window %g s, latency %g s; %d group(s): %s; seed %d', ...
                   familyLabel(stimulusSet), S.Stimulus.Duration, S.Stimulus.Latency, ...
                   stimulusSet.nGroups, groupText(stimulusSet), stimulusSet.Seed);
if isfield(stimulusSet, 'Shortcuts')
    L{end+1} = sprintf('- %s', lum.pattern.describeShortcuts(stimulusSet.Shortcuts));
end
L{end+1} = sprintf('- Light: %s', lightText(Data, S, T));
L{end+1} = sprintf('- Components: cue %s; stimulus %s; left %s; right %s', ...
                   componentText(S.Cue.Components), stimulusComponentText(S), sideText(S.Left), ...
                   sideText(S.Right));
g = S.GUI;
L{end+1} = sprintf('- Reward: %g uL a side reward, delay %g s, drinking grace %g s; centre reward %s', ...
                   g.RewardAmount, g.RewardDelay, g.DrinkingGrace, centreRewardText(S));
L{end+1} = sprintf('- Timing: hold window %g s, response window %g s, ITI %g s', g.HoldWindow, ...
                   g.ResponseWindow, g.ITI);
punish = lum.punishmentFor(S, 'IncorrectChoice');
L{end+1} = sprintf('- Punishment: on %s, %s, timeout %g s; an unpunished wrong choice %s', ...
                   lower(menuItem(S, 'PunishCondition')), lower(menuItem(S, 'PunishType')), ...
                   g.PunishTimeout, ternary(punish.Retry, 'may be retried', 'ends the trial'));
L{end+1} = sprintf('- Trial order: bias correction %g over the last %d choices, at most %s the same side in a row%s', ...
                   g.BiasCorrection, round(g.BiasWindow), runLimitText(S), ...
                   ternary(S.Task.ReverseContingency, ', contingency reversed', ''));
L{end+1} = sprintf('- House light %s at the start; sounds %s', ...
                   ternary(logical(S.Session.HouseLight), 'on', 'off'), ...
                   ternary(logical(S.Session.UseSound), 'on', 'off'));

%% Behaviour
L = section(L, 'Behaviour');
chose = ~isnan(T.choice);
nChoices = sum(chose);
if all(T.bothSidesPay)
    L{end+1} = sprintf('- Rewarded on %d of %d trials (%.0f%%); both side ports paid', ...
                       sum(T.rewarded == 1), T.n, 100 * mean(T.rewarded == 1));
else
    L{end+1} = sprintf('- Correct on %d of %d choices (%.0f%%); rewarded on %d of %d trials', ...
                       sum(T.correct == 1), nChoices, 100 * sum(T.correct == 1) / max(1, nChoices), ...
                       sum(T.rewarded == 1), T.n);
end
% A trial that ended on an early withdrawal ('End trial') did not complete its hold: it is
% counted there, as in the plots, and named apart only when there were any.
endedByWithdrawal = sum(T.outcome == lum.Outcome.EarlyWithdrawal);
endedText = '';
if endedByWithdrawal > 0
    endedText = sprintf(' (%d ended by an early withdrawal)', endedByWithdrawal);
end
L{end+1} = sprintf('- Choices: %d (left %d, right %d); no choice on %d: no hold started %d, hold not completed %d%s, no side poke in time %d', ...
                   nChoices, sum(T.choice == 1), sum(T.choice == 2), T.n - nChoices, ...
                   sum(T.outcome == lum.Outcome.NoInitiation), ...
                   sum(T.outcome == lum.Outcome.HoldNotCompleted) + endedByWithdrawal, endedText, ...
                   sum(T.outcome == lum.Outcome.NoResponse & ~chose));
if any(T.responseRetries > 0)
    L{end+1} = sprintf('- Retries after a wrong choice: %d, on %d trials', sumPresent(T.responseRetries), ...
                       sum(T.responseRetries > 0));
end
centre = nanToZero(T.centreReward);
L{end+1} = sprintf('- Water: %.0f uL (side %.0f uL in %d rewards; centre %.0f uL in %d)', ...
                   sum(T.sideWater) + sum(centre), sum(T.sideWater), sum(T.rewarded == 1), ...
                   sum(centre), sum(centre > 0));
reached = '';
if lum.HoldShaping.growsHold(S)
    atTarget = find(T.holdDuration >= S.GUI.HoldTarget - 5e-5, 1);
    if isempty(atTarget)
        reached = sprintf('; did not reach the target (%g s)', S.GUI.HoldTarget);
    else
        reached = sprintf('; reached the target (%g s) on trial %d', S.GUI.HoldTarget, atTarget);
    end
end
L{end+1} = sprintf('- Centre hold asked for, from the poke: %.3g s at the start, %.3g s at the end (%.3g-%.3g s)%s; stepped back %d times', ...
                   T.holdAsked(1), T.holdAsked(end), min(T.holdAsked), max(T.holdAsked), reached, ...
                   sum(T.steppedBack));
completed = T.holdCompleted == 1;
L{end+1} = sprintf('- Hold completed on %d of %d trials (%.0f%%), in the port a median %.2f s from the poke', ...
                   sum(completed), T.n, 100 * mean(completed), median(T.centreHoldTime(completed), 'omitnan'));
L{end+1} = sprintf('- Held on the first attempt on %d trials (%.0f%% of trials, %.0f%% of completed holds); %d hold attempts (%.1f a trial), %d early withdrawals', ...
                   sum(T.heldFirstAttempt), 100 * mean(T.heldFirstAttempt), ...
                   100 * sum(T.heldFirstAttempt) / max(1, sum(completed)), sum(T.attempts), ...
                   mean(T.attempts), sum(T.attempts) - sum(completed));
rt = T.reactionTime(chose);
L{end+1} = sprintf('- Reaction time: median %.2f s (quartiles %.2f-%.2f s)', median(rt, 'omitnan'), ...
                   quantileOf(rt, 0.25), quantileOf(rt, 0.75));
L{end+1} = sprintf('- Side: chose left on %.0f%% of choices; bias correction aimed for P(left) %.2f-%.2f', ...
                   100 * mean(T.choice(chose) == 1), min(T.biasTarget), max(T.biasTarget));
L{end+1} = sprintf('- By group: %s', byGroupText(T));
L{end+1} = '';
L{end+1} = sprintf('| Trials | %s | Choices | Hold completed | Held on the first attempt | Attempts a trial | Hold asked (s) | RT median (s) | Minutes |', ...
                   ternary(all(T.bothSidesPay), 'Rewarded', 'Correct'));
L{end+1} = '|---|---|---|---|---|---|---|---|---|';
for first = 1:50:T.n
    block = first:min(T.n, first + 49);
    blockChose = chose(block);
    if all(T.bothSidesPay)
        score = mean(T.rewarded(block) == 1);
    else
        score = sum(T.correct(block) == 1) / max(1, sum(blockChose));
    end
    L{end+1} = sprintf('| %d-%d | %.0f%% | %d | %.0f%% | %.0f%% | %.1f | %.2f-%.2f | %.2f | %.0f-%.0f |', ...
                       block(1), block(end), 100 * score, sum(blockChose), ...
                       100 * mean(T.holdCompleted(block)), 100 * mean(T.heldFirstAttempt(block)), ...
                       mean(T.attempts(block)), min(T.holdAsked(block)), ...
                       max(T.holdAsked(block)), median(T.reactionTime(block), 'omitnan'), ...
                       T.start(block(1)) / 60, T.finish(block(end)) / 60); %#ok<AGROW>
end

%% Changes
L = section(L, 'Changed during the session');
if isempty(T.runtimeChanges)
    L{end+1} = '- Nothing';
else
    for c = T.runtimeChanges
        L{end+1} = sprintf('- From trial %d: %s %s -> %s', c.Trial, labelOf(S, c.Name), ...
                           valueText(S, c.Name, c.From), valueText(S, c.Name, c.To)); %#ok<AGROW>
    end
end

%% Recordings
L = section(L, 'Recordings');
L = [L, recordingLines(Data)];
L{end+1} = sprintf('- Summary plots: `%s`', lum.report.folder(dataFile, 'Plots'));
L{end+1} = '';

lines = L;
file = '';
if ~p.Results.Write
    return
end
folder = char(p.Results.Folder);
if isempty(folder)
    folder = lum.report.folder(dataFile, 'Logs');
end
if ~isfolder(folder)
    mkdir(folder);
end
file = fullfile(folder, [dataName '_log.md']);
handle = fopen(file, 'w', 'n', 'UTF-8');
if handle < 0
    error('lum:report:sessionLog:cannotWrite', 'Could not write %s.', file);
end
closer = onCleanup(@() fclose(handle));
fprintf(handle, '%s\n', lines{:});
clear closer
end


%% Pieces ------------------------------------------------------------------------

function L = section(L, title)
% A Markdown section heading, with a blank line either side.
L{end+1} = '';
L{end+1} = sprintf('## %s', title);
L{end+1} = '';
end


function name = stageName(S)
% The training stage's name.
name = 'unknown stage';
if S.Task.TrainingStage >= 1 && S.Task.TrainingStage <= numel(S.Task.TrainingStageNames)
    name = S.Task.TrainingStageNames{S.Task.TrainingStage};
end
end


function label = familyLabel(stimulusSet)
% The stimulus family's label, or its name when it is not a known family.
families = lum.pattern.families();
family = families(strcmp({families.Name}, stimulusSet.Family));
label = stimulusSet.Family;
if ~isempty(family)
    label = family.Label;
end
end


function text = groupText(stimulusSet)
% Every group with the P(left) it ran with.
parts = cell(1, stimulusSet.nGroups);
for k = 1:stimulusSet.nGroups
    parts{k} = sprintf('%s (P(left) %.2f)', stimulusSet.GroupLabels{k}, stimulusSet.GroupPLeft(k));
end
text = strjoin(parts, ', ');
end


function text = lightText(Data, S, T)
% Whether light was delivered, at what LED current and irradiance, through which cables.
if ~S.Session.UseOpto
    text = 'off (no light pattern this session)';
    return
end
cables = {'', ''};
if isfield(S, 'Light') && isfield(S.Light, 'Cables') && numel(S.Light.Cables) == 2
    cables = S.Light.Cables;
end
channels = {'A', 'B'};
parts = cell(1, 2);
for k = 1:2
    series = sprintf('LEDCurrent%s', channels{k});
    current = NaN;
    if isfield(Data, series)
        values = Data.(series)(1:T.n);
        values = values(~isnan(values));
        if ~isempty(values)
            current = values(1);
            if any(values ~= current)
                current = [min(values), max(values)];
            end
        end
    end
    if all(isnan(current))
        amount = 'set by hand';
    elseif isscalar(current)
        amount = sprintf('%g mA', current);
    else
        amount = sprintf('%g-%g mA', current(1), current(2));
    end
    parts{k} = sprintf('%s %s (%s cable)', channels{k}, amount, orDash(cables{k}));
end
text = sprintf('on %d of %d trials; bundle %s; %s', sum(T.optoOn == 1), T.n, ...
               orDash(fieldOr(S.Light, 'Bundle', '')), strjoin(parts, ', '));
if isfield(Data.Session, 'DoricLED') && isfield(Data.Session.DoricLED, 'Intensity') ...
        && isfield(Data.Session.DoricLED.Intensity, 'Notes') && ~isempty(Data.Session.DoricLED.Intensity.Notes)
    text = sprintf('%s; %s', text, strjoin(cellstr(Data.Session.DoricLED.Intensity.Notes), ' '));
end
end


function text = componentText(rows)
% The enabled components of a cue or stimulus table, or 'none'.
on = rows([rows.Enabled]);
if isempty(on)
    text = 'none';
    return
end
text = strjoin(arrayfun(@(row) readable(row.Type), on, 'UniformOutput', false), ', ');
end


function text = stimulusComponentText(S)
% What the stimulus delivers: the light pattern and each enabled component.
parts = {};
if S.Session.UseOpto
    parts{end+1} = 'light pattern';
end
on = S.Stimulus.Components([S.Stimulus.Components.Enabled]);
for k = 1:numel(on)
    parts{end+1} = lower(readable(on(k).Type)); %#ok<AGROW>
end
if isempty(parts)
    text = 'none';
else
    text = strjoin(parts, ', ');
end
end


function text = sideText(side)
% A side's outputs: port light, tone and guide light.
parts = {};
if side.Light.Enabled
    parts{end+1} = 'port light';
end
if side.Tone.Enabled
    parts{end+1} = sprintf('tone %g Hz', side.Tone.Frequency);
end
parts{end+1} = sprintf('guide light %s', lower(side.GuideLight));
text = strjoin(parts, ', ');
end


function text = centreRewardText(S)
% When the centre reward is given, and how much.
g = S.GUI;
if g.CentreRewardAmount <= 0
    text = 'none';
elseif S.Task.TrainingStage == 1
    text = sprintf('%g uL on trials 1-%d', g.CentreRewardAmount, g.CentreRewardTrials);
else
    text = sprintf('%g uL when asked for again', g.CentreRewardAmount);
end
end


function text = runLimitText(S)
% The same-side run limit, or that there is none.
if S.Task.MaxSameSide < 1
    text = 'any number of trials';
else
    text = sprintf('%d', S.Task.MaxSameSide);
end
end


function text = byGroupText(T)
% How often the animal chose left on each group's trials with a choice.
labels = T.stimulusSet.GroupLabels;
parts = cell(1, numel(labels));
for k = 1:numel(labels)
    members = T.group == k & ~isnan(T.choice);
    parts{k} = sprintf('%s chose left %.0f%% (n=%d)', labels{k}, 100 * mean(T.choice(members) == 1), ...
                       sum(members));
end
text = strjoin(parts, '; ');
end


function out = recordingLines(Data)
% The Recordings section: video, barcode, trial sync pulses and the flow meter.
out = {};
session = Data.Session;
if isfield(session, 'Cameras') && isfield(session.Cameras, 'Summary') && ~isempty(session.Cameras.Summary) ...
        && isfield(session.Cameras.Summary, 'Cameras')
    for camera = session.Cameras.Summary.Cameras(:)'
        out{end+1} = sprintf('- Video %s (%s): %d frames written of %d logged; %d missed, %d dropped by the writer%s', ...
                             camera.Name, camera.Serial, camera.FramesWritten, camera.FramesLogged, ...
                             camera.FramesMissed, camera.WriterDrops, errorText(camera)); %#ok<AGROW>
    end
elseif isfield(session, 'Cameras') && isfield(session.Cameras, 'Recorded') && ~session.Cameras.Recorded
    out{end+1} = '- Video: not recorded';
end
if isfield(session, 'Barcode')
    out{end+1} = sprintf('- Barcode %s (%s), %s', session.Barcode.Hex, session.Barcode.Kind, ...
                         ternary(logical(session.Barcode.Sent), 'sent on the sync line', 'not sent'));
end
if isfield(Data, 'SyncMode') && isfield(Data.Session.Settings, 'Sync')
    names = lum.defaultSettings().Sync.ModeNames;
    mode = Data.SyncMode(1);
    if mode >= 1 && mode <= numel(names)
        out{end+1} = sprintf('- Trial sync pulses: %s', names{mode});
    end
end
if isfield(Data, 'Analog') && isfield(Data.Analog, 'Timestamps')
    out{end+1} = sprintf('- Flow meter (Flex analog): %d samples', numel(Data.Analog.Timestamps));
end
end


function text = errorText(camera)
% '; error: ...' when a camera's recording reported one, else ''.
text = '';
if isfield(camera, 'Error') && ~isempty(camera.Error)
    text = sprintf('; error: %s', camera.Error);
end
end


function text = labelOf(S, name)
% A runtime parameter's label as the windows show it, or its name.
text = name;
if isfield(S.GUIMeta, name) && isfield(S.GUIMeta.(name), 'Label')
    text = S.GUIMeta.(name).Label;
end
end


function text = valueText(S, name, value)
% A runtime value as the windows show it: a menu's item, a checkbox's on/off.
if isfield(S.GUIMeta, name) && isfield(S.GUIMeta.(name), 'String') && isnumeric(value) ...
        && isscalar(value) && value >= 1 && value <= numel(S.GUIMeta.(name).String)
    text = S.GUIMeta.(name).String{value};
elseif isfield(S.GUIMeta, name) && strcmp(S.GUIMeta.(name).Style, 'checkbox')
    text = ternary(value == 1, 'on', 'off');
elseif ischar(value)
    text = value;
else
    text = mat2str(value, 4);
end
end


function text = menuItem(S, name)
% A runtime parameter's current value as the windows show it.
text = valueText(S, name, S.GUI.(name));
end


function text = readable(name)
% A component type in words: 'CentreLight' -> 'Centre light'.
names = struct('CentreLight', 'Centre light', 'Tone', 'Tone', 'Air', 'Air');
text = name;
if isfield(names, name)
    text = names.(name);
end
end


function text = emulatedText(Data)
% ', EMULATED ...' for an emulated session, else ''.
text = '';
if isfield(Data.Session, 'Emulated') && Data.Session.Emulated
    text = ', EMULATED (no animal, no hardware)';
end
end


function text = timeOf(stamp)
% 'HH:MM' from 'yyyy-MM-dd HH:mm:ss'.
text = '?';
if numel(stamp) >= 16
    text = stamp(12:16);
end
end


function value = fieldOr(container, name, default)
% A field of a struct, or the default when it is absent or empty.
value = default;
if isstruct(container) && isfield(container, name) && ~isempty(container.(name))
    value = container.(name);
end
end


function text = orDash(text)
% '-' for an empty value.
if isempty(text)
    text = '-';
end
end


function text = oneLine(text)
% Text, or a cell of lines, as one line with single spaces.
text = strtrim(regexprep(char(strjoin(cellstr(text), ' ')), '\s+', ' '));
end


function value = ternary(condition, whenTrue, whenFalse)
% whenTrue if condition, otherwise whenFalse.
if condition
    value = whenTrue;
else
    value = whenFalse;
end
end


function total = sumPresent(values)
% The sum of the values that are not NaN.
total = sum(values(~isnan(values)));
end


function values = nanToZero(values)
% NaN counted as 0.
values(isnan(values)) = 0;
end


function value = quantileOf(values, q)
% A quantile without the Statistics Toolbox: linear between order statistics.
values = sort(values(~isnan(values)));
if isempty(values)
    value = NaN;
    return
end
position = 1 + q * (numel(values) - 1);
low = floor(position);
high = ceil(position);
value = values(low) + (position - low) * (values(high) - values(low));
end
