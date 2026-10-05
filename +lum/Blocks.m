classdef Blocks
    % lum.Blocks holds the paying side for blocks of trials (S.GUI.TrialOrder 'Blocks').
    %
    % A block is a run of trials whose patterns lean to one side; the next block takes the
    % other side (D23). Context correction makes a habit pay less; blocks make another way
    % of choosing pay more: staying with the side that just paid earns about 1 - 1/mean
    % length, while alternating or always going one way still earns 50% and following the
    % stimulus every correct choice. The first trial after a switch is the session's test
    % of the light: a win-stay animal gets it wrong, an alternator half right, an animal
    % that uses the stimulus mostly right.
    %
    % The rule, applied by lum.nextTrialSpec as each trial is prepared:
    %   - A block's length is drawn evenly from S.GUI.BlockMin to BlockMax (whole trials),
    %     so a switch cannot be counted to. With S.GUI.BlockSwitchAfterCorrect N above 0 it
    %     ends instead once it has run BlockMin trials and the animal's last N choices in it
    %     were correct, or at BlockMax. Its length counts the trials prepared (the one
    %     still running included), and the criterion the trials recorded, so a block ends
    %     one trial after the criterion is met.
    %   - A block takes patterns that lean to its side (P(left) above 0.5 for left, below
    %     for right) or none (0.5), brought forward from later in the order by the same swap
    %     as bias correction; the trial's side is still drawn from its own P(left), so the
    %     contingency is unchanged, and a pure-channel set pays the block's side only.
    %   - A block ends early when no later pattern can serve it, and the next block takes
    %     the other side.
    %   - Bias correction and the run limit do not act while blocks run, and the trial
    %     records the block's side as BiasTargetPLeft (1 or 0).
    %   - Choosing Blocks mid-session starts a block at the next trial prepared; choosing
    %     Random ends it there.
    %
    % Each trial records Block (0 in a random order, else the block's number) and BlockSide
    % (1 left, 2 right, NaN in a random order): part of the data format.
    %
    % Static methods; nothing to construct. Pure: no hardware, no globals; lengths and the
    % first block's side come from rand(), as lum.nextTrialSpec's draws do.
    %
    % See also lum.nextTrialSpec, lum.BiasCorrection, lum.updateHistory

    properties (Constant)
        % S.GUI.TrialOrder's items, in code order
        Orders = {'Random', 'Blocks'}
    end

    methods (Static)
        function tf = isOn(S)
            % isOn(S) is true when the trial order is in blocks.
            tf = isfield(S.GUI, 'TrialOrder') && S.GUI.TrialOrder == 2;
        end

        function tf = canUse(pLeft, side)
            % canUse(pLeft, side) is true for patterns a block on that side may use (1 left,
            % 2 right): those leaning to it, or to neither; vectorised over pLeft.
            if side == 1
                tf = pLeft >= 0.5 & pLeft > 0;
            else
                tf = pLeft <= 0.5 & pLeft < 1;
            end
        end

        function block = next(S, history, trialNumber, queue, pLeftOf)
            % next(S, history, trial, queue, pLeftOf) is the block trial trialNumber belongs
            % to: .Block (0 in a random order), .Side, .Start (its first trial) and .Length
            % (the trials drawn for it). The block of the trial prepared before it is in
            % history (notePrepared); queue and pLeftOf say whether the rest of the order
            % can still serve a side.
            block = struct('Block', 0, 'Side', NaN, 'Start', NaN, 'Length', NaN);
            if ~lum.Blocks.isOn(S)
                return
            end
            rest = pLeftOf(queue(trialNumber:end));
            shortest = max(1, round(S.GUI.BlockMin));
            longest = max(shortest, round(S.GUI.BlockMax));
            if history.preparedBlock > 0 && history.preparedTrial == trialNumber - 1
                block = struct('Block', history.blockIndex, 'Side', history.blockSide, ...
                               'Start', history.blockStart, 'Length', history.blockLength);
                inBlock = trialNumber - block.Start;   % Trials it has had so far
                run = 0;
                if history.runBlock == block.Block
                    run = history.blockCorrectRun;
                end
                needed = round(S.GUI.BlockSwitchAfterCorrect);
                if needed > 0
                    over = inBlock >= longest || (inBlock >= shortest && run >= needed);
                else
                    over = inBlock >= block.Length;
                end
                if ~over && any(lum.Blocks.canUse(rest, block.Side))
                    return
                end
            end
            % A new block, on the other side from the last (the first one's at random)
            side = 1 + (rand >= 0.5);
            if any(history.blockSide == [1 2])
                side = 3 - history.blockSide;
            end
            if ~any(lum.Blocks.canUse(rest, side))
                side = 3 - side;
                if ~any(lum.Blocks.canUse(rest, side))
                    block = struct('Block', 0, 'Side', NaN, 'Start', NaN, 'Length', NaN);
                    return   % Nothing left can serve a block: the order as it comes
                end
            end
            block = struct('Block', history.blockIndex + 1, 'Side', side, 'Start', trialNumber, ...
                           'Length', shortest + floor(rand * (longest - shortest + 1)));
        end

        function history = notePrepared(history, spec)
            % notePrepared(history, spec) notes the block of the trial just prepared, which
            % the next one continues or ends (next). Call it after lum.nextTrialSpec, beside
            % lum.HoldShaping.notePrepared.
            if ~isfield(spec, 'Block')
                return
            end
            history.preparedBlock = spec.Block;
            if spec.Block > 0
                history.blockIndex = spec.Block;
                history.blockSide = spec.BlockSide;
                history.blockStart = spec.BlockStart;
                history.blockLength = spec.BlockLength;
            end
        end

        function text = describe(S)
            % describe(S) says in one line how the trial order is decided.
            if ~lum.Blocks.isOn(S)
                text = 'trial order random';
                return
            end
            if S.GUI.BlockSwitchAfterCorrect > 0
                text = sprintf(['trial order in blocks of %d-%d trials, switching after %d '...
                                'correct in a row'], round(S.GUI.BlockMin), round(S.GUI.BlockMax), ...
                               round(S.GUI.BlockSwitchAfterCorrect));
            else
                text = sprintf('trial order in blocks of %d-%d trials, switching by length', ...
                               round(S.GUI.BlockMin), round(S.GUI.BlockMax));
            end
        end

        function [first, position] = firstTrials(block)
            % firstTrials(block) marks each block's first trial in a per-trial Block series
            % (0 outside blocks) and gives each trial's position in its block (1 for the
            % first, NaN outside blocks); vectorised, for the plots and the log.
            block = double(block(:)');
            inBlock = block > 0;
            first = inBlock & [true, block(2:end) ~= block(1:end - 1)];
            position = NaN(size(block));
            starts = find(first);
            for i = 1:numel(starts)
                last = find(block(starts(i):end) ~= block(starts(i)), 1) + starts(i) - 2;
                if isempty(last)
                    last = numel(block);
                end
                position(starts(i):last) = 1:(last - starts(i) + 1);
            end
        end
    end
end
