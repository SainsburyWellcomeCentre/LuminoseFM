function root = repoRoot()
% repoRoot returns the absolute path of the LuminoseFM folder.
%
% Resolved from the location of this file, so the protocol works wherever the
% repository is cloned. Everything that needs a path inside the repository
% (helper folders, docs) or beside it (Bpod_Gen2, PulsePal) starts here rather
% than from a hard-coded drive letter.
%
% Usage:
%   addpath(fullfile(lum.repoRoot, 'hardware'));

% +lum lives directly inside the repository root, so one level up from this file's
% package folder is the root.
packageFolder = fileparts(mfilename('fullpath'));
root = fileparts(packageFolder);
