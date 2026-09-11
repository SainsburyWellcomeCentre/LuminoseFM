function t = theme()
% lum.gui.theme is the one palette every LuminoseFM window draws with.
%
% A light, quiet palette: a warm off-white ground, white panels, and colour kept for
% what carries meaning — the two optical channels, outcomes and sides. Channel A and
% channel B have their own colours and nothing else uses them, so light is
% recognisable at a glance in the setup dialog, the stimulus designer and the
% online plots alike; the sides get colours distinct from both, so a left-rewarded
% trial is never mistaken for channel A.
%
% Returns a struct of RGB triples in [0, 1], plus:
%   .StateColours  4 x 3 colormap for joint states 0 dark, 1 A, 2 B, 3 both
%   .FontSize      Base font size for controls
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.gui.SetupDialog, lum.OnlinePlots, lum.gui.PatternBrowser

t = struct();
t.Background   = [0.961 0.957 0.945];
t.Panel        = [1.000 1.000 1.000];
t.Ink          = [0.137 0.157 0.188];
t.Muted        = [0.435 0.463 0.506];
t.Faint        = [0.878 0.882 0.890];
t.Accent       = [0.180 0.353 0.525];
t.AccentSoft   = [0.890 0.925 0.957];

t.ChannelA     = [0.086 0.553 0.584];   % teal
t.ChannelB     = [0.847 0.412 0.290];   % coral
t.Overlap      = [0.431 0.353 0.620];   % violet: A and B together
t.Dark         = [0.918 0.918 0.914];   % neither channel on

t.Correct      = [0.180 0.584 0.365];
t.Incorrect    = [0.800 0.259 0.322];
t.NoChoice     = [0.620 0.639 0.663];
t.Left         = [0.310 0.365 0.651];   % indigo
t.Right        = [0.773 0.580 0.176];   % ochre

t.Good         = [0.118 0.431 0.259];
t.Bad          = [0.702 0.161 0.200];
t.Warn         = [0.620 0.431 0.063];

t.StateColours = [t.Dark; t.ChannelA; t.ChannelB; t.Overlap];
t.FontSize     = 12;
