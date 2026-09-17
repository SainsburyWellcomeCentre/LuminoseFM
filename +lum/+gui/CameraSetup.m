classdef CameraSetup < handle
    % lum.gui.CameraSetup is the Cameras tab of both setup dialogs, with a live preview.
    %
    % It edits S.Camera: whether the session records video, where SpinCam was cloned,
    % the video format, which cameras record under which view name (24226887 sideview,
    % 24226657 topview on this rig), frame rate, exposure and gain, the TTL input logged
    % with every frame, and the camera window shown during the session.
    %
    % Settings are easiest to get right while looking at the picture, so the tab has a
    % preview: **Preview** connects the cameras ticked to record exactly as the session
    % will (lum.dev.configureCameras) and shows them; frame rate, exposure and gain apply
    % live. **Simulated cameras** previews spincam's synthetic cameras instead, for a desk
    % without cameras. **Full viewer...** opens spincam's own LiveViewer on the same
    % cameras, for cropping and the finer controls; when it closes, the crop, names,
    % frame rate, exposure and gain it left are read back into the tab. The cameras are
    % released when the preview stops or the dialog closes, so the session can open them.
    %
    % Usage, inside a dialog:
    %   cameras = lum.gui.CameraSetup(tab, S.Camera, t, @refresh, 'Subject', subject);
    %   S.Camera = cameras.read(S.Camera);    % in collect
    %   cameras.update(S.Camera);             % in the appearance update
    %   note = cameras.problem(S.Camera);     % '' or a note for the status line
    %   cameras.useHelpLine(helpLine);        % after helpLine.registerTooltips()
    %
    % The video format's tooltip, and so the help line, is one sentence on what the format
    % selected does (lum.dev.Cameras.formatDescription), changing with the choice.
    %
    % See also: lum.dev.Cameras, lum.dev.configureCameras, lum.gui.CameraWindow

    properties (SetAccess = private)
        Controls = struct()
        Manager = []          % The preview's spincam.CameraManager, while previewing
        Connected = struct('Serial', {}, 'Name', {}, 'Row', {})
    end

    properties (Access = private)
        onEdit
        theme
        subject
        rois = {}             % One crop per table row, [] for the full frame
        timerObject = []
        images = gobjects(0)
        ticks = 0
        viewer = []
        helpLine = []         % The dialog's lum.gui.HelpLine, once attached
    end

    properties (Constant, Access = private)
        PreviewRate = 10
    end

    methods
        function obj = CameraSetup(parent, camera, t, onEdit, varargin)
            p = inputParser;
            addParameter(p, 'Subject', '');
            parse(p, varargin{:});
            obj.onEdit = onEdit;
            obj.theme = t;
            obj.subject = char(p.Results.Subject);
            obj.rois = {camera.Cameras.Roi};
            obj.build(parent, camera);
            fig = ancestor(parent, 'figure');
            addlistener(fig, 'ObjectBeingDestroyed', @(~, ~) obj.close());
        end

        function camera = read(obj, camera)
            % read(camera) is S.Camera as the tab has it.
            c = obj.Controls;
            camera.Enabled = c.Enabled.Value;
            camera.SpinCamFolder = strtrim(c.Folder.Value);
            camera.Format = c.Format.Value;
            camera.FrameRate = c.FrameRate.Value;
            camera.ExposureAuto = c.ExposureAuto.Value;
            camera.ExposureTime = c.ExposureTime.Value;
            camera.GainAuto = c.GainAuto.Value;
            camera.Gain = c.Gain.Value;
            camera.TtlLine = c.TtlLine.Value;
            camera.ShowWindow = c.ShowWindow.Value;
            camera.WindowRate = c.WindowRate.Value;
            data = c.Table.Data;
            rows = struct('Serial', {}, 'Name', {}, 'Record', {}, 'Roi', {});
            for i = 1:size(data, 1)
                serial = strtrim(char(string(data{i, 1})));
                if isempty(serial)
                    continue
                end
                rows(end+1) = struct('Serial', serial, 'Name', strtrim(char(string(data{i, 2}))), ...
                                     'Record', logical(data{i, 3}), 'Roi', obj.rois{i}); %#ok<AGROW>
            end
            camera.Cameras = rows;
        end

        function update(obj, camera)
            % update(camera) greys out what does not apply and refreshes the notes.
            c = obj.Controls;
            on = camera.Enabled;
            lum.gui.Form.setEnable({c.Folder, c.Browse, c.Format, c.FrameRate, c.ExposureAuto, ...
                                    c.GainAuto, c.TtlLine, c.ShowWindow}, on);
            c.Table.Enable = char(lum.gui.Form.onOff(on));
            lum.gui.Form.setEnable({c.ExposureTime}, on && ~camera.ExposureAuto);
            lum.gui.Form.setEnable({c.Gain}, on && ~camera.GainAuto);
            lum.gui.Form.setEnable({c.WindowRate}, on && camera.ShowWindow);
            obj.describeFormat();

            folder = lum.dev.Cameras.locateSpinCam(camera.SpinCamFolder);
            if isempty(folder)
                c.FolderNote.Text = 'SpinCam not found: choose the folder SpinCam was cloned into.';
                c.FolderNote.FontColor = obj.theme.Bad;
            else
                c.FolderNote.Text = sprintf('SpinCam found in %s', folder);
                c.FolderNote.FontColor = obj.theme.Good;
            end
            recorded = camera.Cameras(arrayfun(@(r) logical(r.Record), camera.Cameras));
            names = arrayfun(@(r) lum.dev.Cameras.cleanName(r.Name), recorded, 'UniformOutput', false);
            subjectName = obj.subject;
            if isempty(subjectName)
                subjectName = '<subject>';
            end
            extension = struct('avi_mjpeg_mt', '.avi', 'avi_mjpeg', '.avi', 'mp4_h264', '.mp4', ...
                               'avi_raw', '.avi', 'raw', '.raw');
            key = strrep(camera.Format, '-', '_');
            ext = '.avi';
            if isfield(extension, key)
                ext = extension.(key);
            end
            if isempty(names)
                c.FilesNote.Text = 'No camera ticked to record.';
            else
                c.FilesNote.Text = sprintf(['Session Videos (beside Session Data):  %s_%s_LuminoseFM_'...
                                            '<date_time>%s and .csv for each of: %s'], names{1}, ...
                                           subjectName, ext, strjoin(names, ', '));
            end
        end

        function useHelpLine(obj, helpLine)
            % useHelpLine(helpLine) lets the tab describe the chosen video format on the
            % dialog's help line. Call it after helpLine.registerTooltips().
            obj.helpLine = helpLine;
            helpLine.register(obj.Controls.Format, obj.Controls.Format.Tooltip);
        end

        function text = problem(obj, camera) %#ok<INUSL> % A method, so the dialogs call it alike
            % problem(camera) is '' or a note for the status line about video that validation
            % cannot give, because it does not look for SpinCam. The format note comes from
            % validation (lum.validateSettings, lum.sleep.validate), so it is not repeated here.
            text = '';
            if camera.Enabled && isempty(lum.dev.Cameras.locateSpinCam(camera.SpinCamFolder))
                text = ['Video recording is on but SpinCam was not found; set its folder on the '...
                        'Cameras tab (on the rig the session will not start without it).'];
            end
        end

        function startPreview(obj)
            % startPreview() connects the cameras the settings ask for and shows them.
            obj.stopPreview();
            camera = obj.read(struct());
            folder = lum.dev.Cameras.locateSpinCam(camera.SpinCamFolder);
            if isempty(folder)
                obj.say('SpinCam not found: set its folder first.', true);
                obj.Controls.Preview.Value = false;
                return
            end
            if isempty(which('spincam.CameraManager'))
                addpath(folder);
            end
            obj.say('Connecting...', false);
            drawnow;
            try
                options = {};
                if obj.Controls.Simulated.Value
                    nRecorded = max(1, sum(arrayfun(@(r) r.Record, camera.Cameras)));
                    options = {'Backend', 'mock', 'NumCameras', nRecorded, 'Resolution', [512 640]};
                end
                obj.Manager = spincam.CameraManager('FrameRate', camera.FrameRate, options{:});
                obj.Connected = lum.dev.configureCameras(obj.Manager, camera, 'Strict', false, ...
                                                         'PreviewRate', obj.PreviewRate);
                obj.Manager.startPreview();
            catch previewError
                obj.releaseManager();
                obj.Controls.Preview.Value = false;
                obj.say(sprintf('Preview failed: %s', previewError.message), true);
                return
            end
            obj.buildTiles();
            obj.Controls.Preview.Value = true;
            obj.Controls.Preview.Text = 'Stop preview';
            obj.Controls.FullViewer.Enable = 'on';
            obj.say(sprintf('Previewing %s.', strjoin(arrayfun(@(k) sprintf('%s (%s)', ...
                obj.Connected(k).Name, obj.Connected(k).Serial), 1:numel(obj.Connected), ...
                'UniformOutput', false), ', ')), false);
            obj.startTimer();
        end

        function stopPreview(obj)
            % stopPreview() stops showing the cameras and releases them.
            obj.stopTimer();
            obj.closeViewer();
            obj.releaseManager();
            if isfield(obj.Controls, 'Preview') && isvalid(obj.Controls.Preview)
                obj.Controls.Preview.Value = false;
                obj.Controls.Preview.Text = 'Preview';
                obj.Controls.FullViewer.Enable = 'off';
            end
        end

        function refreshPreview(obj)
            % refreshPreview() draws the latest frames; the preview timer calls it.
            if isempty(obj.Manager) || ~isvalid(obj.Manager)
                obj.stopTimer();
                return
            end
            try
                frames = obj.Manager.getLatestFrames();
                for k = 1:min(numel(frames), numel(obj.images))
                    frame = frames{k};
                    if isempty(frame) || ~isvalid(obj.images(k))
                        continue
                    end
                    if size(frame, 2) > 640
                        frame = frame(1:2:end, 1:2:end);
                    end
                    obj.images(k).CData = frame;
                    ax = obj.images(k).Parent;
                    if ~isequal(ax.XLim, [0.5 size(frame, 2) + 0.5])
                        ax.XLim = [0.5 size(frame, 2) + 0.5];
                        ax.YLim = [0.5 size(frame, 1) + 0.5];
                    end
                end
                obj.ticks = obj.ticks + 1;
                if mod(obj.ticks, obj.PreviewRate) == 1
                    T = obj.Manager.getStats();
                    parts = arrayfun(@(k) sprintf('%s %.1f fps, %d missed, TTL %g', T.Name{k}, ...
                                                  T.FPS(k), T.FramesMissed(k), T.LastTTL(k)), ...
                                     1:height(T), 'UniformOutput', false);
                    obj.say(strjoin(parts, '   |   '), false);
                end
                drawnow limitrate
            catch refreshError
                obj.stopTimer();
                obj.say(sprintf('Preview stopped: %s', refreshError.message), true);
            end
        end

        function close(obj)
            % close() stops the preview and releases the cameras.
            obj.stopPreview();
        end

        function delete(obj)
            obj.close();
        end
    end

    methods (Access = private)
        function build(obj, parent, camera)
            t = obj.theme;
            height = @lum.gui.Form.panelHeight;
            grid = uigridlayout(parent, [1 2], 'ColumnWidth', {460, '1x'}, 'Padding', 12, ...
                                'ColumnSpacing', 12, 'BackgroundColor', t.Background);
            left = uigridlayout(grid, [5 1], 'RowHeight', {height(5) + 18, 200, height(4), ...
                                height(2), '1x'}, 'Padding', 0, 'RowSpacing', 10, ...
                                'BackgroundColor', t.Background, 'Scrollable', 'on');

            form = lum.gui.Form.panel(left, 'Recording', 5, t, 130);
            form.RowHeight = {26, 26, 22, 26, 44};
            uilabel(form, 'Text', '');
            c.Enabled = uicheckbox(form, 'Text', 'Record video', 'Value', camera.Enabled, ...
                'ValueChangedFcn', @(~, ~) obj.onEdit(), ...
                'Tooltip', ['Record every camera ticked below for the whole session, into Session '...
                            'Videos beside Session Data. Untick to run without video.']);
            lum.gui.Form.label(form, 'SpinCam folder', t);
            row = uigridlayout(form, [1 2], 'ColumnWidth', {'1x', 80}, 'Padding', 0, ...
                               'ColumnSpacing', 6, 'BackgroundColor', t.Panel);
            c.Folder = uieditfield(row, 'text', 'Value', char(camera.SpinCamFolder), ...
                'ValueChangedFcn', @(~, ~) obj.onEdit(), ...
                'Tooltip', ['The folder SpinCam was cloned into (it holds +spincam). Leave empty '...
                            'when SpinCam is already on the MATLAB path.']);
            c.Browse = uibutton(row, 'Text', ['Browse' char(8230)], 'ButtonPushedFcn', @(~, ~) obj.browse(), ...
                'Tooltip', 'Choose the SpinCam folder');
            uilabel(form, 'Text', '');
            c.FolderNote = uilabel(form, 'Text', '', 'FontSize', 11);
            lum.gui.Form.label(form, 'Video format', t);
            c.Format = uidropdown(form, 'Items', lum.dev.Cameras.Formats, 'Value', camera.Format, ...
                'ValueChangedFcn', @(~, ~) obj.formatChanged(), ...
                'Tooltip', lum.dev.Cameras.formatDescription(camera.Format));
            lum.gui.Form.label(form, 'Files', t);
            c.FilesNote = lum.gui.Form.note(form, '', t);

            box = uipanel(left, 'Title', 'Cameras', 'FontWeight', 'bold', ...
                          'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
            inner = uigridlayout(box, [2 1], 'RowHeight', {'1x', 28}, 'Padding', [10 8 10 8], ...
                                 'RowSpacing', 6, 'BackgroundColor', t.Panel);
            c.Table = uitable(inner, 'ColumnName', {'Serial', 'View (file prefix)', 'Record', 'Crop'}, ...
                'ColumnEditable', [true true true false], 'ColumnWidth', {90, 'auto', 60, 110}, ...
                'ColumnFormat', {'char', 'char', 'logical', 'char'}, ...
                'CellEditCallback', @(~, ~) obj.onEdit(), ...
                'Tooltip', ['One row per camera, by serial number. The view names the files: '...
                            'sideview_<session>.avi. Tick Record for each camera the session records.']);
            c.Table.Data = obj.tableData(camera.Cameras);
            buttons = uigridlayout(inner, [1 3], 'ColumnWidth', {'1x', '1x', '1x'}, 'Padding', 0, ...
                                   'ColumnSpacing', 6, 'BackgroundColor', t.Panel);
            c.FindCameras = uibutton(buttons, 'Text', 'Find attached', ...
                'ButtonPushedFcn', @(~, ~) obj.findAttached(), ...
                'Tooltip', 'Add a row for every attached camera not yet listed');
            c.AddRow = uibutton(buttons, 'Text', 'Add row', 'ButtonPushedFcn', @(~, ~) obj.addRow(), ...
                'Tooltip', 'Add an empty row to type a serial number into');
            c.FullFrame = uibutton(buttons, 'Text', 'Full frame', ...
                'ButtonPushedFcn', @(~, ~) obj.fullFrame(), ...
                'Tooltip', 'Clear every crop: record the whole sensor');

            form = lum.gui.Form.panel(left, 'Image', 4, t, 130);
            lum.gui.Form.label(form, 'Frame rate (Hz)', t);
            c.FrameRate = uieditfield(form, 'numeric', 'Value', camera.FrameRate, ...
                'Limits', [1 lum.dev.Cameras.MaxFrameRate], 'ValueChangedFcn', @(~, ~) obj.imageEdited(), ...
                'Tooltip', ['Frames per second, the same for every camera. Two full-frame cameras on '...
                            'the one USB controller deliver up to 120 Hz; above that, crop in the full viewer.']);
            lum.gui.Form.label(form, 'Exposure (us)', t);
            row = uigridlayout(form, [1 2], 'ColumnWidth', {70, '1x'}, 'Padding', 0, ...
                               'ColumnSpacing', 6, 'BackgroundColor', t.Panel);
            c.ExposureAuto = uicheckbox(row, 'Text', 'Auto', 'Value', camera.ExposureAuto, ...
                'ValueChangedFcn', @(~, ~) obj.imageEdited(), ...
                'Tooltip', 'Let the camera choose the exposure continuously');
            c.ExposureTime = uieditfield(row, 'numeric', 'Value', camera.ExposureTime, ...
                'Limits', [1 1e6], 'ValueChangedFcn', @(~, ~) obj.imageEdited(), ...
                'Tooltip', 'Manual exposure in microseconds; it must be shorter than one frame (10000 at 100 Hz).');
            lum.gui.Form.label(form, 'Gain (dB)', t);
            row = uigridlayout(form, [1 2], 'ColumnWidth', {70, '1x'}, 'Padding', 0, ...
                               'ColumnSpacing', 6, 'BackgroundColor', t.Panel);
            c.GainAuto = uicheckbox(row, 'Text', 'Auto', 'Value', camera.GainAuto, ...
                'ValueChangedFcn', @(~, ~) obj.imageEdited(), ...
                'Tooltip', 'Let the camera choose the gain continuously');
            c.Gain = uieditfield(row, 'numeric', 'Value', camera.Gain, 'Limits', [0 48], ...
                'ValueChangedFcn', @(~, ~) obj.imageEdited(), 'Tooltip', 'Manual gain in dB');
            lum.gui.Form.label(form, 'TTL input', t);
            c.TtlLine = uidropdown(form, 'Items', lum.dev.Cameras.TtlLines, 'Value', camera.TtlLine, ...
                'ValueChangedFcn', @(~, ~) obj.onEdit(), ...
                'Tooltip', ['The camera input logged with every frame (passive TTL logging). Line0 is '...
                            'the yellow (signal) and brown (ground) wires. Wire Bpod''s sync line here '...
                            'to see the barcode and trial pulses frame by frame.']);

            form = lum.gui.Form.panel(left, 'During the session', 2, t, 130);
            lum.gui.Form.label(form, 'Camera window', t);
            c.ShowWindow = uicheckbox(form, 'Text', 'Show the cameras', 'Value', camera.ShowWindow, ...
                'ValueChangedFcn', @(~, ~) obj.onEdit(), ...
                'Tooltip', ['A window with every camera and its frame rate, missed frames and TTL, '...
                            'while the session runs. Closing it does not stop the recording.']);
            lum.gui.Form.label(form, 'Refresh (Hz)', t);
            c.WindowRate = uieditfield(form, 'numeric', 'Value', camera.WindowRate, ...
                'Limits', [0.5 lum.dev.Cameras.MaxWindowRate], 'ValueChangedFcn', @(~, ~) obj.onEdit(), ...
                'Tooltip', ['How often the camera window redraws. Each redraw copies one frame per '...
                            'camera into MATLAB, so keep it low (5) during a session.']);

            lum.gui.Form.note(left, ['SpinCam records on native threads of its own, so the video never '...
                                     'waits for Bpod and Bpod never waits for the video. Every frame''s '...
                                     'row in the .csv has its camera timestamp (HardwareTimestamp_us), '...
                                     'its host time in seconds (HostTime_s, the clock of '...
                                     'Data.CameraTime) and the TTL input state (TTL_State), which carries '...
                                     'the session barcode and trial pulses from Bpod''s sync line.'], t);

            box = uipanel(grid, 'Title', 'Live preview', 'FontWeight', 'bold', ...
                          'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
            right = uigridlayout(box, [3 1], 'RowHeight', {30, 40, '1x'}, 'Padding', [10 8 10 8], ...
                                 'RowSpacing', 6, 'BackgroundColor', t.Panel);
            row = uigridlayout(right, [1 3], 'ColumnWidth', {140, 170, 150}, 'Padding', 0, ...
                               'ColumnSpacing', 8, 'BackgroundColor', t.Panel);
            c.Preview = uibutton(row, 'state', 'Text', 'Preview', 'FontWeight', 'bold', ...
                'ValueChangedFcn', @(source, ~) obj.previewToggled(source.Value), ...
                'Tooltip', ['Connect the cameras ticked to record, set up as the session will record '...
                            'them, and show them. Released when stopped or when the dialog closes.']);
            c.Simulated = uicheckbox(row, 'Text', 'Simulated cameras', 'Value', false, ...
                'Tooltip', 'Preview SpinCam''s synthetic cameras, on a computer without cameras');
            c.FullViewer = uibutton(row, 'Text', ['Full viewer' char(8230)], 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) obj.openViewer(), ...
                'Tooltip', ['SpinCam''s own viewer on the same cameras: crop, black level and more. '...
                            'What it leaves is read back here when it closes.']);
            c.PreviewStatus = uilabel(right, 'Text', 'Not previewing.', 'WordWrap', 'on', ...
                                      'FontSize', 11, 'FontColor', t.Muted);
            c.Tiles = uigridlayout(right, [1 2], 'Padding', 0, 'ColumnSpacing', 8, ...
                                   'BackgroundColor', t.Panel);
            obj.Controls = c;
        end

        function data = tableData(obj, rows)
            data = cell(numel(rows), 4);
            for i = 1:numel(rows)
                data(i, :) = {char(rows(i).Serial), char(rows(i).Name), logical(rows(i).Record), ...
                              cropText(obj.rois{i})};
            end
        end

        function refreshTable(obj)
            data = obj.Controls.Table.Data;
            for i = 1:size(data, 1)
                data{i, 4} = cropText(obj.rois{i});
            end
            obj.Controls.Table.Data = data;
        end

        function browse(obj)
            start = obj.Controls.Folder.Value;
            if ~isfolder(start)
                start = pwd;
            end
            folder = uigetdir(start, 'Choose the folder SpinCam was cloned into');
            fig = ancestor(obj.Controls.Folder, 'figure');
            if isvalid(fig)
                figure(fig);
            end
            if ischar(folder)
                obj.Controls.Folder.Value = folder;
                obj.onEdit();
            end
        end

        function addRow(obj)
            obj.Controls.Table.Data(end+1, :) = {'', '', false, cropText([])};
            obj.rois{end+1} = [];
            obj.onEdit();
        end

        function fullFrame(obj)
            obj.rois = cell(1, size(obj.Controls.Table.Data, 1));
            obj.refreshTable();
            obj.onEdit();
        end

        function findAttached(obj)
            camera = obj.read(struct());
            folder = lum.dev.Cameras.locateSpinCam(camera.SpinCamFolder);
            if isempty(folder)
                obj.say('SpinCam not found: set its folder first.', true);
                return
            end
            if isempty(which('spincam.CameraManager'))
                addpath(folder);
            end
            try
                manager = obj.Manager;
                owned = isempty(manager);
                if owned
                    manager = spincam.CameraManager('FrameRate', []);
                end
                attached = manager.listCameras();
                if owned
                    delete(manager);
                end
            catch listError
                obj.say(sprintf('Could not list cameras: %s', listError.message), true);
                return
            end
            known = obj.Controls.Table.Data(:, 1);
            added = 0;
            for i = 1:height(attached)
                serial = char(attached.Serial{i});
                if ~any(strcmp(known, serial))
                    obj.Controls.Table.Data(end+1, :) = {serial, ['cam' serial], false, cropText([])};
                    obj.rois{end+1} = [];
                    added = added + 1;
                end
            end
            obj.say(sprintf('%d camera(s) attached, %d added.', height(attached), added), false);
            obj.onEdit();
        end

        function formatChanged(obj)
            % The help line shows the old description before this runs (it chains the
            % callback), so the one for the format just chosen replaces it here.
            obj.describeFormat();
            if ~isempty(obj.helpLine) && isvalid(obj.helpLine)
                obj.helpLine.describe(obj.Controls.Format);
            end
            obj.onEdit();
        end

        function describeFormat(obj)
            % The format's tooltip and help-line text describe the format selected.
            format = obj.Controls.Format;
            text = lum.dev.Cameras.formatDescription(format.Value);
            if strcmp(char(format.Tooltip), text)
                return
            end
            format.Tooltip = text;
            if ~isempty(obj.helpLine) && isvalid(obj.helpLine)
                obj.helpLine.register(format, text);
            end
        end

        function previewToggled(obj, on)
            if on
                obj.startPreview();
            else
                obj.stopPreview();
                obj.say('Not previewing.', false);
            end
        end

        function imageEdited(obj)
            % Frame rate, exposure and gain apply to a running preview straight away.
            obj.onEdit();
            if isempty(obj.Manager) || ~isvalid(obj.Manager)
                return
            end
            camera = obj.read(struct());
            try
                serials = {obj.Connected.Serial};
                if camera.ExposureAuto
                    obj.Manager.setProperty('FrameRate', camera.FrameRate, serials);
                    obj.Manager.setProperty('ExposureAuto', 'Continuous', serials);
                else
                    obj.Manager.setProperty('ExposureTime', min(camera.ExposureTime, ...
                                            floor(0.99e6 / camera.FrameRate)), serials);
                    obj.Manager.setProperty('FrameRate', camera.FrameRate, serials);
                end
                if camera.GainAuto
                    obj.Manager.setProperty('GainAuto', 'Continuous', serials);
                else
                    obj.Manager.setProperty('Gain', camera.Gain, serials);
                end
            catch applyError
                obj.say(sprintf('Could not apply: %s', applyError.message), true);
            end
        end

        function openViewer(obj)
            if isempty(obj.Manager) || ~isvalid(obj.Manager)
                return
            end
            obj.stopTimer();
            try
                obj.viewer = spincam.LiveViewer(obj.Manager);
                addlistener(obj.viewer, 'ObjectBeingDestroyed', @(~, ~) obj.viewerClosed());
                obj.say('The full viewer is open; its settings come back here when it closes.', false);
            catch viewerError
                obj.say(sprintf('Could not open the viewer: %s', viewerError.message), true);
                obj.startTimer();
            end
        end

        function viewerClosed(obj)
            % Read back what the viewer left in the cameras.
            obj.viewer = [];
            if isempty(obj.Manager) || ~isvalid(obj.Manager) || ~isvalid(obj.Controls.Table)
                return
            end
            try
                c = obj.Controls;
                first = obj.Connected(1).Serial;
                % The camera quantizes the frame rate (100 reads back 100.058), and writing a
                % read-back value lands one step higher. Keep the typed rate unless the viewer
                % really changed it.
                rate = obj.Manager.getProperty('FrameRate', {first});
                if abs(rate - c.FrameRate.Value) > 0.2
                    c.FrameRate.Value = min(max(round(rate, 1), 1), lum.dev.Cameras.MaxFrameRate);
                end
                c.ExposureAuto.Value = ~strcmpi(obj.Manager.getProperty('ExposureAuto', {first}), 'Off');
                c.ExposureTime.Value = round(obj.Manager.getProperty('ExposureTime', {first}));
                c.GainAuto.Value = ~strcmpi(obj.Manager.getProperty('GainAuto', {first}), 'Off');
                c.Gain.Value = min(max(obj.Manager.getProperty('Gain', {first}), 0), 48);
                simulated = strcmp(obj.Manager.Backend, 'mock');
                for k = 1:numel(obj.Connected)
                    row = obj.Connected(k).Row;
                    device = obj.Manager.camera(obj.Connected(k).Serial);
                    c.Table.Data{row, 2} = device.Name;
                    if ~simulated
                        roi = obj.Manager.getRoi({obj.Connected(k).Serial});
                        full = device.sensorSize();
                        if isequal(roi, [0 0 full])
                            roi = [];
                        end
                        obj.rois{row} = roi;
                    end
                end
                obj.refreshTable();
                obj.onEdit();
                if strcmp(obj.Manager.State, 'idle')
                    obj.Manager.startPreview();
                end
                obj.startTimer();
                obj.say('Read back the viewer''s settings.', false);
            catch readError
                obj.say(sprintf('Could not read the viewer''s settings back: %s', readError.message), true);
            end
        end

        function buildTiles(obj)
            delete(obj.Controls.Tiles.Children);
            n = numel(obj.Connected);
            obj.Controls.Tiles.ColumnWidth = repmat({'1x'}, 1, max(n, 1));
            obj.images = gobjects(1, n);
            for k = 1:n
                ax = uiaxes(obj.Controls.Tiles, 'Color', obj.theme.Ink);
                ax.Toolbar.Visible = 'off';
                disableDefaultInteractivity(ax);
                obj.images(k) = image(ax, zeros(2, 2, 'uint8'), 'CDataMapping', 'scaled');
                colormap(ax, gray(256));
                clim(ax, [0 255]);
                axis(ax, 'image');
                ax.XTick = [];
                ax.YTick = [];
                title(ax, sprintf('%s  ·  %s', obj.Connected(k).Name, obj.Connected(k).Serial), ...
                      'Interpreter', 'none', 'FontWeight', 'normal', 'FontSize', 11);
            end
        end

        function startTimer(obj)
            obj.stopTimer();
            obj.timerObject = timer('Name', 'LuminoseFM camera preview', 'ExecutionMode', 'fixedSpacing', ...
                                    'BusyMode', 'drop', 'Period', 1 / obj.PreviewRate, ...
                                    'TimerFcn', @(~, ~) obj.refreshPreview());
            start(obj.timerObject);
        end

        function stopTimer(obj)
            if ~isempty(obj.timerObject) && isvalid(obj.timerObject)
                stop(obj.timerObject);
                delete(obj.timerObject);
            end
            obj.timerObject = [];
        end

        function closeViewer(obj)
            if ~isempty(obj.viewer) && isvalid(obj.viewer)
                openViewer = obj.viewer;
                obj.viewer = [];
                delete(openViewer);
            end
        end

        function releaseManager(obj)
            if ~isempty(obj.Manager) && isvalid(obj.Manager)
                try
                    delete(obj.Manager);
                catch releaseError
                    warning('lum:gui:CameraSetup:releaseFailed', 'Releasing the cameras: %s', ...
                            releaseError.message);
                end
            end
            obj.Manager = [];
            obj.Connected = struct('Serial', {}, 'Name', {}, 'Row', {});
        end

        function say(obj, text, isError)
            if ~isfield(obj.Controls, 'PreviewStatus') || ~isvalid(obj.Controls.PreviewStatus)
                return
            end
            obj.Controls.PreviewStatus.Text = text;
            if isError
                obj.Controls.PreviewStatus.FontColor = obj.theme.Bad;
            else
                obj.Controls.PreviewStatus.FontColor = obj.theme.Muted;
            end
        end
    end
end


function text = cropText(roi)
% 'full frame' or 'x,y wxh'.
if isempty(roi)
    text = 'full frame';
else
    text = sprintf('%d,%d %dx%d', roi(1), roi(2), roi(3), roi(4));
end
end
