classdef RealFlex < lum.dev.Flex
    % lum.dev.RealFlex is the Flex I/O shim for a state machine that has Flex channels.
    %
    % Constructed by lum.dev.open on a Bpod r2+. Reads the live channel
    % configuration rather than the saved FlexConfig.mat, so a channel reconfigured
    % from the Bpod console since startup is reflected correctly.
    %
    % See also: lum.dev.Flex, lum.dev.NullFlex, lum.dev.open

    methods
        function obj = RealFlex(analogChannels, samplingRate, syncChannel)
            obj@lum.dev.Flex(analogChannels, samplingRate, syncChannel, true);
            if isempty(analogChannels)
                obj.announce('no analog input configured; the flow meter will not be recorded');
            else
                obj.announce('analog input on Flex %s at %g Hz', ...
                             mat2str(analogChannels), samplingRate);
            end
            if isempty(syncChannel)
                obj.announce(['sync TTL output not configured; set Flex2 to digital '...
                              'output in the Bpod console to enable it']);
            end
        end
    end

    methods (Access = protected)
        function applyBarcode(obj, code)
            % A state machine of its own, run to completion before the first trial,
            % so the barcode never appears among a trial's states.
            SendStateMachine(lum.sync.barcodeStateMachine(code, obj.SyncChannel));
            RunStateMachine;
        end

        function applyOpenViewer(~)
            global BpodSystem %#ok<GVMIS>
            BpodSystem.startAnalogViewer;
        end

        function sessionData = applyMerge(obj, sessionData)
            % applyMerge() closes the analog stream, then folds it into the session data.
            %
            % AddFlexIOAnalogData stops the acquisition timer and reopens the file by
            % name for reading, but nothing flushes Bpod's own write handle first, so
            % the last samples can still be sitting in MATLAB's buffer. Closing the
            % write handle here flushes them. RunProtocol('Stop') closes the same
            % handle inside a try/catch, so closing it early is safe.
            global BpodSystem %#ok<GVMIS>

            if isprop(BpodSystem, 'Timers') && isfield(BpodSystem.Timers, 'AnalogTimer')
                stop(BpodSystem.Timers.AnalogTimer);
            end
            try
                fclose(BpodSystem.AnalogDataFile);
            catch
                % Already closed, or never opened because recording was disabled.
            end

            % In volts, without a trial-aligned copy: that copy would duplicate a
            % whole session of 1 kHz samples in the same file, and analysis can slice
            % it from Samples and TrialNumber instead. Called with one option only:
            % AddFlexIOAnalogData v1.9.0 reads its *first* option as the trial-aligned
            % flag when given two, so ('Volts', 0) switched the copy on.
            sessionData = AddFlexIOAnalogData(sessionData, 'Volts');
            if isfield(sessionData, 'Analog') && isfield(sessionData, 'TrialStartTimestamp')
                sessionData.Analog = lum.dev.Flex.alignAnalog(sessionData.Analog, ...
                    sessionData.TrialStartTimestamp(1), obj.RunsBeforeTrials);
                obj.note('merged analog data: %d samples, aligned for %d run(s) before trial 1', ...
                         sessionData.Analog.nSamples, obj.RunsBeforeTrials);
            end
        end
    end
end
