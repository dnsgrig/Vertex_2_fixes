function updatePresynapticCellsAfterSpike(DVModel, allSpike)
% Update presynaptic/postsynaptic state after spikes - this function has
% been added as it was missing in the forked version. It was created to
% reflect similar patterns of update functions in the
% vertext/vertex_simulate / simulatuion folder
% 
% Expected inputs:
%  - DVModel : struct or handle containing connectivity and optionally neuron models
%      e.g. DVModel.connections{preID} = [postID1, postID2, ...]
%           DVModel.NeuronModel{n} = struct or handle for neuron n
%  - allSpike : list of spikes. Common formats supported:
%       - Nx2 numeric array: [preID, spikeTimeIndex]
%       - cell array of [preID, spikeTimeIndex] pairs
%       - vector of preID (no time)
%
% This implementation:
%  - iterates spikes
%  - finds postsynaptic targets using several common field names
%  - for each target, attempts several safe update patterns:
%       * increment a synaptic conductance field (.g_syn) if present
%       * call a method/field .receiveSpike if it exists
%       * accumulate a simple incomingSpikes counter in DVModel if neuron models are plain structs
%
% Needs tailoring to the exact model (e.g. conductance waveform, delay, weight instead of a generic increment).

if isempty(allSpike)
    return;
end

% Normalise allSpike to Nx2 numeric array (preID, timeIndex)
if iscell(allSpike)
    % assume each cell contains [preID, time]
    try
        allSpike = cell2mat(allSpike(:));
    catch
        % fallback: try extracting first two elements of each cell
        tmp = zeros(numel(allSpike),2);
        for ii = 1:numel(allSpike)
            v = allSpike{ii};
            if isnumeric(v) && numel(v) >= 1
                tmp(ii,1) = v(1);
                if numel(v) >= 2, tmp(ii,2) = v(2); end
            end
        end
        allSpike = tmp;
    end
end

if isvector(allSpike) && numel(allSpike) > 0
    % just a list of preIDs
    allSpike = allSpike(:);
    allSpike = [allSpike, zeros(size(allSpike))];
end

if size(allSpike,2) < 2
    allSpike(:,2) = 0; % no time info
end

% Helper to get postsynaptic targets for a given preID using common field names
getTargets = @(preID) getTargetsFromModel(DVModel, preID);

% Optionally access neuron models collection
if isfield(DVModel, 'NeuronModel')
    NeuronModelColl = DVModel.NeuronModel;
else
    NeuronModelColl = [];
end

% Process each spike
for r = 1:size(allSpike,1)
    preID = allSpike(r,1);
    spikeTime = allSpike(r,2); % keep for user-specific updates

    posts = getTargets(preID);
    if isempty(posts)
        continue;
    end

    for p = posts(:).'
        % If neuron models are available and are handles/structs, try to update them
        if ~isempty(NeuronModelColl) && numel(NeuronModelColl) >= p && ~isempty(NeuronModelColl{p})
            nm = NeuronModelColl{p};

            % 1) If model has method/field to receive a spike, call it
            if isobject(nm) && ismethod(nm, 'receiveSpike')
                try
                    nm.receiveSpike(preID, spikeTime);
                    continue;
                catch
                    % fall through to other attempts
                end
            end

            if isstruct(nm)
                % 2) Common pattern: increase synaptic conductance field
                if isfield(nm, 'g_syn')
                    % increment by 1 or by a weight if available in DVModel.weights
                    w = fetchWeight(DVModel, preID, p);
                    nm.g_syn = nm.g_syn + w;
                    NeuronModelColl{p} = nm;
                    continue;
                end

                % 3) Common pattern: record incoming spike times in a list
                if isfield(nm, 'incomingSpikeTimes')
                    nm.incomingSpikeTimes(end+1,1:2) = [spikeTime, preID];
                    NeuronModelColl{p} = nm;
                    continue;
                end
            end

            % 4) If object has property/method named 'addIncomingSpike' or similar
            if isobject(nm) && ismethod(nm, 'addIncomingSpike')
                try
                    nm.addIncomingSpike(preID, spikeTime);
                    continue;
                catch
                end
            end
        end

        % If no neuron model or fall-through, store minimal bookkeeping in DVModel
        if isfield(DVModel, 'incomingSpikes')
            if numel(DVModel.incomingSpikes) < p
                DVModel.incomingSpikes{p} = [];
            end
            DVModel.incomingSpikes{p}(end+1,:) = [spikeTime, preID];
        else
            % create container
            DVModel.incomingSpikes = cell(max(posts),1);
            DVModel.incomingSpikes{p} = [spikeTime, preID];
        end
    end
end

% If we modified NeuronModelColl (struct update), write back
if ~isempty(NeuronModelColl) && isfield(DVModel, 'NeuronModel')
    DVModel.NeuronModel = NeuronModelColl;
end

end

%% Helper functions
function posts = getTargetsFromModel(DVModel, preID)
% Try common field names to obtain postsynaptic targets for preID
posts = [];
possibleFields = {'connections', 'conn', 'Conn', 'Connections', ...
                  'postSynaptic', 'postSyn', 'post', 'targets', 'preToPost'};
for f = possibleFields
    fn = f{1};
    if isfield(DVModel, fn)
        C = DVModel.(fn);
        % accept cell array indexed by preID, or sparse/adjacency matrix
        if iscell(C)
            if numel(C) >= preID && ~isempty(C{preID})
                posts = C{preID};
                return;
            end
        elseif isnumeric(C)
            % adjacency: rows pre, cols post
            if size(C,1) >= preID
                posts = find(C(preID,:));
                return;
            end
        end
    end
end
end

function w = fetchWeight(DVModel, preID, postID)
% Try to obtain a synaptic weight; default to 1
w = 1;
if isempty(DVModel), return; end
if isfield(DVModel,'weights') && ~isempty(DVModel.weights)
    W = DVModel.weights;
    if iscell(W)
        if numel(W) >= preID && ~isempty(W{preID})
            % W{preID} may be vector aligned to posts
            vec = W{preID};
            if numel(vec) >= postID
                w = vec(postID);
                return;
            end
        end
    elseif isnumeric(W)
        if size(W,1) >= preID && size(W,2) >= postID
            w = W(preID, postID);
            return;
        end
    end
end
end