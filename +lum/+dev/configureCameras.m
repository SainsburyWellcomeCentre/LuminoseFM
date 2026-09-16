function connected = configureCameras(manager, camera, varargin)
% lum.dev.configureCameras connects and sets up the cameras S.Camera asks for.
%
% One definition of how the settings become camera state, used by the session
% (lum.dev.openCameras) and by the setup dialog's live preview (lum.gui.CameraSetup), so
% the preview shows what the session will record. For each camera ticked to record in
% S.Camera.Cameras: connect it, give it its view name (the file-name prefix), crop it
% (an empty crop is the full frame, so a crop left in a camera by an earlier session is
% not carried over silently), set the frame rate, exposure and gain, and log the TTL
% input passively; then set the recorder's format, with the extended frame log and no
% date appended to file names (the data file's name already has one).
%
% With spincam's simulated cameras (the emulator), the rows are given the simulated
% cameras in order, whatever their serial numbers.
%
% Arguments:
%   manager  A spincam.CameraManager, or anything with its interface (tests)
%   camera   S.Camera
%
% Options:
%   'Strict'       true (default) to refuse when a camera ticked to record is not
%                  attached; false to connect what is there (the preview)
%   'PreviewRate'  Preview frames per second kept for display; 0 keeps none (default)
%
% Returns a struct array, one element per connected camera: Serial, Name, Row (its
% index in S.Camera.Cameras).
%
% See also: lum.dev.openCameras, lum.dev.RealCameras, lum.gui.CameraSetup

p = inputParser;
addParameter(p, 'Strict', true);
addParameter(p, 'PreviewRate', 0);
parse(p, varargin{:});

rows = camera.Cameras;
recordRows = reshape(find(arrayfun(@(r) logical(r.Record), rows)), 1, []);
attached = manager.listCameras();
attachedSerials = reshape(cellstr(attached.Serial), 1, []);

%% Which physical camera each row is
serials = cell(1, numel(recordRows));
if strcmp(manager.Backend, 'mock')
    n = min(numel(recordRows), numel(attachedSerials));
    recordRows = recordRows(1:n);
    serials = attachedSerials(1:n);
else
    for i = 1:numel(recordRows)
        serials{i} = strtrim(char(rows(recordRows(i)).Serial));
    end
    present = ismember(serials, attachedSerials);
    if p.Results.Strict && ~all(present)
        missing = arrayfun(@(k) sprintf('%s (%s)', serials{k}, rows(recordRows(k)).Name), ...
                           find(~present), 'UniformOutput', false);
        error('lum:dev:configureCameras:notAttached', ...
              ['Camera %s is ticked to record but is not attached (attached: %s). Check its USB '...
               'cable, close SpinView, or untick it on the Cameras tab.'], ...
              strjoin(missing, ', '), listText(attachedSerials));
    end
    recordRows = recordRows(present);
    serials = serials(present);
end
if isempty(serials)
    error('lum:dev:configureCameras:noCameras', ...
          'No camera ticked to record is attached (attached: %s).', listText(attachedSerials));
end

%% Connect and name
manager.DefaultFrameRate = camera.FrameRate;
manager.connect(serials);
names = arrayfun(@(k) lum.dev.Cameras.cleanName(rows(k).Name), recordRows, 'UniformOutput', false);
% Through placeholder names first, so a camera can take the name another one was
% given by default when it connected.
for i = 1:numel(serials)
    manager.setCameraName(serials{i}, ['cam' serials{i}]);
end
for i = 1:numel(serials)
    manager.setCameraName(serials{i}, names{i});
end

%% Image
for i = 1:numel(serials)
    roi = rows(recordRows(i)).Roi;
    if isempty(roi)
        manager.resetRoi(serials(i));
    else
        manager.setRoi(double(roi(:)'), serials(i));
    end
end
rate = camera.FrameRate;
if camera.ExposureAuto
    manager.setProperty('FrameRate', rate, serials);
    trySet(manager, 'ExposureAuto', 'Continuous', serials);
else
    % The camera caps the frame rate by the exposure, so a shorter exposure goes first.
    trySet(manager, 'ExposureTime', min(camera.ExposureTime, floor(0.99e6 / rate)), serials);
    manager.setProperty('FrameRate', rate, serials);
end
if camera.GainAuto
    trySet(manager, 'GainAuto', 'Continuous', serials);
else
    trySet(manager, 'Gain', camera.Gain, serials);
end

%% Frame log and files
manager.configureSync('passive', 'TtlLine', camera.TtlLine);
manager.Recorder.Format = camera.Format;
manager.Recorder.CsvExtended = true;
manager.AppendDateTime = false;
manager.PreviewMaxHz = p.Results.PreviewRate;

connected = struct('Serial', serials, 'Name', names, 'Row', num2cell(recordRows));


function trySet(manager, name, value, serials)
% A property some cameras may not offer: warn, and record with the camera's own value.
try
    manager.setProperty(name, value, serials);
catch setError
    warning('lum:dev:configureCameras:property', 'Could not set %s on the cameras: %s', ...
            name, setError.message);
end


function text = listText(serials)
% 'none' or the serial numbers.
if isempty(serials)
    text = 'none';
else
    text = strjoin(serials, ', ');
end
