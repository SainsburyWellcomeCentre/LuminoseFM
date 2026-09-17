function cameras = openCameras(emulated, S)
% lum.dev.openCameras connects the session's cameras, or explains why there are none.
%
% Called by lum.dev.open. Recording switched off (S.Camera.Enabled) gives the null
% shim. Otherwise spincam is found (S.Camera.SpinCamFolder, or already on the MATLAB
% path) and put on the path, and a spincam.CameraManager is set up by
% lum.dev.configureCameras and checked by starting and stopping its streams once, so a
% camera held by SpinView or another MATLAB is found now rather than when recording
% starts.
%
% On the rig a session that asks for video refuses to start without it, as a light
% session does without PulsePal: a session that runs but records nothing is only
% discovered afterwards. In the emulator the cameras are spincam's simulated ones
% ('mock' backend: synthetic frames through the real engine, so files and the camera
% window still work), and anything missing degrades to the null shim with a warning.
%
% Arguments:
%   emulated  True when Bpod is running as an emulator (from lum.dev.open)
%   S         Settings struct
%
% Returns a lum.dev.RealCameras or lum.dev.NullCameras.
%
% See also: lum.dev.open, lum.dev.configureCameras, lum.dev.Cameras

camera = S.Camera;
if ~camera.Enabled
    cameras = lum.dev.NullCameras(camera, 'recording switched off for this session');
    return
end

folder = lum.dev.Cameras.locateSpinCam(camera.SpinCamFolder);
if isempty(folder)
    where = '';
    if ~isempty(strtrim(char(camera.SpinCamFolder)))
        where = sprintf(' in %s', camera.SpinCamFolder);
    end
    if emulated
        cameras = lum.dev.NullCameras(camera, sprintf('emulator mode, and SpinCam was not found%s', where));
        return
    end
    error('lum:dev:openCameras:noSpinCam', ...
          ['Video recording is on, but SpinCam was not found%s. Set the SpinCam folder on the '...
           'Cameras tab of the setup dialog, or untick Record video there.'], where);
end
if isempty(which('spincam.CameraManager'))
    addpath(folder);  % Session only; the saved path is untouched
end

backend = 'spinnaker';
options = {};
if emulated
    backend = 'mock';
    nCameras = max(1, sum(arrayfun(@(r) logical(r.Record), camera.Cameras)));
    options = {'NumCameras', nCameras, 'Resolution', [512 640]};
end
previewRate = 0;
if camera.ShowWindow
    previewRate = camera.WindowRate;
end

manager = [];
try
    manager = spincam.CameraManager('Backend', backend, 'FrameRate', camera.FrameRate, options{:});
    connected = lum.dev.configureCameras(manager, camera, 'Strict', true, 'PreviewRate', previewRate);
    manager.startPreview();
    manager.stopPreview();
    % SpinCam checks this only when recording starts; a session should refuse now.
    if lum.dev.Cameras.needsSpinVideo(camera.Format) && ~SpinCam.Engine.HasSpinVideo
        error('lum:dev:openCameras:noSpinVideo', ['The %s format needs Spinnaker''s SpinVideo '...
              'component, which this Spinnaker installation lacks; choose avi-mjpeg-mt or raw.'], ...
              camera.Format);
    end
    cameras = lum.dev.RealCameras(manager, camera, folder, connected);
catch openError
    if ~isempty(manager) && isvalid(manager)
        delete(manager);
    end
    if emulated
        warning('lum:dev:openCameras:emulatorFallback', ...
                'The simulated cameras could not start (%s); the session records no video.', ...
                openError.message);
        cameras = lum.dev.NullCameras(camera, 'emulator mode, simulated cameras unavailable');
        return
    end
    error('lum:dev:openCameras:failed', ...
          ['The cameras could not be started: %s\nClose SpinView and any other MATLAB using '...
           'them, check their USB cables, or untick Record video on the Cameras tab.'], ...
          openError.message);
end
