classdef CameraWindow < handle
    % lum.gui.CameraWindow shows the session's cameras while it runs.
    %
    % One tile per camera: the latest frame, its view and serial, and a line of health
    % figures — frames per second, frames missed by the camera, frames written, writer
    % drops, and the TTL input of the latest frame (a quick check that the sync line
    % reaches the camera).
    %
    % It is built to cost the session as little as possible. Recording never passes
    % through it: spincam's engine grabs, encodes and logs on its own threads. The window
    % reads one preview frame per camera S.Camera.WindowRate times a second (5 by
    % default) from a timer, which the engine keeps ready at that rate and no faster;
    % halves large frames before drawing; updates existing image handles; and draws with
    % drawnow limitrate nocallbacks. The statistics are read once a second. Closing the
    % window stops the timer and nothing else: recording carries on.
    %
    % Stopping from the console. The window is not one of Bpod's protocol figures: the
    % console's End button runs RunProtocol('Stop') from its callback, and a Stop that
    % closed this window could run inside the timer's own callback (a drawnow that
    % processes callbacks lets the button in) and stop the timer from within it, which
    % froze MATLAB on the rig (2026-09-22). So the timer's drawnow processes no
    % callbacks, the protocol's teardown closes the window, and the timer runs through
    % a function of this file that stops it, and closes the window, if the window
    % cannot be refreshed for any reason, the class gone from the path included.
    %
    % Usage:
    %   window = lum.gui.CameraWindow(devices.cameras, S.Camera, 'Subject', subject);
    %   window.close();    % in teardown, before RunProtocol('Stop')
    %
    % See also: lum.dev.Cameras, lum.gui.CameraSetup

    properties (SetAccess = private)
        Figure = []
    end

    properties (Access = private)
        cameras          % lum.dev.Cameras
        timerObject = []
        images = gobjects(0)
        titles = gobjects(0)
        details = gobjects(0)
        ticks = 0
        rate
    end

    methods
        function obj = CameraWindow(cameras, camera, varargin)
            p = inputParser;
            addParameter(p, 'Subject', '', @(x) ischar(x) || isstring(x));
            addParameter(p, 'Visible', 'on');
            addParameter(p, 'StartTimer', true);
            parse(p, varargin{:});

            obj.cameras = cameras;
            obj.rate = camera.WindowRate;
            if ~cameras.canPreview()
                return
            end
            [~, info] = cameras.latestFrames();
            obj.build(info, char(p.Results.Subject), p.Results.Visible);
            if p.Results.StartTimer
                obj.timerObject = timer('Name', 'LuminoseFM camera window', ...
                                        'ExecutionMode', 'fixedSpacing', 'BusyMode', 'drop', ...
                                        'Period', max(round(1000 / obj.rate) / 1000, 0.033));
                obj.timerObject.TimerFcn = @(source, ~) tick(source, obj, obj.Figure);
                % Whoever deletes the figure, the timer stops with it.
                obj.Figure.DeleteFcn = @(~, ~) stopQuietly(obj.timerObject);
                start(obj.timerObject);
            end
        end

        function refresh(obj)
            % refresh() draws the latest frames, and once a second the statistics.
            if isempty(obj.Figure) || ~isvalid(obj.Figure)
                obj.stopTimer();
                return
            end
            try
                frames = obj.cameras.latestFrames();
                for k = 1:min(numel(frames), numel(obj.images))
                    frame = frames{k};
                    if isempty(frame)
                        continue
                    end
                    if size(frame, 2) > 640
                        frame = frame(1:2:end, 1:2:end);
                    end
                    set(obj.images(k), 'CData', frame);
                end
                obj.ticks = obj.ticks + 1;
                if mod(obj.ticks, max(1, round(obj.rate))) == 1 || obj.rate < 1
                    obj.showStatistics();
                end
                drawnow limitrate nocallbacks  % Never the End button inside this callback
            catch refreshError
                % The session matters more than its preview: say why, and stop looking.
                obj.stopTimer();
                if ~isempty(obj.details) && isvalid(obj.details(1))
                    set(obj.details(1), 'String', sprintf('Preview stopped: %s', refreshError.message));
                end
            end
        end

        function close(obj)
            % close() stops the preview and closes the window; recording carries on.
            obj.stopTimer();
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                delete(obj.Figure);
            end
            obj.Figure = [];
        end

        function delete(obj)
            obj.close();
        end
    end

    methods (Access = private)
        function build(obj, info, subject, visible)
            t = lum.gui.theme();
            n = numel(info);
            tileWidth = 480;
            tileHeight = 400;
            obj.Figure = figure('Name', 'LuminoseFM - cameras', 'NumberTitle', 'off', ...
                                'MenuBar', 'none', 'ToolBar', 'none', 'Color', t.Background, ...
                                'Visible', visible, 'Position', [520 80 n * tileWidth + 20 tileHeight + 30], ...
                                'CloseRequestFcn', @(source, ~) closeRequested(source, obj));
            heading = 'Cameras: recording';
            if ~isempty(subject)
                heading = sprintf('%s  |  %s', heading, subject);
            end
            uicontrol(obj.Figure, 'Style', 'text', 'String', heading, 'Units', 'normalized', ...
                      'Position', [0.01 0.93 0.98 0.06], 'FontSize', 11, 'FontWeight', 'bold', ...
                      'HorizontalAlignment', 'left', 'BackgroundColor', t.Background, ...
                      'ForegroundColor', t.Ink);
            obj.images = gobjects(1, n);
            obj.titles = gobjects(1, n);
            obj.details = gobjects(1, n);
            for k = 1:n
                left = (k - 1) / n;
                ax = axes('Parent', obj.Figure, 'Units', 'normalized', ...
                          'Position', [left + 0.01, 0.12, 1 / n - 0.02, 0.76], 'Color', t.Ink);
                obj.images(k) = image(ax, zeros(2, 2, 'uint8'), 'CDataMapping', 'scaled');
                colormap(ax, gray(256));
                clim(ax, [0 255]);
                axis(ax, 'image', 'off');
                obj.titles(k) = title(ax, sprintf('%s  ·  %s', info(k).Name, info(k).Serial), ...
                                      'Color', t.Ink, 'FontSize', 10, 'Interpreter', 'none');
                obj.details(k) = uicontrol(obj.Figure, 'Style', 'text', 'String', 'starting...', ...
                                           'Units', 'normalized', ...
                                           'Position', [left + 0.01, 0.01, 1 / n - 0.02, 0.09], ...
                                           'FontSize', 9, 'HorizontalAlignment', 'left', ...
                                           'BackgroundColor', t.Background, 'ForegroundColor', t.Muted);
            end
        end

        function showStatistics(obj)
            stats = obj.cameras.statistics();
            t = lum.gui.theme();
            for k = 1:min(numel(stats), numel(obj.details))
                s = stats(k);
                text = sprintf('%.1f fps  |  missed %d  |  written %d  |  writer drops %d  |  TTL %s', ...
                               s.FPS, s.FramesMissed, s.FramesWritten, s.WriterDrops, ttlText(s.LastTTL));
                colour = t.Muted;
                if s.Faulted || ~isempty(s.LastError)
                    text = sprintf('ERROR: %s', s.LastError);
                    colour = t.Bad;
                elseif s.FramesMissed > 0 || s.WriterDrops > 0
                    colour = t.Warn;
                end
                set(obj.details(k), 'String', text, 'ForegroundColor', colour);
            end
        end

        function stopTimer(obj)
            stopQuietly(obj.timerObject);
            obj.timerObject = [];
        end
    end
end


function tick(timerObject, window, figureHandle)
% The timer's callback. Anything that stops the window refreshing, including its class
% no longer being on the path once RunProtocol('Stop') has removed the protocol folder,
% stops the timer and closes the figure, using nothing but built-ins.
try
    window.refresh();
catch
    stopQuietly(timerObject);
    if isgraphics(figureHandle)
        delete(figureHandle);
    end
end
end


function closeRequested(figureHandle, window)
% The window's close box: close() normally, and the figure alone if that cannot run.
try
    window.close();
catch
    delete(figureHandle);
end
end


function stopQuietly(timerObject)
% Stop and delete a timer, whatever state it is in.
try
    if ~isempty(timerObject) && isvalid(timerObject)
        stop(timerObject);
        delete(timerObject);
    end
catch
end
end


function text = ttlText(value)
% 'high', 'low' or '-'.
if isnan(value) || value < 0
    text = '-';
elseif value > 0
    text = 'high';
else
    text = 'low';
end
end
