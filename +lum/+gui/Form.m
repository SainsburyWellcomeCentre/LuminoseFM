classdef Form
    % lum.gui.Form holds the small layout helpers every setup window shares.
    %
    % The setup dialog, the sleep setup dialog and the experiment panels they share
    % (lum.gui.ExperimentForm) lay out forms the same way: titled panels of label and
    % field rows at one row height, numeric fields held to limits, muted notes, a
    % barcode preview. One definition here, so the windows look alike and a change of
    % spacing is made once. Static methods only, for uifigure components.
    %
    % See also: lum.gui.SetupDialog, lum.gui.SleepSetupDialog, lum.gui.ExperimentForm

    methods (Static)
        function grid = panel(parent, title, nRows, t, labelWidth)
            % panel(parent, title, nRows, t, labelWidth) is a titled panel holding a
            % label/field form of nRows rows; returns the form's grid.
            box = uipanel(parent, 'Title', title, 'FontWeight', 'bold', ...
                          'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
            grid = uigridlayout(box, [max(nRows, 1) 2], 'ColumnWidth', {labelWidth, '1x'}, ...
                                'RowHeight', repmat({26}, 1, max(nRows, 1)), ...
                                'Padding', [10 8 10 8], 'RowSpacing', 6, 'ColumnSpacing', 10, ...
                                'BackgroundColor', t.Panel);
        end

        function height = panelHeight(nRows)
            % panelHeight(nRows) is the pixel height panel() needs for nRows rows:
            % title bar, padding and rows.
            height = 44 + nRows * 32;
        end

        function label(parent, caption, t)
            % label(parent, caption, t) is a form row's label.
            uilabel(parent, 'Text', caption, 'FontColor', t.Ink);
        end

        function field = number(parent, value, limits, onEdit, isInteger)
            % number(parent, value, limits, onEdit, isInteger) is a numeric field held
            % to its limits, calling onEdit when it changes.
            field = uieditfield(parent, 'numeric', 'Value', value, 'Limits', limits, ...
                                'ValueChangedFcn', @(~, ~) onEdit());
            if isInteger
                field.RoundFractionalValues = 'on';
            end
        end

        function handle = note(parent, caption, t)
            % note(parent, caption, t) is a wrapped, muted explanation.
            handle = uilabel(parent, 'Text', caption, 'WordWrap', 'on', 'FontColor', t.Muted, ...
                             'FontSize', 11, 'VerticalAlignment', 'top');
        end

        function items = withValue(items, value)
            % withValue(items, value) is a dropdown's items with its current value
            % included, so an editable dropdown can show a value typed in an earlier
            % session.
            if ~isempty(value) && ~ismember(value, items)
                items = [{value}, items];
            end
        end

        function state = onOff(tf)
            % onOff(tf) is a logical as the on/off value an Enable property wants.
            state = matlab.lang.OnOffSwitchState(tf);
        end

        function setEnable(handles, on)
            % setEnable(handles, on) enables or disables a cell array of controls.
            for i = 1:numel(handles)
                handles{i}.Enable = lum.gui.Form.onOff(on);
            end
        end

        function drawBarcode(ax, params, kind, t)
            % drawBarcode(ax, params, kind, t) previews the barcode a session of this
            % kind started now would send.
            cla(ax);
            hold(ax, 'on');
            try
                code = lum.sync.barcode(lum.sync.barcodeValue(), params, kind);
            catch barcodeError
                title(ax, barcodeError.message, 'Color', t.Bad, 'FontWeight', 'normal', 'FontSize', 10);
                hold(ax, 'off');
                return
            end
            edges = [0 cumsum(code.Durations)];
            for i = find(code.Levels == 1)
                rectangle(ax, 'Position', [edges(i) 0 code.Durations(i) 1], 'FaceColor', t.Ink, ...
                          'EdgeColor', 'none');
            end
            set(ax, 'XLim', [0 edges(end)], 'YLim', [0 1.15], 'YTick', [], 'Color', t.Panel, ...
                'XColor', t.Muted, 'YColor', 'none', 'TickDir', 'out', 'Box', 'off');
            xlabel(ax, 'Seconds from the first edge');
            title(ax, sprintf('A %s session started now: 0x%s, %.2f s, %g ms markers', ...
                              lower(kind), code.Hex, code.TotalDuration, 1000 * code.MarkerWidth), ...
                  'FontWeight', 'normal', 'FontSize', 10, 'Color', t.Ink);
            hold(ax, 'off');
        end
    end
end
