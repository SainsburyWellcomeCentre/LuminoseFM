classdef Flex < lum.dev.Device
    % lum.dev.Flex represents the state machine's Flex I/O channels.
    %
    % Two things on this rig use Flex I/O: the flow meter, streamed by Bpod itself
    % from Flex1 configured as an analog input, and the sync TTL on Flex2 as a
    % digital output. Neither is emulated — Bpod('EMU') presents a Bpod r0.7-1.0
    % with no Flex channels at all — so both are behind this shim.
    %
    % The protocol never streams analog data itself; Bpod writes it to a
    % '..._ANLG.dat' file beside the session file. This class reports what is
    % configured, opens Bpod's analog viewer so the operator can watch the airflow,
    % sends the session barcode on the sync line, and merges the analog file into the
    % session data once the session ends — with its timeline corrected for the
    % barcode (alignAnalog).
    %
    % See also: lum.dev.open, lum.sync.barcode, AddFlexIOAnalogData, CheckRig

    properties (SetAccess = protected)
        AnalogChannels  % Indices of Flex channels configured as analog input
        SamplingRate    % Analog sampling rate in Hz, or NaN if none configured
        SyncChannel     % Output channel name for the sync TTL, or '' if unconfigured
        % State machines run before the first trial, i.e. the barcode. Bpod starts the
        % analog stream on the session's first run and counts every run as a trial,
        % so the merge has to know how many there were.
        RunsBeforeTrials = 0
    end

    methods
        function obj = Flex(analogChannels, samplingRate, syncChannel, available)
            obj@lum.dev.Device('FlexIO', available);
            obj.AnalogChannels = analogChannels;
            obj.SamplingRate = samplingRate;
            obj.SyncChannel = syncChannel;
        end

        function tf = hasAnalog(obj)
            % hasAnalog() is true when a flow-meter stream is being recorded.
            tf = obj.Available && ~isempty(obj.AnalogChannels);
        end

        function tf = hasSync(obj)
            % hasSync() is true when the sync TTL output channel exists.
            tf = obj.Available && ~isempty(obj.SyncChannel);
        end

        function sent = sendBarcode(obj, code)
            % sendBarcode(code) sends the session barcode on the sync line, blocking
            % until it is done (a second or two). Call before the first trial, and
            % before BpodTrialManager exists. Returns false, and logs why, when there
            % is no line to send it on.
            sent = false;
            if ~obj.hasSync()
                obj.note('%s barcode %s not sent: no sync line on this state machine', ...
                         lower(code.Kind), code.Hex);
                return
            end
            obj.applyBarcode(code);
            obj.RunsBeforeTrials = obj.RunsBeforeTrials + 1;
            obj.note('sent %s barcode %s (%.2f s) on %s', lower(code.Kind), code.Hex, ...
                     code.TotalDuration, obj.SyncChannel);
            sent = true;
        end

        function openAnalogViewer(obj)
            % openAnalogViewer() shows the live analog stream (the flow meter).
            if ~obj.hasAnalog()
                obj.note('analog viewer not opened: no analog input is recorded');
                return
            end
            obj.applyOpenViewer();
            obj.note('opened the analog viewer');
        end

        function sessionData = mergeAnalogData(obj, sessionData)
            % mergeAnalogData() folds the streamed analog file into the session data.
            %
            % Run once, after the trial loop. Returns sessionData unchanged when no
            % analog channel was recorded, so the caller needs no special case.
            if ~obj.hasAnalog()
                obj.note('no analog channel recorded; nothing to merge');
                return
            end
            sessionData = obj.applyMerge(sessionData);
        end
    end

    methods (Static)
        function analog = alignAnalog(analog, firstTrialStart, runsBeforeTrials)
            % alignAnalog(analog, firstTrialStart, runsBeforeTrials) corrects the
            % timeline AddFlexIOAnalogData gives the analog stream.
            %
            % Bpod starts streaming on the first RunStateMachine of a session and tags
            % each sample with the number of the state machine run it was taken in,
            % but AddFlexIOAnalogData stamps the first sample with the first *trial's*
            % start time. A barcode sent as its own run before trial 1 therefore
            % shifts every analog timestamp late by the barcode's length (about 1.8 s),
            % and numbers every sample one trial too high. The airflow then appears to
            % arrive as the animal reaches the reward port, when it arrived with the
            % hold (session 20260911_140213 is the case that showed it).
            %
            % The sample tagged with the first trial's run is put at firstTrialStart,
            % the rest follow at the sampling rate, and the tags are renumbered so that
            % samples before trial 1 are trial 0. Sessions with nothing before trial 1
            % are left as they are. TrialData, a copy of the samples per trial, is
            % dropped: it would be misaligned and it doubles the file.
            %
            % Pure: no hardware, no globals, unit-testable offline.
            if isfield(analog, 'TrialData')
                analog = rmfield(analog, 'TrialData');
            end
            if runsBeforeTrials < 1 || ~isfield(analog, 'TrialNumber') || isempty(analog.TrialNumber)
                return
            end
            first = find(analog.TrialNumber > runsBeforeTrials, 1);
            if isempty(first)
                return
            end
            n = numel(analog.TrialNumber);
            analog.Timestamps = firstTrialStart + ((1:n) - first) / analog.SamplingRate;
            analog.TrialNumber = max(analog.TrialNumber - runsBeforeTrials, 0);
            analog.info.Alignment = sprintf(['Timestamps and TrialNumber corrected by '...
                'lum.dev.Flex.alignAnalog for %d state machine run(s) before trial 1 (the '...
                'session barcode); samples taken before trial 1 have TrialNumber 0.'], ...
                runsBeforeTrials);
        end
    end

    methods (Access = protected)
        function sessionData = applyMerge(obj, sessionData) %#ok<INUSL> % Overridden by subclasses
            % applyMerge() performs the merge. Subclass responsibility.
        end

        function applyBarcode(obj, code) %#ok<INUSD> % Overridden by subclasses
            % applyBarcode() runs the barcode on the line. Subclass responsibility.
        end

        function applyOpenViewer(obj) %#ok<MANU> % Overridden by subclasses
            % applyOpenViewer() opens the viewer. Subclass responsibility.
        end
    end
end
