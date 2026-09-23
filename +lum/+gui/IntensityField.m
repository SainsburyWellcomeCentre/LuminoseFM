classdef IntensityField < handle
    % lum.gui.IntensityField is a field for an LED intensity: mW/mm2 when calibrated, mA when not.
    %
    % Settings keep each channel's intensity in two forms (lum.led.intensitySetting): the
    % irradiance at the fiber tips, used when the channel's light path is calibrated, and
    % the LED current, used when it is not. This field holds both and shows the one that
    % applies: irradiance in mW/mm2, with the current that gives it beside it
    % (lum.led.currentFor, within the channel's limit, saying so when the channel cannot
    % reach it), or mA with "not calibrated". What is typed changes the form shown; the
    % other is kept, so a calibration saved or a cable changed never loses either.
    %
    % Usage:
    %   f = lum.gui.IntensityField(parentGrid, 100, @onEdit, 'Irradiance', 8);
    %   f.setCalibration(cal);          % [] for none; the shown value follows
    %   f.setLimit(700);                % the channel's limit, mA
    %   mA = f.currentmA();             % the mA typed for an uncalibrated channel
    %   v = f.irradiance();             % the mW/mm2 typed for a calibrated channel
    %   mA = f.runmA();                 % what the channel runs at: whole mA
    %
    % With 'AllowEmpty', an empty field (NaN) means the most the channel gives: its limit
    % in mA, or the most irradiance its calibration reaches within it.
    %
    % It occupies two cells of the parent grid: the number, then the unit and the
    % current it stands for.
    %
    % See also: lum.led.intensity, lum.led.currentFor, lum.gui.DoricSetup

    properties (SetAccess = private)
        Field               % The numeric uieditfield
        UnitLabel           % Its unit, and the current it stands for
        Calibration = []    % The light path's calibration, or []
        AllowEmpty = false  % Whether no value (NaN: the most) is allowed
        LimitmA = Inf       % The channel's current limit
    end

    properties (Access = private)
        storedmA            % mA, used without a calibration; NaN for none
        storedIrradiance    % mW/mm2, used with one; NaN for none
        onEdit
    end

    methods
        function obj = IntensityField(parent, currentmA, onEdit, varargin)
            p = inputParser;
            addParameter(p, 'Irradiance', NaN);
            addParameter(p, 'LimitmA', Inf);
            addParameter(p, 'AllowEmpty', false);
            addParameter(p, 'Tooltip', '');
            parse(p, varargin{:});
            obj.AllowEmpty = logical(p.Results.AllowEmpty);
            obj.LimitmA = double(p.Results.LimitmA);
            obj.onEdit = onEdit;
            obj.storedmA = double(currentmA);
            obj.storedIrradiance = double(p.Results.Irradiance);
            allow = 'off';
            if obj.AllowEmpty
                allow = 'on';
            end
            obj.Field = uieditfield(parent, 'numeric', 'Limits', [0 Inf], 'AllowEmpty', allow, ...
                                    'ValueDisplayFormat', '%.4g', 'Tooltip', p.Results.Tooltip, ...
                                    'ValueChangedFcn', @(~, ~) obj.edited());
            obj.UnitLabel = uilabel(parent, 'Text', '', 'FontSize', 11);
            obj.show();
        end

        function setCalibration(obj, cal)
            % setCalibration(cal) changes the light path's calibration ([] for none); both
            % stored values stay, and the field shows the one that now applies.
            if isequal(cal, obj.Calibration)
                return
            end
            obj.Calibration = cal;
            obj.show();
        end

        function setLimit(obj, limitmA)
            % setLimit(mA) changes the channel's limit, which caps what it runs at.
            if isequal(double(limitmA), obj.LimitmA)
                return
            end
            obj.LimitmA = double(limitmA);
            obj.show();
        end

        function setCurrent(obj, currentmA)
            % setCurrent(mA) shows another current: the mA, and on a calibrated channel
            % the irradiance it gives.
            obj.storedmA = double(currentmA);
            if ~isempty(obj.Calibration)
                obj.storedIrradiance = lum.led.irradiance(obj.Calibration, obj.storedmA);
            end
            obj.show();
        end

        function mA = currentmA(obj)
            % currentmA() is the current typed for the channel when not calibrated.
            mA = obj.storedmA;
        end

        function value = irradiance(obj)
            % irradiance() is the irradiance typed for the channel when calibrated, mW/mm2.
            value = obj.storedIrradiance;
        end

        function mA = runmA(obj)
            % runmA() is the whole mA the channel runs at: through the calibration when
            % there is one, the current typed when not; the limit for empty.
            if obj.usesIrradiance()
                mA = lum.led.currentFor(obj.Calibration, obj.storedIrradiance, obj.LimitmA);
            elseif isnan(obj.storedmA)
                mA = obj.LimitmA;
            else
                mA = obj.storedmA;
            end
        end

        function setEnable(obj, on)
            obj.Field.Enable = lum.gui.Form.onOff(on);
        end
    end

    methods (Access = private)
        function tf = usesIrradiance(obj)
            % Irradiance is shown and typed when calibrated, unless no irradiance is known
            % and none may be empty (a current outside the calibration).
            tf = ~isempty(obj.Calibration) && (~isnan(obj.storedIrradiance) || obj.AllowEmpty);
        end

        function edited(obj)
            value = obj.Field.Value;
            if isempty(value)
                value = NaN;
            end
            if obj.usesIrradiance()
                obj.storedIrradiance = double(value);
            elseif isnan(value)
                obj.storedmA = NaN;
            else
                obj.storedmA = round(value);
                if ~isempty(obj.Calibration)
                    obj.storedIrradiance = lum.led.irradiance(obj.Calibration, obj.storedmA);
                end
            end
            obj.show();
            obj.onEdit();
        end

        function show(obj)
            if obj.usesIrradiance()
                value = obj.storedIrradiance;
                [mA, reached, note] = lum.led.currentFor(obj.Calibration, value, obj.LimitmA);
                unit = ['mW/mm' char(178)];
                if isnan(value)
                    text = sprintf('%s, empty: the most, %.3g (%g mA)', unit, reached, mA);
                elseif isempty(note)
                    text = sprintf('%s  = %g mA', unit, mA);
                elseif isnan(reached)
                    text = sprintf('%s: runs at %g mA, below the calibration', unit, mA);
                else
                    text = sprintf('%s: reaches %.3g (%g mA)', unit, reached, mA);
                end
            else
                value = obj.storedmA;
                if isempty(obj.Calibration)
                    text = 'mA (not calibrated)';
                else
                    text = sprintf('mA, outside the calibration (%g-%g mA)', ...
                                   obj.Calibration.CurrentmA(1), obj.Calibration.CurrentmA(end));
                end
                if isnan(value)
                    text = sprintf('%s, empty: the limit, %g mA', text, obj.LimitmA);
                end
            end
            if isnan(value)
                if obj.AllowEmpty
                    obj.Field.Value = [];
                end
            else
                obj.Field.Value = value;
            end
            obj.UnitLabel.Text = text;
        end
    end
end
