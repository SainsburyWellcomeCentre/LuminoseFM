function [imageFile, problem] = savePlotsImage(fig, dataFile)
% lum.gui.savePlotsImage saves the session's live figure as it looks at the end, beside the data.
%
%   [imageFile, problem] = lum.gui.savePlotsImage(fig, dataFile)
%
% Written once, at teardown, after the last trial or block is plotted and before the
% figure is closed, so the operator's view of the session is kept with its data:
%
%   <Session Data folder>\<data file name>_plots.png
%
% exportapp is used because it is the only exporter that takes these figures:
% exportgraphics refuses a classic figure holding more than one uipanel, and print any
% figure with UI components. It works headless too (under -batch).
%
% Arguments:
%   fig       The figure (lum.OnlinePlots.Figure or lum.sleep.Plots.Figure)
%   dataFile  The session's data file, BpodSystem.Path.CurrentDataFile
%
% Returns:
%   imageFile  Full path of the image written, or '' when none was
%   problem    '' on success, otherwise why nothing was written — a closed figure, or
%              the exporter's error. Never throws: a figure that cannot be saved must
%              not cost the session its teardown.
%
% See also: LuminoseFM, lum.sleep.run, lum.OnlinePlots, lum.sleep.Plots

imageFile = '';
problem = '';
if isempty(fig) || ~isgraphics(fig)
    problem = 'the figure was closed during the session';
    return
end
[folder, name] = fileparts(char(dataFile));
if isempty(name)
    problem = 'the session has no data file name';
    return
end
target = fullfile(folder, [name '_plots.png']);
try
    exportapp(fig, target);
    imageFile = target;
catch exportError
    problem = exportError.message;
end
