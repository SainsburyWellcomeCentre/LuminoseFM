classdef SessionRunner < handle
    % lum.SessionRunner runs trials, with or without BpodTrialManager.
    %
    % The protocol needs BpodTrialManager: it is what lets trial n+1 be built and
    % uploaded while trial n is still running, which is the whole basis of the
    % real-time requirement. But BpodTrialManager's constructor errors outright in
    % emulator mode ("The Bpod emulator does not currently support running state
    % machines with TrialManager", BpodTrialManager.m), and the protocol must also
    % run end to end under Bpod('EMU').
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
    % With a trial manager, the prepare window opens as the trial starts
    % (lum.triggerStates) and the next state machine really is uploaded while the
    % current one runs. In
    % emulator mode the same calls run the trial to completion first, so the
    % session is sequential - slower between trials, but identical in what it
    % produces. Mode says which is in use, and is recorded in the data file so a
    % session's timing can be interpreted correctly afterwards. The decision is D3 in
    % docs/architecture.md.
    %
    % See also BpodTrialManager, lum.dev.open, lum.triggerStates

    properties (SetAccess = private)
        Mode           % 'trialmanager' or 'blocking'
        TriggerStates  % States whose onset opens the prepare window (entered from the first)
        Failed = false % True once a call to the state machine has failed
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
            % point in a trial where MATLAB may start preparing the next one
            % (lum.triggerStates); every trial passes through one of them.
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
                obj.start(sma, 1);
            else
                obj.pendingSma = sma;
            end
        end

        function awaitPrepareWindow(obj)
            % awaitPrepareWindow() blocks until it is safe to prepare the next trial.
            %
            % With a trial manager this returns as soon as the running trial has left its
            % first state for one of the trigger states (lum.triggerStates: every one is
            % entered from the first state), leaving the rest of the trial for MATLAB to
            % work in. It watches BpodSystem.Status.CurrentStateName rather than calling
            % BpodTrialManager.getCurrentEvents, which learns its trigger states only when
            % first called: a transition it had processed before then - trial 1's, when
            % TrialStart is short - went unnoticed, and it waited for the trial to end (rig
            % check 2026-09-28: trial 2 started 153 ms late at a 0 s ITI). In blocking mode
            % there is no such window, so the trial is run to completion here and its data
            % held for awaitTrialData.
            global BpodSystem %#ok<GVMIS> % Bpod's own session object
            if strcmp(obj.Mode, 'trialmanager')
                first = BpodSystem.StateMatrix.StateNames{1};
                while BpodSystem.Status.BeingUsed == 1 && BpodSystem.Status.InStateMatrix == 1 ...
                        && strcmp(BpodSystem.Status.CurrentStateName, first)
                    pause(0.001);
                end
            else
                SendStateMachine(obj.pendingSma);
                obj.pendingSma = [];
                obj.pendingRaw = RunStateMachine;
            end
        end

        function awaitState(obj, name)
            % awaitState(name) blocks until the running trial has entered the state, or ended.
            %
            % With a trial manager: until BpodSystem.Status.CurrentStateName is the state
            % (BpodTrialManager writes it on every transition), or the trial has ended
            % (Status.InStateMatrix 0), or the session was stopped. In blocking mode the trial
            % has already run to completion, so it returns at once.
            global BpodSystem %#ok<GVMIS> % Bpod's own session object
            if ~strcmp(obj.Mode, 'trialmanager')
                return
            end
            while BpodSystem.Status.BeingUsed == 1 && BpodSystem.Status.InStateMatrix == 1 ...
                    && ~strcmp(BpodSystem.Status.CurrentStateName, name)
                pause(0.001);
            end
        end

        function queue(obj, sma)
            % queue(sma) uploads the next trial's state machine.
            %
            % With a trial manager the upload happens now, over USB, while the
            % current trial is still running - the 'RunASAP' flag tells the device to
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
                obj.start([], 0);  % No argument: the machine was already sent
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
    end

    methods (Access = private)
        function start(obj, sma, hasSma)
            % start() calls BpodTrialManager.startTrial and turns a failure to talk
            % to the state machine into one error the session loop can act on.
            %
            % The failure this exists for is a USB link that has lost its place in
            % the byte stream: BpodTrialManager then reads a trial-start timestamp
            % that is not one (the console shows a missed-deadline warning of
            % astronomical size), and the next trial's acknowledgement byte never
            % arrives, so startTrial errors. Bpod's own message says only that the
            % state machine was not acknowledged; what the operator needs to know is
            % that the session is over, the data are safe and the link has to be
            % reset. Failed records that it happened, for anything that asks the
            % runner afterwards rather than catching the error.
            try
                if hasSma
                    obj.trialManager.startTrial(sma);
                else
                    obj.trialManager.startTrial();
                end
            catch startError
                obj.Failed = true;
                error('lum:SessionRunner:linkLost', ...
                      ['Lost the link to the Bpod state machine part way through the '...
                       'session: %s\n'...
                       'The trials completed so far are saved. Close MATLAB, power-cycle '...
                       'the state machine and PulsePal, and start again; a session that '...
                       'begins on a port a previous one did not release is the usual '...
                       'cause.'], startError.message);
            end
        end
    end

    methods
        function delete(obj)
            obj.close();
        end
    end
end
