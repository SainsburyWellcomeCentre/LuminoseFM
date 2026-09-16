classdef NullCameras < lum.dev.Cameras
    % lum.dev.NullCameras is the camera shim for sessions that record no video.
    %
    % Recording switched off, or, in the emulator, spincam not found. Starting and
    % stopping are logged; marks return NaN, so Data.CameraTime says no clock was kept.
    %
    % See also: lum.dev.Cameras, lum.dev.RealCameras, lum.dev.openCameras

    methods
        function obj = NullCameras(settings, reason)
            obj@lum.dev.Cameras(false, 'none', settings);
            obj.announce('no video recorded (%s)', reason);
        end
    end
end
