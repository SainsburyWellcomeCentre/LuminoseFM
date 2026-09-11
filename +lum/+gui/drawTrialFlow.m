function drawTrialFlow(targetAxes, S)
% lum.gui.drawTrialFlow draws one trial as a timeline, from the cue to the inter-trial interval.
%
% Every block carries its current length, so changing the stimulus window, its latency
% from the poke or a runtime timing is seen in context rather than as a number in a
% field. Blocks whose length the animal decides — waiting for the poke with the cue on,
% leaving and choosing, the outcome — are drawn at a fixed width and labelled with their
% limit. The bracket under the hold, from the poke, says what a broken hold does and,
% when the hold is shaped, how.
%
% Blocks are laid out in the axes' own pixels: each is at least as wide as its labels
% and the rest of the width is shared out by duration, and every caption is kept
% inside the axes, so nothing is cut off at the edges however the window is sized.
% Redraw when the axes change size.
%
% Setup dialog only: it clears and redraws the axes.
%
% Arguments:
%   targetAxes  Axes to draw into
%   S           Settings struct (need not be valid: bad values draw as zero)
%
% See also: lum.gui.SetupDialog, lum.cueTiming, lum.HoldShaping

t = lum.gui.theme();
cla(targetAxes);
hold(targetAxes, 'on');

stimulusWindow = max(S.Stimulus.Duration, 0);
postHold = max(S.GUI.PostStimulusHold, 0);
latency = max(S.Stimulus.Latency, 0);
openSpan = max(0.35, 0.3 * (latency + stimulusWindow + postHold));
if latency > 0
    stimulusCaption = sprintf('%g s', stimulusWindow);
else
    stimulusCaption = sprintf('%g s, from the poke', stimulusWindow);
end

% Name, seconds drawn as, colour, caption, part of the hold
blocks = { ...
    'Cue on: wait for poke', openSpan, mix(t.Accent, 0.35), cueCaption(S), false; ...
    'Latency',      latency, mix(t.Accent, 0.2), sprintf('%g s, cue on', latency), true; ...
    'Stimulus',     max(stimulusWindow, 0.04), mix((t.ChannelA + t.ChannelB) / 2, 0.7), ...
                    stimulusCaption, true; ...
    'Post-stimulus hold', postHold, mix(t.Muted, 0.35), sprintf('%g s', postHold), true; ...
    'Leave and choose', openSpan, t.Faint, sprintf('<= %g s', S.GUI.ResponseWindow), false; ...
    'Outcome',      0.8 * openSpan, mix(t.Correct, 0.3), 'reward / punish', false; ...
    'ITI',          max(S.GUI.ITI, 0.08), t.Faint, sprintf('%g s', S.GUI.ITI), false};
blocks([false, latency == 0, false, postHold == 0, false, false, false], :) = [];
nBlocks = size(blocks, 1);

axesWidth = pixelWidth(targetAxes);
gap = 8;
minimum = zeros(1, nBlocks);
for i = 1:nBlocks
    minimum(i) = max(textWidth(blocks{i, 1}, true), textWidth(blocks{i, 4}, false)) + 12;
end
widths = fitWidths([blocks{:, 2}], minimum, axesWidth - gap * (nBlocks - 1));

x = 0;
holdStart = NaN;
holdEnd = NaN;
for i = 1:nBlocks
    [name, ~, colour, caption, inHold] = blocks{i, :};
    width = widths(i);
    rectangle(targetAxes, 'Position', [x 0.40 width 0.34], 'FaceColor', colour, ...
              'EdgeColor', 'none', 'Curvature', 0.12);
    text(targetAxes, x + width / 2, 0.57, caption, 'HorizontalAlignment', 'center', ...
         'FontSize', 9, 'Color', t.Ink);
    text(targetAxes, x + width / 2, 0.90, name, 'HorizontalAlignment', 'center', ...
         'FontSize', 9, 'FontWeight', 'bold', 'Color', t.Ink);
    if inHold
        if isnan(holdStart)
            holdStart = x;
        end
        holdEnd = x + width;
    end
    x = x + width + gap;
end
total = x - gap;

% The hold window runs from trial start to the end of a completed hold, across any
% restarts, so it is bracketed over the top of those blocks.
line(targetAxes, [0 0 holdEnd holdEnd], [0.97 1.01 1.01 0.97], 'Color', t.Muted, 'LineWidth', 1);
windowText = sprintf('hold window: a hold completed within %g s of trial start', S.GUI.HoldWindow);
text(targetAxes, keptInside(holdEnd / 2, textWidth(windowText, false), total), 1.05, windowText, ...
     'HorizontalAlignment', 'center', 'FontSize', 9, 'Color', t.Muted);

% The centre hold, bracketed underneath, with what a break does and how it is shaped.
line(targetAxes, [holdStart holdStart holdEnd holdEnd], [0.33 0.27 0.27 0.33], ...
     'Color', t.Accent, 'LineWidth', 1.2);
if isfield(S.Task, 'OnHoldBreak') && strcmp(S.Task.OnHoldBreak, 'End trial')
    breakText = 'leaving early ends the trial';
else
    breakText = 'leaving early stops the stimulus and the cue comes back; the next poke restarts it';
end
if lum.HoldShaping.growsHold(S.Task.HoldShaping) || lum.HoldShaping.hasGrace(S.Task.HoldShaping)
    caption = sprintf('centre hold, shaped (%s): %s', lower(S.Task.HoldShaping), breakText);
else
    caption = sprintf('centre hold: %s', breakText);
end
text(targetAxes, keptInside((holdStart + holdEnd) / 2, textWidth(caption, false), total), 0.14, ...
     caption, 'HorizontalAlignment', 'center', 'FontSize', 9, 'Color', t.Accent);

axis(targetAxes, 'off');
% When the blocks' labels need more than the axes have, the drawing is wider than the
% axes and is scaled down to fit; the margin keeps the outermost labels in view.
margin = max(0, total - axesWidth) / 2 + 2;
targetAxes.XLim = [-margin, total + margin];
targetAxes.YLim = [0 1.12];
hold(targetAxes, 'off');


function text = cueCaption(S)
% The parts of the cue, in words.
try
    types = {lum.cueTiming(S).Type};
catch
    types = {};
end
if isempty(types)
    text = 'no cue';
    return
end
names = struct('CentreLight', 'light', 'Tone', 'tone', 'Air', 'air');
words = cellfun(@(type) names.(type), types, 'UniformOutput', false);
text = strjoin(words, ' + ');


function width = pixelWidth(ax)
% The axes' drawing width in pixels, or a typical one before it has been laid out.
width = 0;
try
    position = ax.InnerPosition;
    if strcmp(ax.Units, 'pixels')
        width = position(3);
    end
catch
    % Not an axes with a pixel position; fall back below
end
if ~(width > 200)
    width = 1150;
end


function width = textWidth(text, isBold)
% A generous estimate of a 9 pt label's width in pixels.
perCharacter = 6.4 + 0.6 * isBold;
width = numel(text) * perCharacter;


function widths = fitWidths(seconds, minimum, available)
% Widths proportional to seconds, none narrower than its minimum, adding up to the
% space available wherever the minimums allow it.
widths = minimum;
free = true(size(seconds));
for pass = 1:numel(seconds)
    share = available - sum(minimum(~free));
    scale = share / sum(seconds(free));
    tooNarrow = free & (seconds * scale < minimum);
    if ~any(tooNarrow)
        widths(free) = seconds(free) * scale;
        return
    end
    free(tooNarrow) = false;
    if ~any(free)
        return
    end
end


function centre = keptInside(centre, width, total)
% A centre for a label of this width that keeps all of it between 0 and total.
if width >= total
    centre = total / 2;
else
    centre = min(max(centre, width / 2), total - width / 2);
end


function colour = mix(colour, amount)
% A colour faded towards white: amount 1 is the colour, 0 is white.
colour = 1 - amount * (1 - colour);
