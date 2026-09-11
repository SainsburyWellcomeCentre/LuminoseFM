classdef SyncMode
    % lum.SyncMode enumerates how the sync TTL line is driven during trials.
    %
    % The line goes to the acquisition devices, so its meaning is part of the
    % experiment: what a rising edge means in the electrophysiology file is
    % decided here. Stored as an integer per trial (Data.SyncMode) and part of the
    % data format — append new modes, never renumber the existing ones, or old
    % session files change meaning. Names may be clarified; codes may not move.
    %
    % Whether the line is driven at all is separate, and stays S.Session.UseSync;
    % so is whether the hardware can (Flex2 configured as a digital output). The
    % session barcode sent before the first trial is separate too, and is the
    % same whatever mode the trials use (lum.sync.barcode).
    %
    % See also: lum.nextTrialSpec, lum.buildTrialSM, lum.sync.barcode

    properties (Constant)
        % One pulse per trial, always S.Sync.FixedWidth long. The simplest thing to
        % detect, and enough when the acquisition system counts trials.
        FixedWidth    = 1

        % One pulse per trial, its width drawn uniformly within S.Sync.WidthJitter
        % of S.Sync.MeanWidth. The widths are near-unique, so a recording can be
        % matched to Data.SyncPulseWidth trial by trial rather than by counting
        % edges from the start. (Named 'Random width' before version 0.2.)
        JitteredWidth = 2

        % No pulse. The line goes high at trial start and low when the animal
        % pokes the centre port, so its own edges mark the task events and the
        % recording carries the initiation latency without the behaviour file.
        TaskEvents    = 3
    end

    methods (Static)
        function names = allNames()
            % allNames() lists every mode name, ordered by code. This is what the
            % setup dialog offers, so the list and the codes cannot drift.
            names = {'Fixed width', 'Jittered width', 'Task events'};
        end

        function text = name(code)
            % name(code) returns the mode's name, for logs and the trial record.
            names = lum.SyncMode.allNames();
            if ~isscalar(code) || ~isfinite(code) || code < 1 || code > numel(names)
                text = 'Unknown';
                return
            end
            text = names{code};
        end
    end
end
