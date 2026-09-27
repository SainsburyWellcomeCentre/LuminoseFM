function t = theme()
% lum.gui.theme is the one palette and type scale every LuminoseFM window draws with.
%
% A light, quiet palette: a warm off-white ground, white panels, and colour kept for
% what carries meaning — the two optical channels, outcomes, the hold and sides. Channel A
% and channel B have their own colours and nothing else uses them, so light is
% recognisable at a glance in the setup dialog, the stimulus designer and the
% online plots alike; the sides get colours distinct from both, so a left-rewarded
% trial is never mistaken for channel A.
%
% Plots are drawn for print: white figures, dark axes and text, one type scale, and colour
% only where it means something. The plot colours were checked with the dataviz skill's
% validator against white (OKLab distance x100, Machado 2009 colour-vision simulation):
%   Left #3E5C76 and Right #D4A72C    a navy and gold pair: 35 apart, at least 31 under any
%                                     simulated colour-vision deficiency
%   Correct #78A874, Incorrect #A6503F  a sage and rust pair, apart in lightness so that
%                                     they stay 14 apart under deutan and protan simulation;
%                                     the plots also mark them by shape (filled, open)
%   Left against the near-black series 13; Right against channel B 11 (they share no panel)
%   Series #2B3038, near black: a single series with no side or outcome to show
%   The greys mean "no choice" or "no hold", never a side or an outcome of a choice.
% Right, Correct and the lighter greys are under 3:1 against white: every panel that uses
% them has a key, and their marks are drawn large or thick.
%
% Returns a struct of RGB triples in [0, 1], plus:
%   .StateColours  4 x 3 colormap for joint states 0 dark, 1 A, 2 B, 3 both
%   .FontSize      Base font size for controls
%   .Font          The plots' type: .Name, and the sizes .Title, .Label, .Tick, .Legend,
%                  .Note (points), used through lum.gui.styleAxes and lum.gui.panelLegend;
%                  the summary plots' scale, for print
%   .FontCompact   The same family a step smaller, for the live figures (lum.OnlinePlots,
%                  lum.sleep.Plots), whose nine panels share one window
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.gui.styleAxes, lum.gui.panelLegend, lum.gui.SetupDialog, lum.OnlinePlots,
%           lum.report.summaryPlots

t = struct();
t.Background   = [0.961 0.957 0.945];
t.Panel        = [1.000 1.000 1.000];
t.Ink          = [0.137 0.157 0.188];
t.Muted        = [0.435 0.463 0.506];
t.Faint        = [0.878 0.882 0.890];
t.Grid         = hex('#E6E7EA');        % Gridlines in plots: behind everything, just visible
t.PlotBackground = [1 1 1];             % Plot figures are white, as printed
t.Axis         = hex('#33383F');        % Plot axes, ticks and tick labels
t.Series       = hex('#2B3038');        % A single series with no side or outcome (near black)
t.SeriesSoft   = hex('#8A9099');        % Its faint companions: each trial behind a mean
t.Accent       = [0.180 0.353 0.525];
t.AccentSoft   = [0.890 0.925 0.957];

t.ChannelA     = [0.086 0.553 0.584];   % teal
t.ChannelB     = [0.847 0.412 0.290];   % coral
t.Overlap      = [0.431 0.353 0.620];   % violet: A and B together
t.Dark         = [0.918 0.918 0.914];   % neither channel on

t.Correct      = hex('#78A874');        % sage green: correct, rewarded, hold completed
t.Incorrect    = hex('#A6503F');        % rust: incorrect, not rewarded
t.HeldLater    = hex('#B5CFB3');        % pale sage: hold completed after early withdrawals
t.NoChoice     = hex('#7F848B');        % grey: a trial without a choice, as a mark
t.NoSidePoke   = hex('#C4C7CC');        % light grey: hold completed, no side poke in time
t.NotHeld      = hex('#5E636B');        % dark grey: the hold was not completed
t.NoHold       = hex('#9DA1A8');        % mid grey: no hold started in the hold window
t.Left         = hex('#3E5C76');        % navy
t.Right        = hex('#D4A72C');        % gold

t.Good         = [0.118 0.431 0.259];   % Text: dark enough to read, not plot marks
t.Bad          = [0.702 0.161 0.200];
t.Warn         = [0.620 0.431 0.063];

t.StateColours = [t.Dark; t.ChannelA; t.ChannelB; t.Overlap];
t.FontSize     = 12;
t.Font         = struct('Name', fontName(), 'Title', 12, 'Label', 11, 'Tick', 10, ...
                        'Legend', 10, 'Note', 9);
t.FontCompact  = struct('Name', t.Font.Name, 'Title', 10, 'Label', 9, 'Tick', 9, ...
                        'Legend', 9, 'Note', 8);
end


function rgb = hex(text)
% An RGB triple in [0, 1] from '#RRGGBB'.
rgb = reshape(sscanf(text(2:end), '%2x'), 1, 3) / 255;
end


function name = fontName()
% The plots' font: Segoe UI where it is installed (Windows), else MATLAB's default. Looked up
% once per MATLAB process: listfonts takes a moment.
persistent cached
if isempty(cached)
    cached = 'Helvetica';
    try
        if any(strcmpi(listfonts, 'Segoe UI'))
            cached = 'Segoe UI';
        end
    catch
        % No font list (no display): the default
    end
end
name = cached;
end
