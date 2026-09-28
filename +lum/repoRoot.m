function root = repoRoot()
% lum.repoRoot returns the absolute path of the LuminoseFM folder.
%
% Resolved from the location of this file, so the protocol works wherever the
% repository is cloned. Everything that needs a path inside the repository
% (calibration/, docs/, .git) or beside it (PulsePal, two folders up) starts here
% rather than from a hard-coded drive letter.
%
% Usage:
%   folder = fullfile(lum.repoRoot, 'calibration');
%
% See also lum.version, lum.led.calibrationFolder, lum.dev.openPulsePal

% +lum lives directly inside the repository root, so one level up from this file's
% package folder is the root.
packageFolder = fileparts(mfilename('fullpath'));
root = fileparts(packageFolder);
