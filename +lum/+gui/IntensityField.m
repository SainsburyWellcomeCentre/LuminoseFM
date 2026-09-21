classdef IntensityField < handle
    % lum.gui.IntensityField is a field for an LED intensity: mA, or mW/mm2 when calibrated.
    %
    % Settings hold LED currents in mA (S.Doric.CurrentmA, S.Ephys). A window shows and
    % takes a current in the unit of the channel's light path: irradiance at the fiber
    % tips in mW/mm2 when that path has a calibration (lum.led.loadCalibration), mA when
    % it does not. This field does the conversion both ways (lum.led.toUnit,
    % lum.led.fromUnit), so every window that sets an intensity behaves alike: a typed
    % irradiance becomes the whole mA that gives it, and the field then shows the
    % irradiance those mA give.
    %
    % Usage:
    %   f = lum.gui.IntensityField(parentGrid, 100, @onEdit);   % a field and its unit
    %   f.setCalibration(cal);          % [] for none; the shown value follows
    %   mA = f.currentmA();             % whole mA; NaN when empty (AllowEmpty)
    %
    % An irradiance outside the calibration's range is refused as it is typed, with a
    % message, and the field goes back to what it was.
    %
    % It occupies two cells of the parent grid: the number, then the unit and the
    % current it stands for.
    %
    % See also: lum.led.toUnit, lum.led.fromUnit, lum.gui.DoricSetup

    properties (SetAccess = private)
        Field               % The numeric uieditfield
        UnitLabel           % Its unit, and the other unit's value
        Calibration = []    % The light path's calibration, or []
        AllowEmpty = false  % Whether no value (NaN mA) is allowed
    end

    properties (Access = private)
        storedmA            % The current the field stands for; NaN for none
        showingmA = true    % Whether the field shows mA (no calibration, or outside it)
        onEdit
    end

    methods
        function obj = IntensityField(parent, currentmA, onEdit, varargin)
            p = inputParser;
            addParameter(p, 'AllowEmpty', false);
            addParameter(p, 'Tooltip', '');
            parse(p, varargin{:});
            obj.AllowEmpty = logical(p.Results.AllowEmpty);
            obj.onEdit = onEdit;
            obj.storedmA = double(currentmA);
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
            % setCalibration(cal) changes the light path's calibration ([] for none); the
            % stored current stays, and the field shows it in the new unit.
            if isequal(cal, obj.Calibration)
                return
            end
            obj.Calibration = cal;
            obj.show();
        end

        function setCurrent(obj, currentmA)
            % setCurrent(mA) shows another current.
            obj.storedmA = double(currentmA);
            obj.show();
        end

        function mA = currentmA(obj)
            % currentmA() is the current the field stands for. Errors when the typed
            % irradiance is outside the calibration ('lum:led:current:outOfRange').
            mA = obj.storedmA;
        end

        function setEnable(obj, on)
            obj.Field.Enable = lum.gui.Form.onOff(on);
        end
    end

    methods (Access = private)
        function edited(obj)
            value = obj.Field.Value;
            if isempty(value) || isnan(value)
                obj.storedmA = NaN;
            else
                try
                    if obj.showingmA
                        obj.storedmA = round(value);
                    else
                        obj.storedmA = lum.led.fromUnit(obj.Calibration, value);
                    end
                catch conversionError
                    obj.show();  % Back to what it was
                    uialert(ancestor(obj.Field, 'figure'), conversionError.message, 'Intensity');
                    return
                end
            end
            obj.show();
            obj.onEdit();
        end

        function show(obj)
            if isnan(obj.storedmA)
                if obj.AllowEmpty
                    obj.Field.Value = [];
                end
                [~, unit] = lum.led.toUnit(obj.Calibration, 0);
                obj.showingmA = isempty(obj.Calibration);
                obj.UnitLabel.Text = unitText(unit);
                return
            end
            [value, unit] = lum.led.toUnit(obj.Calibration, obj.storedmA);
            obj.showingmA = isempty(obj.Calibration) || isnan(value);
            if isnan(value)
                % A current outside the calibration: shown in mA, and said.
                obj.Field.Value = obj.storedmA;
                obj.UnitLabel.Text = sprintf('mA, outside the calibration (%g-%g mA)', ...
                                             obj.Calibration.CurrentmA(1), obj.Calibration.CurrentmA(end));
                return
            end
            obj.Field.Value = value;
            if isempty(obj.Calibration)
                obj.UnitLabel.Text = 'mA (not calibrated)';
            else
                obj.UnitLabel.Text = sprintf('%s  = %g mA', unitText(unit), obj.storedmA);
            end
        end
    end
end


function text = unitText(unit)
if strcmp(unit, 'mW/mm2')
    text = ['mW/mm' char(178)];
else
    text = unit;
end
end
