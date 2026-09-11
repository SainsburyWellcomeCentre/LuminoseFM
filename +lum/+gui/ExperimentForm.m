classdef ExperimentForm
    % lum.gui.ExperimentForm builds the experiment record both setup dialogs share.
    %
    % A behaviour session and a sleep session record the same things about the animal
    % and what else happened in the session (S.Meta): subject and genotype, a
    % Neuropixels recording, an EEG/EMG recording, a drug, and notes. Both dialogs
    % build those panels here, read them back here and grey out what is switched off
    % here, so the two cannot drift apart and the data file means the same in both.
    %
    % Usage, inside a dialog:
    %   controls = lum.gui.ExperimentForm.buildAnimal(leftGrid, S, choices, t);
    %   more = lum.gui.ExperimentForm.buildRecordings(bodyGrid, S, choices, t, @refresh);
    %   S.Meta = lum.gui.ExperimentForm.read(controls, S.Meta);
    %   lum.gui.ExperimentForm.update(controls, S.Meta);
    %
    % The genotype is an editable dropdown: the listed genotypes
    % (lum.experimentChoices) are suggestions, and any other can be typed.
    %
    % See also: lum.gui.SetupDialog, lum.gui.SleepSetupDialog, lum.gui.Form

    methods (Static)
        function controls = buildAnimal(parent, S, choices, t)
            % buildAnimal(parent, S, choices, t): subject and genotype.
            form = lum.gui.Form.panel(parent, 'Animal', 2, t, 170);
            lum.gui.Form.label(form, 'Subject', t);
            controls.Subject = uieditfield(form, 'text', 'Value', S.Meta.Subject, ...
                'Editable', lum.gui.Form.onOff(isempty(S.Meta.Subject)), ...
                'Tooltip', 'Chosen in the Bpod launch manager; it names the data file');
            lum.gui.Form.label(form, 'Genotype', t);
            controls.Genotype = uidropdown(form, ...
                'Items', lum.gui.Form.withValue(choices.Genotypes, S.Meta.Genotype), ...
                'Value', S.Meta.Genotype, 'Editable', 'on', ...
                'Tooltip', 'Pick one, or type any genotype');
        end

        function controls = buildNotes(parent, S, t)
            % buildNotes(parent, S, t): free-text notes for the session.
            box = uipanel(parent, 'Title', 'Session notes', 'FontWeight', 'bold', ...
                          'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
            grid = uigridlayout(box, [1 1], 'Padding', 8, 'BackgroundColor', t.Panel);
            controls.Notes = uitextarea(grid, 'Value', S.Meta.Notes);
        end

        function controls = buildRecordings(parent, S, choices, t, onEdit)
            % buildRecordings(parent, S, choices, t, onEdit): the Neuropixels, EEG/EMG
            % and drug panels, in a scrollable column of their own.
            height = @lum.gui.Form.panelHeight;
            label = @(form, caption) lum.gui.Form.label(form, caption, t);
            grid = uigridlayout(parent, [4 1], 'RowHeight', {height(6), height(4), height(7), '1x'}, ...
                                'Padding', 0, 'RowSpacing', 10, 'BackgroundColor', t.Background, ...
                                'Scrollable', 'on');

            np = S.Meta.Neuropixels;
            form = lum.gui.Form.panel(grid, 'Neuropixels', 6, t, 190);
            label(form, '');
            controls.NPEnabled = uicheckbox(form, 'Text', 'Neuropixels recording', ...
                'Value', np.Enabled, 'ValueChangedFcn', @(~, ~) onEdit());
            label(form, 'Probe');
            controls.NPProbe = uidropdown(form, 'Items', lum.gui.Form.withValue(choices.Probes, np.Probe), ...
                'Value', np.Probe, 'Editable', 'on');
            label(form, 'Implant');
            controls.NPImplant = uidropdown(form, 'Items', choices.Implants, 'Value', np.Implant);
            label(form, 'Target region');
            controls.NPTarget = uieditfield(form, 'text', 'Value', np.Target);
            label(form, 'Coordinates (AP, ML, DV mm)');
            controls.NPCoordinates = uieditfield(form, 'text', 'Value', np.Coordinates);
            label(form, 'Probe serial number');
            controls.NPSerial = uieditfield(form, 'text', 'Value', np.SerialNumber);

            eeg = S.Meta.EEG;
            form = lum.gui.Form.panel(grid, 'EEG and EMG', 4, t, 190);
            label(form, '');
            controls.EEGEnabled = uicheckbox(form, 'Text', 'EEG/EMG recording', ...
                'Value', eeg.Enabled, 'ValueChangedFcn', @(~, ~) onEdit());
            label(form, 'EEG channels');
            controls.EEGChannels = lum.gui.Form.number(form, eeg.EEGChannels, [0 64], onEdit, true);
            label(form, 'EMG channels');
            controls.EMGChannels = lum.gui.Form.number(form, eeg.EMGChannels, [0 16], onEdit, true);
            label(form, 'Montage and notes');
            controls.EEGNotes = uieditfield(form, 'text', 'Value', eeg.Notes);

            drug = S.Meta.Drug;
            form = lum.gui.Form.panel(grid, 'Drug', 7, t, 190);
            label(form, '');
            controls.DrugEnabled = uicheckbox(form, 'Text', 'Drug administration', ...
                'Value', drug.Enabled, 'ValueChangedFcn', @(~, ~) onEdit());
            label(form, 'Drug');
            controls.DrugName = uidropdown(form, 'Items', lum.gui.Form.withValue(choices.Drugs, drug.Name), ...
                'Value', drug.Name, 'Editable', 'on', 'ValueChangedFcn', @(~, ~) onEdit());
            label(form, 'Delivery');
            controls.DrugDelivery = uidropdown(form, ...
                'Items', lum.gui.Form.withValue(choices.Deliveries, drug.Delivery), 'Value', drug.Delivery);
            label(form, 'Dose');
            doseGrid = uigridlayout(form, [1 2], 'ColumnWidth', {'1x', 90}, 'Padding', 0, ...
                                    'ColumnSpacing', 6, 'BackgroundColor', t.Panel);
            controls.DrugDose = lum.gui.Form.number(doseGrid, drug.Dose, [0 Inf], onEdit, false);
            controls.DrugUnit = uidropdown(doseGrid, ...
                'Items', lum.gui.Form.withValue(choices.DoseUnits, drug.DoseUnit), 'Value', drug.DoseUnit);
            label(form, 'Vehicle');
            controls.DrugVehicle = uieditfield(form, 'text', 'Value', drug.Vehicle);
            label(form, 'Given (min before start)');
            controls.DrugMinutes = lum.gui.Form.number(form, drug.MinutesBeforeSession, [-1440 1440], ...
                                                       onEdit, false);

            lum.gui.Form.note(grid, ['What is recorded or given in a session is stored with its data, '...
                                     'so a session can be found by it later.'], t);
        end

        function meta = read(controls, meta)
            % read(controls, meta) reads whichever of these panels a dialog built back
            % into S.Meta.
            c = controls;
            if isfield(c, 'Subject')
                meta.Subject = strtrim(c.Subject.Value);
            end
            if isfield(c, 'Genotype')
                meta.Genotype = strtrim(char(c.Genotype.Value));
            end
            if isfield(c, 'Notes')
                meta.Notes = strjoin(cellstr(c.Notes.Value), newline);
            end
            if isfield(c, 'NPEnabled')
                meta.Neuropixels = struct('Enabled', c.NPEnabled.Value, ...
                    'Probe', char(c.NPProbe.Value), 'Implant', c.NPImplant.Value, ...
                    'Target', c.NPTarget.Value, 'Coordinates', c.NPCoordinates.Value, ...
                    'SerialNumber', c.NPSerial.Value);
                meta.EEG = struct('Enabled', c.EEGEnabled.Value, ...
                    'EEGChannels', c.EEGChannels.Value, 'EMGChannels', c.EMGChannels.Value, ...
                    'Notes', c.EEGNotes.Value);
                meta.Drug = struct('Enabled', c.DrugEnabled.Value, ...
                    'Name', strtrim(char(c.DrugName.Value)), 'Delivery', c.DrugDelivery.Value, ...
                    'Dose', c.DrugDose.Value, 'DoseUnit', c.DrugUnit.Value, ...
                    'Vehicle', c.DrugVehicle.Value, 'MinutesBeforeSession', c.DrugMinutes.Value);
            end
        end

        function update(controls, meta)
            % update(controls, meta) greys out the details of what is switched off.
            c = controls;
            if ~isfield(c, 'NPEnabled')
                return
            end
            lum.gui.Form.setEnable({c.NPProbe, c.NPImplant, c.NPTarget, c.NPCoordinates, c.NPSerial}, ...
                                   meta.Neuropixels.Enabled);
            lum.gui.Form.setEnable({c.EEGChannels, c.EMGChannels, c.EEGNotes}, meta.EEG.Enabled);
            lum.gui.Form.setEnable({c.DrugName, c.DrugDelivery, c.DrugDose, c.DrugUnit, ...
                                    c.DrugVehicle, c.DrugMinutes}, meta.Drug.Enabled);
        end

        function controls = merge(controls, more)
            % merge(controls, more) adds one struct of controls to another.
            names = fieldnames(more);
            for i = 1:numel(names)
                controls.(names{i}) = more.(names{i});
            end
        end
    end
end
