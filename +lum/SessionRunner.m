classdef SessionRunner < handle
    % lum.SessionRunner runs trials, with or without BpodTrialManager.
    %
    % The protocol needs BpodTrialManager: it is what lets trial n+1 be built and
    % uploaded while trial n is still running, which is the whole basis of the
    % real-time requirement. But BpodTrialManager's constructor errors outright in
    % emulator mode ("The Bpod emulator does not currently support running state
    % machines with TrialManager", BpodTrialManager.m), and running end to end
    % under Bpod('EMU') is equally non-negotiable.
    %
    % This class reconciles the two. It exposes one four-call rhythm that the
    % session loop follows unchanged, and implements it either over
    % BpodTrialManager or over blocking RunStateMachine calls:
    %
    %   runner.begin(smaForTrial1);
    %   for trial = 1:nTrials
    %       runner.awaitPrepareWindow();      % returns when it is safe to work
    %       runner.queue(smaForNextTrial);    % upload the next trial
    %       raw = runner.awaitTrialData();    % the finished trial's raw events
    %       runner.advance();                 % start watching the next trial
    %   end
    %
    % With a trial manager, the prepare window opens partway through the trial and
    % the next state machine really is uploaded while the current one runs. In
    % emulator mode the same calls run the trial to completion first, so the
    % session is sequential — slower between trials, but identical in what it
    % produces. Mode says which is in use, and is recorded in the data file so a
    % session's timing can be interpreted correctly afterwards.
    %
    % See also: BpodTrialManager, lum.dev.open, docs/architecture.md (D3)

    properties (SetAccess = private)
        Mode           % 'trialmanager' or 'blocking'
        TriggerStates  % States whose onset opens the prepare window
    end

    properties (Access = private)
        trialManager   % BpodTrialManager instance, or [] in blocking mode
        pendingSma     % Blocking mode: the state machine for the trial not yet run
        pendingRaw     % Blocking mode: raw events of the trial just run
    end

    methods
        function obj = SessionRunner(emulated, triggerStates)
            % SessionRunner(emulated, triggerStates) picks the execution strategy.
            %
            % emulated comes from lum.dev.open, which is the one place that reads
            % BpodSystem.EmulatorMode. triggerStates names the states that mark the
            % point in a trial where MATLAB may start preparing the next one; they
            % should be states every trial passes through, late enough that the
            % remaining states leave time for the work.
            obj.TriggerStates = triggerStates;
            if emulated
                obj.Mode = 'blocking';
                obj.trialManager = [];
            else
                obj.Mode = 'trialmanager';
                obj.trialManager = BpodTrialManager;
            end
        end

        function begin(obj, sma)
            % begin(sma) sends the first trial's state machine and starts it.
            if strcmp(obj.Mode, 'trialmanager')
                obj.trialManager.startTrial(sma);
            else
                obj.pendingSma = sma;
            end
        end

        function awaitPrepareWindow(obj)
            % awaitPrepareWindow() blocks until it is safe to prepare the next trial.
            %
            % With a trial manager this returns as soon as the running trial reaches
            % one of the trigger states, leaving the rest of the trial for MATLAB to
            % work in. In blocking mode there is no such window, so the trial is run
            % to completion here and its data held for awaitTrialData.
            if strcmp(obj.Mode, 'trialmanager')
                obj.trialManager.getCurrentEvents(obj.TriggerStates);
            else
                SendStateMachine(obj.pendingSma);
                obj.pendingSma = [];
                obj.pendingRaw = RunStateMachine;
            end
        end

        function queue(obj, sma)
            % queue(sma) uploads the next trial's state machine.
            %
            % With a trial manager the upload happens now, over USB, while the
            % current trial is still running — the 'RunASAP' flag tells the device to
            % start it the moment the current one exits.
            if strcmp(obj.Mode, 'trialmanager')
                SendStateMachine(sma, 'RunASAP');
            else
                obj.pendingSma = sma;
            end
        end

        function raw = awaitTrialData(obj)
            % awaitTrialData() returns the finished trial's raw states and events.
            if strcmp(obj.Mode, 'trialmanager')
                raw = obj.trialManager.getTrialData;
            else
                raw = obj.pendingRaw;
                obj.pendingRaw = [];
            end
        end

        function advance(obj)
            % advance() begins monitoring the trial that queue() uploaded.
            if strcmp(obj.Mode, 'trialmanager')
                obj.trialManager.startTrial();  % No argument: the machine was already sent
            end
        end

        function close(obj)
            % close() releases the trial manager, which stops its polling timer in
            % its own destructor.
            if ~isempty(obj.trialManager)
                delete(obj.trialManager);
                obj.trialManager = [];
            end
        end

        function delete(obj)
            obj.close();
        end
    end
end
