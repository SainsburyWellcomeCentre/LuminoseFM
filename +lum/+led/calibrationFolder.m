function folder = calibrationFolder()
% lum.led.calibrationFolder is where this rig's LED calibrations are kept.
%
% The folder 'calibration' at the root of the repository. It belongs to the rig, not
% to the code: git ignores it (.gitignore), so a clone on another rig starts with no
% calibration and never inherits this one. It is created when the first calibration is
% saved.
%
% See also: lum.led.calibrationFile, lum.led.saveCalibration, lum.repoRoot

folder = fullfile(lum.repoRoot(), 'calibration');
