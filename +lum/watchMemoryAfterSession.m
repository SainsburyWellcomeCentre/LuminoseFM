function logFile = watchMemoryAfterSession(dataFile, seconds)
% lum.watchMemoryAfterSession watches MATLAB's memory for a few minutes after a session.
%
% LUMS0014's desktop sessions of 2026-09-25 and 2026-09-26 ended normally, then about two
% minutes later MATLAB printed "Out of memory." (Windows logged it committing ~180 GB),
% with memory flat at ~4 GB through every trial and the teardown. Nothing of the protocol
% runs by then, and -batch runs exit before it could show. So a separate process watches:
% a PowerShell sampler, started here, writes one row a second for `seconds` to
% <data file>_memory.csv: MATLAB's private and resident memory, the CPU its own (main)
% thread used in that second, and the busiest other thread. If the memory grows while the
% main thread is busy, MATLAB code is allocating (a callback, a timer); if it grows while
% the main thread is idle, a background thread is (the camera engine, .NET, graphics).
% The file starts with the MATLAB timers still running, which are the usual suspects.
%
% Windows only; a desktop session's teardown calls it last, before RunProtocol('Stop').
% It never throws: a sampler that cannot start is a warning.
%
% Arguments:
%   dataFile  The session's data file (BpodSystem.Path.CurrentDataFile)
%   seconds   How long to watch, default 240
%
% Returns the log file's path, or '' when nothing was started.
%
% See also: LuminoseFM, lum.sleep.run

if nargin < 2
    seconds = 240;
end
logFile = '';
if ~ispc || isempty(dataFile)
    return
end
try
    [folder, name] = fileparts(dataFile);
    logFile = fullfile(folder, [name '_memory.csv']);
    writeHeader(logFile, seconds);
    script = fullfile(tempdir, 'LuminoseFM_watchMemory.ps1');
    writeLines(script, samplerScript());
    commandLine = sprintf(['-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%s" '...
                         '%d "%s" %d %d'], script, feature('getpid'), logFile, round(seconds), ...
                        mainThreadId());
    info = System.Diagnostics.ProcessStartInfo('powershell.exe', commandLine);
    info.CreateNoWindow = true;
    info.UseShellExecute = false;
    System.Diagnostics.Process.Start(info);
    fprintf('LuminoseFM: watching MATLAB''s memory for %d s after the session: %s\n', ...
            round(seconds), logFile);
catch watchError
    warning('lum:watchMemoryAfterSession:notStarted', ...
            'MATLAB''s memory is not watched after this session: %s', watchError.message);
    logFile = '';
end
end


function writeHeader(logFile, seconds)
% The timers still running, and the columns, as comment lines above the samples.
lines = {sprintf('# MATLAB memory after the session, one row a second for %d s (lum.watchMemoryAfterSession)', ...
                 round(seconds)), ...
         sprintf('# written %s; MATLAB process %d', char(datetime('now'), 'yyyy-MM-dd HH:mm:ss'), ...
                 feature('getpid'))};
timers = timerfindall;
for k = 1:numel(timers)
    try
        lines{end+1} = sprintf('# timer "%s" running %s, period %g s, executed %d times', ...
                               timers(k).Name, timers(k).Running, timers(k).Period, ...
                               timers(k).TasksExecuted); %#ok<AGROW>
    catch
    end
end
if isempty(timers)
    lines{end+1} = '# no MATLAB timers';
end
lines{end+1} = ['Time,ElapsedSeconds,PrivateGB,WorkingSetGB,Threads,MainThreadCPUSeconds,' ...
                'BusiestThreadId,BusiestThreadCPUSeconds'];
writeLines(logFile, lines);
end


function id = mainThreadId()
% The Windows id of the thread running MATLAB code (the one .NET calls are made on); 0
% when it cannot be read.
id = 0;
try
    id = double(System.AppDomain.GetCurrentThreadId());
catch
end
end


function writeLines(file, lines)
handle = fopen(file, 'w');
if handle < 0
    error('lum:watchMemoryAfterSession:cannotWrite', 'Cannot write %s.', file);
end
closer = onCleanup(@() fclose(handle));
fprintf(handle, '%s\r\n', lines{:});
end


function lines = samplerScript()
% Samples the MATLAB process once a second; appends one CSV row per sample.
lines = {
    'param([int]$ProcessId, [string]$LogFile, [int]$Seconds, [int]$MainThread)'
    '$ErrorActionPreference = ''SilentlyContinue'''
    'try { $p = Get-Process -Id $ProcessId -ErrorAction Stop } catch { exit }'
    '$previous = @{}'
    'foreach ($t in $p.Threads) { $previous[$t.Id] = $t.TotalProcessorTime.TotalSeconds }'
    '$started = Get-Date'
    'while (((Get-Date) - $started).TotalSeconds -lt $Seconds) {'
    '    Start-Sleep -Seconds 1'
    '    $p.Refresh()'
    '    if ($p.HasExited) { break }'
    '    $main = 0.0; $busiestId = 0; $busiest = 0.0; $now = @{}'
    '    foreach ($t in $p.Threads) {'
    '        $cpu = $t.TotalProcessorTime.TotalSeconds'
    '        $now[$t.Id] = $cpu'
    '        $delta = $cpu'
    '        if ($previous.ContainsKey($t.Id)) { $delta = $cpu - $previous[$t.Id] }'
    '        if ($t.Id -eq $MainThread) { $main = $delta }'
    '        elseif ($delta -gt $busiest) { $busiest = $delta; $busiestId = $t.Id }'
    '    }'
    '    $previous = $now'
    '    $row = ''{0},{1:F0},{2:F3},{3:F3},{4},{5:F3},{6},{7:F3}'' -f (Get-Date).ToString(''HH:mm:ss''), ((Get-Date) - $started).TotalSeconds, ($p.PrivateMemorySize64 / 1GB), ($p.WorkingSet64 / 1GB), $p.Threads.Count, $main, $busiestId, $busiest'
    '    Add-Content -Path $LogFile -Value $row'
    '}'
    };
end
