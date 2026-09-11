function choices = experimentChoices()
% lum.experimentChoices lists the options the Experiment tab offers.
%
% Kept apart from the dialog so that the lists can grow without touching layout
% code, and so analysis scripts can read what the recorded values could have been.
% The dialog's dropdowns are editable wherever a list cannot be complete, so an
% unlisted genotype or drug is typed rather than forced into 'Other'.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.defaultSettings, lum.gui.SetupDialog

choices = struct();
choices.SessionTypes = {'Behaviour', 'Sleep'};
% Suggestions only: the genotype dropdown is editable, so any genotype can be typed.
choices.Genotypes = {'OSN-ChR', 'Wild type'};
choices.Probes = {'Neuropixels 1.0', 'Neuropixels 2.0 (single shank)', ...
                  'Neuropixels 2.0 (4-shank)', 'Neuropixels Opto'};
choices.Implants = {'Chronic', 'Acute'};
choices.Drugs = {'Saline (vehicle control)', 'Baclofen', 'APV', 'Bicuculline', 'Gabazine', ...
                 'Muscimol', 'Isoflurane', 'Ketamine/xylazine'};
choices.Deliveries = {'Intraperitoneal (i.p.)', 'Subcutaneous (s.c.)', 'Intravenous (i.v.)', ...
                      'Oral', 'Intracerebral infusion', 'Topical on the bulb', 'Inhalation'};
choices.DoseUnits = {'mg/kg', 'ug/kg', 'mM', 'uM', 'nL', 'uL', '%'};
choices.GuideLights = {'Never', 'Habituation only', 'Always'};
choices.RuntimeWindows = {'Automatic', 'Tabbed', 'Compact'};
