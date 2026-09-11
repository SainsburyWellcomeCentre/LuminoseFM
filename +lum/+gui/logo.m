function image = logo(sizePixels)
% lum.gui.logo returns the Luminose logo as a small, round RGB image.
%
% The artwork in docs/logo is 1024 pixels square; the windows show it at a few
% dozen. It is block-averaged down (base MATLAB only, no toolbox) and cut to a
% circle on the theme's background, then cached, so each window pays for the
% decode once per MATLAB session and nothing is resampled during the trial loop.
%
% Arguments:
%   sizePixels  Edge of the square image (default 64)
%
% Returns an sizePixels x sizePixels x 3 uint8 image, or [] if the artwork is
% missing — windows then simply show no logo.
%
% See also: lum.gui.theme, lum.gui.SetupDialog, lum.OnlinePlots

persistent cache
if nargin < 1
    sizePixels = 64;
end
key = sprintf('px%d', sizePixels);
if isstruct(cache) && isfield(cache, key)
    image = cache.(key);
    return
end

image = [];
path = fullfile(lum.repoRoot, 'docs', 'logo', 'luminose_logo.jpg');
if ~isfile(path)
    return
end
try
    artwork = imread(path);
catch
    return
end
if size(artwork, 3) == 1
    artwork = repmat(artwork, 1, 1, 3);
end

side = min(size(artwork, 1), size(artwork, 2));
block = floor(side / sizePixels);
if block < 1
    return
end
used = block * sizePixels;
first = floor((side - used) / 2) + 1;
artwork = double(artwork(first:first + used - 1, first:first + used - 1, :));

background = lum.gui.theme().Background * 255;
[column, row] = meshgrid(1:sizePixels, 1:sizePixels);
centre = (sizePixels + 1) / 2;
distance = hypot(column - centre, row - centre);
% A one-pixel soft edge, so the circle does not look cut out with scissors.
coverage = min(max(sizePixels / 2 - distance + 0.5, 0), 1);

image = zeros(sizePixels, sizePixels, 3, 'uint8');
for channel = 1:3
    blocks = reshape(artwork(:, :, channel), block, sizePixels, block, sizePixels);
    averaged = squeeze(mean(mean(blocks, 1), 3));
    image(:, :, channel) = uint8(coverage .* averaged + (1 - coverage) * background(channel));
end

if ~isstruct(cache)
    cache = struct();
end
cache.(key) = image;
