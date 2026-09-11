classdef PatternBrowser < handle
    % lum.gui.PatternBrowser scrolls through every trial's light pattern in a session.
    %
    % The stimulus set fixes the pattern and order of every trial before the
    % session starts, so the operator can look at exactly what trial 1, trial 2 or
    % trial 873 will deliver. Each trial is drawn as two lanes, channel A above
    % channel B, with a ribbon underneath coloured by joint state (dark, A only,
    % B only, both), and a line saying what the group is and which side it pays.
    %
    % Used by the setup dialog's Stimulus tab and by the stimulus designer, in
    % uifigures. Setup time only: redrawing here allocates freely.
    %
    % Usage:
    %   browser = lum.gui.PatternBrowser(parentGridOrPanel);
    %   browser.show(stimulusSet);          % a new stimulus set, keeping the trial shown
    %   browser.goTo(12);           % trial 12
    %   fig.WindowKeyPressFcn = @(~, e) browser.onKey(e);  % arrow keys, optional
    %
    % See also: lum.pattern.stimulusSet, lum.gui.StimulusDesigner, lum.gui.theme

    properties (SetAccess = private)
        Trial = 1   % Trial being shown
        Grid        % The browser's own grid layout
    end

    properties (Access = private)
        stimulusSet = []
        theme
        axes
        patchA
        patchB
        ribbon
        slider
        trialField
        info
    end

    methods
        function obj = PatternBrowser(parent)
            t = lum.gui.theme();
            obj.theme = t;
            obj.Grid = uigridlayout(parent, [3 1], 'RowHeight', {'1x', 30, 36}, ...
                                    'Padding', 0, 'RowSpacing', 6, 'BackgroundColor', t.Panel);

            ax = uiaxes(obj.Grid);
            ax.Toolbar.Visible = 'off';
            disableDefaultInteractivity(ax);
            set(ax, 'Color', t.Panel, 'XColor', t.Muted, 'YColor', t.Muted, 'Box', 'off', ...
                'TickDir', 'out', 'FontSize', 10, 'YLim', [-0.95 2.15], 'XGrid', 'on', ...
                'GridColor', t.Faint, 'GridAlpha', 1, 'YTick', [-0.35 0.7 1.65], ...
                'YTickLabel', {'joint', 'B', 'A'});
            xlabel(ax, 'Time from stimulus onset (s)');
            hold(ax, 'on');
            colormap(ax, t.StateColours);
            obj.ribbon = image(ax, 'XData', [0 1], 'YData', [-0.35 -0.35], ...
                               'CData', zeros(1, 1, 'uint8'), 'CDataMapping', 'direct');
            obj.patchA = patch(ax, 'Faces', zeros(0, 4), 'Vertices', zeros(0, 2), ...
                               'FaceColor', t.ChannelA, 'EdgeColor', 'none');
            obj.patchB = patch(ax, 'Faces', zeros(0, 4), 'Vertices', zeros(0, 2), ...
                               'FaceColor', t.ChannelB, 'EdgeColor', 'none');
            obj.axes = ax;

            controls = uigridlayout(obj.Grid, [1 5], 'ColumnWidth', {34, '1x', 34, 40, 70}, ...
                                    'Padding', 0, 'ColumnSpacing', 6, 'BackgroundColor', t.Panel);
            uibutton(controls, 'Text', '<', 'Tooltip', 'Previous trial', ...
                     'ButtonPushedFcn', @(~, ~) obj.goTo(obj.Trial - 1));
            obj.slider = uislider(controls, 'Limits', [1 2], 'Value', 1, ...
                                  'MajorTicks', [], 'MinorTicks', [], ...
                                  'ValueChangingFcn', @(~, event) obj.goTo(round(event.Value)), ...
                                  'ValueChangedFcn', @(source, ~) obj.goTo(round(source.Value)));
            uibutton(controls, 'Text', '>', 'Tooltip', 'Next trial', ...
                     'ButtonPushedFcn', @(~, ~) obj.goTo(obj.Trial + 1));
            uilabel(controls, 'Text', 'Trial', 'HorizontalAlignment', 'right', ...
                    'FontColor', t.Muted);
            obj.trialField = uieditfield(controls, 'numeric', 'Value', 1, 'Limits', [1 Inf], ...
                                         'RoundFractionalValues', 'on', ...
                                         'ValueChangedFcn', @(source, ~) obj.goTo(source.Value));

            obj.info = uilabel(obj.Grid, 'Text', 'No stimulus set yet.', 'WordWrap', 'on', ...
                               'FontColor', t.Ink, 'VerticalAlignment', 'top');
        end

        function show(obj, stimulusSet, trial)
            % show(stimulusSet) displays a (new) stimulus set, at the trial already shown.
            if nargin < 3
                trial = obj.Trial;
            end
            obj.stimulusSet = stimulusSet;
            nTrials = numel(stimulusSet.TrialPattern);
            obj.slider.Limits = [1 max(2, nTrials)];
            obj.slider.Enable = matlab.lang.OnOffSwitchState(nTrials > 1);
            obj.trialField.Limits = [1 max(1, nTrials)];
            obj.goTo(trial);
        end

        function goTo(obj, trial)
            % goTo(trial) draws one trial's pattern.
            if isempty(obj.stimulusSet) || ~isvalid(obj.axes)
                return
            end
            shown = obj.stimulusSet;
            nTrials = numel(shown.TrialPattern);
            trial = min(max(round(trial), 1), nTrials);
            obj.Trial = trial;
            obj.slider.Value = min(trial, obj.slider.Limits(2));
            obj.trialField.Value = trial;

            index = shown.TrialPattern(trial);
            pattern = lum.pattern.patternAt(shown, index);
            segments = pattern.Segments;
            obj.drawLane(obj.patchA, segments(segments(:, 1) == 1, :), 1.30, 2.00);
            obj.drawLane(obj.patchB, segments(segments(:, 1) == 2, :), 0.35, 1.05);

            if isfield(shown, 'States')
                states = shown.States(:, index)';
            else
                states = rasterise(segments, shown.nBins, shown.BinDuration);
            end
            bin = shown.BinDuration;
            window = max(shown.Duration, bin);
            obj.ribbon.XData = [bin / 2, window - bin / 2];
            obj.ribbon.CData = uint8(states);
            obj.axes.XLim = [0 window];

            d = shown.Descriptors;
            obj.info.Text = sprintf( ...
                ['Trial %d of %d  |  %s  |  P(left) %.2f  |  A %.3g s, B %.3g s, both %.3g s, '...
                 'dark %.3g s  |  %d global timer(s)'], trial, nTrials, pattern.Name, ...
                pattern.PLeft, d.AOn(index), d.BOn(index), d.Overlap(index), d.Dark(index), ...
                shown.nTimers(index));
        end

        function onKey(obj, event)
            % onKey(event) steps through trials with the left and right arrow keys.
            switch event.Key
                case 'leftarrow'
                    obj.goTo(obj.Trial - 1);
                case 'rightarrow'
                    obj.goTo(obj.Trial + 1);
            end
        end
    end

    methods (Access = private)
        function drawLane(~, lanePatch, segments, bottom, top)
            % One rectangle per segment, between bottom and top.
            n = size(segments, 1);
            vertices = zeros(4 * n, 2);
            for i = 1:n
                x0 = segments(i, 2);
                x1 = x0 + segments(i, 3);
                vertices(4 * i - 3:4 * i, :) = [x0 bottom; x1 bottom; x1 top; x0 top];
            end
            lanePatch.Faces = reshape(1:4 * n, 4, n)';
            lanePatch.Vertices = vertices;
        end
    end
end


function states = rasterise(segments, nBins, bin)
% Joint states per bin, rebuilt from segments when the set has no States.
states = zeros(1, nBins);
centres = ((1:nBins) - 0.5) * bin;
for i = 1:size(segments, 1)
    lit = centres >= segments(i, 2) & centres < segments(i, 2) + segments(i, 3);
    states(lit) = bitor(states(lit), segments(i, 1));
end
end
