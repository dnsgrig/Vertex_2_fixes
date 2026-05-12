function psave(fileroot, varargin)
% PSAVE compatibility wrapper that forwards to dsave/save safely.
% Usage:
%  psave()                      % default 'matlab' filename per worker
%  psave(fileroot)              % filename (adds index on workers)
%  psave(fileroot, var1, 'a')   % mix of variable values and names
%  psave(fileroot, '-v7.3')     % uses save (dsave disallows format flags)

if nargin < 1 || isempty(fileroot)
    fileroot = 'matlab';
end
if isstring(fileroot), fileroot = char(fileroot); end

% Separate flags (starting with '-') and other args
flags = {};
args  = {};
for k = 1:numel(varargin)
    v = varargin{k};
    if ischar(v) && startsWith(v, '-')
        flags{end+1} = v; %#ok<AGROW>
    else
        args{end+1} = v; %#ok<AGROW>
    end
end

% Build per-worker filename
[folder,name,ext] = fileparts(fileroot);
if isempty(ext), ext = '.mat'; end
isWorker = true;
try idx = labindex; catch isWorker = false; end
if isWorker
    outname = fullfile(folder, sprintf('%s%d%s', name, idx, ext));
else
    outname = fullfile(folder, [name ext]);
end

% If any format flag like '-v7.3' present, use save; otherwise use dsave.
formatFlags = {'-v7.3','-v7','-v6','-nocompression'}; 
useSave = any(ismember(flags, formatFlags));

if useSave
    % Prepare variable NAME list for save called in the caller workspace.
    % For inputs that are variable NAMES (char/string), use them directly.
    % For inputs that are values, assign temporary names into caller workspace.
    names = {};
    tmpNames = {};
    for k = 1:numel(args)
        a = args{k};
        if ischar(a) || isstring(a)
            names{end+1} = char(a); %#ok<AGROW>
        else
            tmp = sprintf('__psave_tmp_%d_%d', feature('getpid'), k);
            assignin('caller', tmp, a);
            names{end+1} = tmp; %#ok<AGROW>
            tmpNames{end+1} = tmp; %#ok<AGROW>
        end
    end

    % Build save command with proper quoting of flags and names
    % Example: save('outname','-v7.3','var1','var2')
    flagStr = '';
    if ~isempty(flags)
        quotedFlags = cellfun(@(s) ['''' s ''''], flags, 'UniformOutput', false);
        flagStr = sprintf(', %s', strjoin(quotedFlags, ', '));
    end
    if isempty(names)
        % save all workspace variables if no variable list given
        cmd = sprintf('save(''%s''%s);', outname, flagStr);
    else
        % quote each variable name as an argument to save
        quotedNames = cellfun(@(s) ['''' s ''''], names, 'UniformOutput', false);
        cmd = sprintf('save(''%s''%s, %s);', outname, flagStr, strjoin(quotedNames, ', '));
    end

    % Execute save in caller workspace (safe single evalin call)
    evalin('caller', cmd);

    % Optionally clean up temporary names we created in caller
    for k = 1:numel(tmpNames)
        evalin('caller', sprintf('clear %s', tmpNames{k}));
    end
else
    % Use dsave: pass variable names or values directly if possible.
    if isempty(args)
        dsave(outname);
    else
        % If args are names (char), pass as names; if values, pass values via cell expansion.
        if all(cellfun(@(x) ischar(x) || isstring(x), args))
            dsave(outname, args{:});
        else
            % Mixed or value inputs: create temp names in caller and call dsave there.
            tmpNames = {};
            for k = 1:numel(args)
                a = args{k};
                if ischar(a) || isstring(a)
                    tmpNames{end+1} = char(a); %#ok<AGROW>
                else
                    tmp = sprintf('__psave_tmp_%d_%d', feature('getpid'), k);
                    assignin('caller', tmp, a);
                    tmpNames{end+1} = tmp; %#ok<AGROW>
                end
            end
            % call dsave in caller workspace
            cmd = sprintf('dsave(''%s'', %s);', outname, strjoin(cellfun(@(s) ['''' s ''''], tmpNames, 'UniformOutput', false), ', '));
            evalin('caller', cmd);

            % cleanup temporary names
            for k = 1:numel(tmpNames)
                if startsWith(tmpNames{k}, '__psave_tmp_')
                    evalin('caller', sprintf('clear %s', tmpNames{k}));
                end
            end
        end
    end
end
end
