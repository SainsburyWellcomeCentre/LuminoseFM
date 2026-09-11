function [sessionType, app] = SessionTypeDialog(varargin)
% lum.gui.SessionTypeDialog asks what kind of session is starting: behaviour or sleep.
%
% The first window LuminoseFM opens (D11). The choice decides everything after it:
%
%   Behaviour  the 2-AFC task — the full setup dialog, the trial loop, the runtime
%              window and the online plots
%   Sleep      a home-cage sleep recording — a reduced setup dialog, then the session
%              barcode (with sleep markers) and sync pulses on a clock, with a plot
%              of the pulses sent
%
% The kind chosen last for this subject is preselected, because it is saved with the
% subject's settings (S.Session.Type).
%
% Options:
%   'Default'  'Behaviour' (default) or 'Sleep': the preselected choice
%   'Subject'  The subject chosen in the launch manager, shown in the header
%   'Wait'     false to return at once with the window open (for tests); default true
%   'Visible'  'on' (default) or 'off'
%
% Returns:
%   sessionType  'Behaviour', 'Sleep', or '' if the operator cancelled
%   app          .Figure, .choose(type), .cancel() and .choice() — the choice so far,
%                for tests that do not wait
%
% See also: LuminoseFM, lum.gui.SetupDialog, lum.gui.SleepSetupDialog

p = inputParser;
p.FunctionName = 'lum.gui.SessionTypeDialog';
addParameter(p, 'Default', 'Behaviour', @(x) ischar(x) || isstring(x));
addParameter(p, 'Subject', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'Wait', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'Visible', 'on');
parse(p, varargin{:});

sessionType = '';
t = lum.gui.theme();
types = lum.experimentChoices().SessionTypes;
preselected = char(p.Results.Default);
if ~ismember(preselected, types)
    preselected = types{1};
end
descriptions = struct( ...
    'Behaviour', 'The 2-AFC task in the behaviour box: cue, stimulus, choice and reward.', ...
    'Sleep', 'A home-cage sleep recording: a sleep barcode, then sync pulses only.');

fig = uifigure('Name', 'LuminoseFM - new session', 'Position', [300 300 560 280], ...
               'Color', t.Background, 'Visible', p.Results.Visible, ...
               'CloseRequestFcn', @(~, ~) onCancel());
grid = uigridlayout(fig, [4 1], 'RowHeight', {52, 26, '1x', 30}, 'Padding', [16 12 16 14], ...
                    'RowSpacing', 10, 'BackgroundColor', t.Background);

header = uigridlayout(grid, [1 2], 'ColumnWidth', {48, '1x'}, 'Padding', 0, ...
                      'ColumnSpacing', 12, 'BackgroundColor', t.Background);
logoImage = lum.gui.logo(96);
if isempty(logoImage)
    uilabel(header, 'Text', '');
else
    uiimage(header, 'ImageSource', logoImage, 'ScaleMethod', 'fit');
end
subject = char(p.Results.Subject);
if isempty(subject)
    subject = 'no subject chosen';
end
titles = uigridlayout(header, [2 1], 'RowHeight', {26, 20}, 'Padding', 0, 'RowSpacing', 0, ...
                      'BackgroundColor', t.Background);
uilabel(titles, 'Text', 'LuminoseFM  |  new session', 'FontSize', 18, 'FontWeight', 'bold', ...
        'FontColor', t.Ink);
uilabel(titles, 'Text', sprintf('Subject %s', subject), 'FontColor', t.Muted);

uilabel(grid, 'Text', 'What kind of session is this?', 'FontSize', 14, 'FontWeight', 'bold', ...
        'FontColor', t.Ink);

options = uigridlayout(grid, [2 numel(types)], 'RowHeight', {44, '1x'}, 'Padding', 0, ...
                       'ColumnSpacing', 12, 'RowSpacing', 6, 'BackgroundColor', t.Background);
buttons = struct();
for i = 1:numel(types)
    name = types{i};
    buttons.(name) = uibutton(options, 'Text', name, 'FontSize', 14, 'FontWeight', 'bold', ...
                              'ButtonPushedFcn', @(~, ~) choose(name));
    buttons.(name).Layout.Row = 1;
    buttons.(name).Layout.Column = i;
    if strcmp(name, preselected)
        buttons.(name).BackgroundColor = t.Accent;
        buttons.(name).FontColor = [1 1 1];
    end
    description = lum.gui.Form.note(options, descriptions.(name), t);
    description.Layout.Row = 2;
    description.Layout.Column = i;
end

footer = uigridlayout(grid, [1 2], 'ColumnWidth', {'1x', 100}, 'Padding', 0, ...
                      'ColumnSpacing', 8, 'BackgroundColor', t.Background);
lum.gui.Form.note(footer, sprintf('Last used for this subject: %s.', lower(preselected)), t);
uibutton(footer, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());

app = struct('Figure', fig, 'choose', @choose, 'cancel', @onCancel, 'choice', @currentChoice);
if p.Results.Wait
    uiwait(fig);
end


    function choose(name)
        sessionType = name;
        if isvalid(fig)
            delete(fig);
        end
    end

    function onCancel()
        sessionType = '';
        if isvalid(fig)
            delete(fig);
        end
    end

    function value = currentChoice()
        value = sessionType;
    end
end
