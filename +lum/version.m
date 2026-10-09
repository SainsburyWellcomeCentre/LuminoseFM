function text = version(part)
% lum.version returns a version string for the LuminoseFM protocol.
%
% lum.version() is the release and commit; lum.version('release') the release alone, without
% asking git (S.Session.SettingsVersion, written into every settings file).
%
% Recorded in every session file (Data.Session.ProtocolVersion), so a data set can be
% traced back to the code that produced it: the release, then the short git commit,
% as '0.9.10+8634ab8'. The commit comes from git when MATLAB can run it, and otherwise
% from the repository's .git folder (the rig's MATLAB has no git on its path; sessions
% up to 0.9.7 recorded the release alone). With no repository, the release alone.
%
% What each release changed is in docs/naming-and-versions.md (Version history), and
% what to watch for in files written by older releases is in docs/data-format.md
% (Reading older files). Analysis code reads the version before it reads a session.
%
% Bump the release with every change that reaches the rig, and give it a section in
% docs/naming-and-versions.md in the same change.
%
% See also LuminoseFM

release = '0.11.1';
text = release;
if nargin > 0 && strcmp(part, 'release')
    return
end

commit = '';
try
    [status, output] = system(sprintf('git -C "%s" rev-parse --short HEAD', lum.repoRoot));
    if status == 0
        commit = strtrim(output);
    end
catch
    % No git on the system path: read the repository's own files instead.
end
if isempty(commit) || ~all(isstrprop(commit, 'xdigit'))
    commit = commitFromGitFolder(fullfile(lum.repoRoot, '.git'));
end
if ~isempty(commit)
    text = sprintf('%s+%s', release, commit);
end


function commit = commitFromGitFolder(gitFolder)
% The checked-out commit, short, from .git/HEAD and the branch it names (loose or packed);
% '' when there is no repository. MATLAB on the rig has no git on its path, so every session
% up to 0.9.7 recorded the release alone.
commit = '';
try
    head = strtrim(fileread(fullfile(gitFolder, 'HEAD')));
    if startsWith(head, 'ref:')
        ref = strtrim(extractAfter(head, 'ref:'));
        loose = fullfile(gitFolder, strrep(ref, '/', filesep));
        if isfile(loose)
            full = strtrim(fileread(loose));
        else
            full = '';
            packed = splitlines(fileread(fullfile(gitFolder, 'packed-refs')));
            match = packed(endsWith(strtrim(packed), [' ' ref]));
            if ~isempty(match)
                full = strtok(match{1});
            end
        end
    else
        full = head;  % A detached HEAD holds the commit itself
    end
    if numel(full) >= 7 && all(isstrprop(full, 'xdigit'))
        commit = full(1:7);
    end
catch
    % No repository, or one laid out otherwise: the release alone.
end
