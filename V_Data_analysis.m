%% ===========================================================================================
%% ============================= 1. Population characteristics ===============================
%% ===========================================================================================

% Reads the Excel file, renames variables, computes:
%  - N (participants)
%  - N_male (Sex==1), N_female (Sex==0), plus N_missingSex
%  - N_axis1_disorder (ksads_any_diag_excl_elim_lft_v15==1)
%  - Mean, SD, Min, Max, Range for numeric variables (Age, CGAS, CBCL, PSP)
% Writes one Excel output with 4 sheets: ALL, SZ, BP, P
% Adds p-values to the ALL sheet for group differences in:
%  - Age, CGAS, CBCL, PSP (one-way ANOVA)
%  - Number of females / sex distribution across groups (chi-square test)

clear; clc;

% -------------------- INPUTS --------------------
inFile  = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/VIA15_allkey_291124_88participants.xlsx';
outFile = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/VIA15_descriptives_by_group.xlsx';

% Group variable and coding
groupVar = 'HighRiskStatus_v15'; 
groupMap = containers.Map({'SZ','BP','K'}, {'FHR_SZ','FHR_BP','PBC'});

% Variables to rename + classify
renameSpecs = {
    'Incluage_teen_v15',     'Age'   % numeric
    'CGASx_v15',             'CGAS'  % numeric
    'CBCL_totsc_cg_v15',     'CBCL'  % numeric
    'PSP_cg_v15',            'PSP'   % numeric
    'Sex_teen_v15',          'Sex'   % categorical (0=female, 1=male assumed)
};

numericVars = {'Age','CGAS','CBCL','PSP'};
sexVar      = 'Sex';
axis1Var    = 'ksads_any_diag_excl_elim_lft_v15';

% -------------------- LOAD --------------------
K = readtable(inFile);

% Rename columns (only if present; fail loudly if missing)
for i = 1:size(renameSpecs,1)
    oldName = renameSpecs{i,1};
    newName = renameSpecs{i,2};
    if ~ismember(oldName, K.Properties.VariableNames)
        error('Missing expected variable "%s" in the Excel file.', oldName);
    end
    K.Properties.VariableNames = strrep(K.Properties.VariableNames, oldName, newName);
end

% Sanity check group variable exists
if ~ismember(groupVar, K.Properties.VariableNames)
    error('Missing expected group variable "%s" in the Excel file.', groupVar);
end

% Sanity check axis 1 disorder variable exists
if ~ismember(axis1Var, K.Properties.VariableNames)
    error('Missing expected Axis 1 disorder variable "%s" in the Excel file.', axis1Var);
end

% -------------------- TYPE CLEANUP --------------------
% Ensure group is string for reliable comparisons
if iscell(K.(groupVar))
    K.(groupVar) = string(K.(groupVar));
elseif ischar(K.(groupVar))
    K.(groupVar) = string(K.(groupVar));
elseif iscategorical(K.(groupVar))
    K.(groupVar) = string(K.(groupVar));
else
    % If it is numeric-coded, adjust this section to map codes -> labels.
    K.(groupVar) = string(K.(groupVar));
end
K.(groupVar) = strtrim(K.(groupVar));

% Ensure Sex is numeric (0/1). Convert from categorical/string/cell if needed.
if ismember(sexVar, K.Properties.VariableNames)
    if iscategorical(K.(sexVar))
        K.(sexVar) = double(string(K.(sexVar)));
    elseif iscell(K.(sexVar))
        K.(sexVar) = double(string(K.(sexVar)));
    elseif isstring(K.(sexVar))
        K.(sexVar) = double(K.(sexVar));
    end
else
    error('Missing expected sex variable "%s".', sexVar);
end

% Ensure Axis 1 disorder variable is numeric (0/1). Convert from categorical/string/cell if needed.
if isnumeric(K.(axis1Var))
    % do nothing
elseif iscell(K.(axis1Var))
    K.(axis1Var) = double(string(K.(axis1Var)));
elseif isstring(K.(axis1Var))
    K.(axis1Var) = double(K.(axis1Var));
elseif iscategorical(K.(axis1Var))
    K.(axis1Var) = double(string(K.(axis1Var)));
else
    error('Unsupported data type for variable "%s".', axis1Var);
end

% Ensure numeric variables are numeric
for v = 1:numel(numericVars)
    vn = numericVars{v};
    if ~ismember(vn, K.Properties.VariableNames)
        error('Missing expected numeric variable "%s" after renaming.', vn);
    end

    if isnumeric(K.(vn))
        continue;
    elseif iscell(K.(vn))
        K.(vn) = double(string(K.(vn)));
    elseif isstring(K.(vn))
        K.(vn) = double(K.(vn));
    elseif iscategorical(K.(vn))
        K.(vn) = double(string(K.(vn)));
    else
        error('Unsupported data type for variable "%s".', vn);
    end
end

% -------------------- SUMMARY FUNCTION --------------------
makeSummaryTable = @(T) local_makeSummary(T, numericVars, sexVar, axis1Var);

% -------------------- BUILD TABLES --------------------
% 1) ALL groups combined
T_all = makeSummaryTable(K);

% Compute p-values across the 3 groups for ALL sheet only
requestedRaw = {'SZ','BP','K'}; % raw codes expected in data
pVals = local_computePValues(K, numericVars, sexVar, groupVar, requestedRaw);

% Add p-values column to ALL sheet
T_all.P_value = nan(height(T_all),1);
for i = 1:numel(numericVars)
    rowIdx = strcmp(T_all.Variable, numericVars{i});
    if any(rowIdx)
        T_all.P_value(rowIdx) = pVals.(numericVars{i});
    end
end

% Add female-count p-value as an extra row in ALL sheet
femaleRow = T_all(1,:);
femaleRow.Variable = "N_female(Sex==0)";
femaleRow.N_total = height(K);
femaleRow.N_male = sum(K.(sexVar) == 1, 'omitnan');
femaleRow.N_female = sum(K.(sexVar) == 0, 'omitnan');
femaleRow.N_missingSex = sum(isnan(K.(sexVar)));
femaleRow.N_axis1_disorder = sum(K.(axis1Var) == 1, 'omitnan');
femaleRow.Mean = NaN;
femaleRow.SD = NaN;
femaleRow.Min = NaN;
femaleRow.Max = NaN;
femaleRow.Range = NaN;
femaleRow.P_value = pVals.N_female;

T_all = [T_all; femaleRow];

% 2) Each group separately, using the values in groupVar
rawGroups = unique(K.(groupVar));
rawGroups = rawGroups(~ismissing(rawGroups));

% Prepare output: write ALL first
if exist(outFile,'file')
    delete(outFile); % avoid stale sheets from older runs
end
writetable(T_all, outFile, 'Sheet', 'ALL', 'WriteMode', 'overwritesheet');

% Write requested sheets (SZ, BP, P). If one is absent, still write an empty summary.
for i = 1:numel(requestedRaw)
    gRaw = requestedRaw{i};
    if isKey(groupMap, gRaw)
        sheetName = groupMap(gRaw);
    else
        sheetName = gRaw;
    end

    idx = (K.(groupVar) == gRaw);
    if any(idx)
        T_g = makeSummaryTable(K(idx,:));
    else
        % Create a minimal table noting no data
        T_g = table;
        T_g.Note = "No participants found for group code: " + gRaw;
    end

    writetable(T_g, outFile, 'Sheet', sheetName, 'WriteMode', 'overwritesheet');
end

fprintf('Done. Wrote descriptives to:\n%s\n', outFile);

% -------------------- LOCAL FUNCTION --------------------
function S = local_makeSummary(T, numericVars, sexVar, axis1Var)
    % Participant counts
    N = height(T);

    % Sex counts (assumes 1=male, 0=female)
    sex = T.(sexVar);
    N_male   = sum(sex == 1, 'omitnan');
    N_female = sum(sex == 0, 'omitnan');
    N_sex_missing = sum(isnan(sex));

    % Axis 1 disorder counts (1 = yes, 0 = no)
    axis1 = T.(axis1Var);
    N_axis1_disorder = sum(axis1 == 1, 'omitnan');

    % Build numeric summary rows
    varName = strings(numel(numericVars),1);
    Mean    = nan(numel(numericVars),1);
    SD      = nan(numel(numericVars),1);
    Min     = nan(numel(numericVars),1);
    Max     = nan(numel(numericVars),1);
    Range   = nan(numel(numericVars),1);

    for i = 1:numel(numericVars)
        vn = numericVars{i};
        x = T.(vn);
        x = x(~isnan(x));

        varName(i) = string(vn);

        if ~isempty(x)
            Mean(i)  = mean(x);
            SD(i)    = std(x);
            Min(i)   = min(x);
            Max(i)   = max(x);
            Range(i) = Max(i) - Min(i);
        end
    end

    numericSummary = table(varName, Mean, SD, Min, Max, Range, ...
        'VariableNames', {'Variable','Mean','SD','Min','Max','Range'});

    % Put counts at the top (as a small header block)
    countsBlock = table( ...
        ["N_total"; "N_male(Sex==1)"; "N_female(Sex==0)"; "N_missingSex"; "N_axis1_disorder"], ...
        [N; N_male; N_female; N_sex_missing; N_axis1_disorder], ...
        'VariableNames', {'Metric','Value'} ...
    );

    % Combine into one output table with a blank separator row in between
    blank = table(" ", NaN, 'VariableNames', {'Metric','Value'});
    countsBlock2 = countsBlock;
    countsBlock2.Value = double(countsBlock2.Value);

    % Convert numeric summary to the same 2-column style? (Not ideal.)
    % Instead: write as one table by horizontally concatenating blocks would be messy.
    % Best compromise: return a single table with counts repeated as extra columns.
    % This keeps Excel easy to read and avoids “mixed layout” writes.
    %
    % Final table: numeric rows + count columns repeated for context.
    numericSummary.N_total = repmat(N, height(numericSummary), 1);
    numericSummary.N_male  = repmat(N_male, height(numericSummary), 1);
    numericSummary.N_female = repmat(N_female, height(numericSummary), 1);
    numericSummary.N_missingSex = repmat(N_sex_missing, height(numericSummary), 1);
    numericSummary.N_axis1_disorder = repmat(N_axis1_disorder, height(numericSummary), 1);

    % Reorder columns
    S = numericSummary(:, {'Variable','N_total','N_male','N_female','N_missingSex','N_axis1_disorder', ...
                           'Mean','SD','Min','Max','Range'});
end

function pVals = local_computePValues(T, numericVars, sexVar, groupVar, requestedRaw)
    % Restrict to the 3 requested groups only
    validGroupIdx = ismember(T.(groupVar), string(requestedRaw));
    T = T(validGroupIdx,:);

    pVals = struct();

    % Numeric variables: one-way ANOVA across 3 groups
    for i = 1:numel(numericVars)
        vn = numericVars{i};
        x = T.(vn);
        g = T.(groupVar);

        validIdx = ~isnan(x) & ~ismissing(g);
        x = x(validIdx);
        g = g(validIdx);

        if isempty(x) || numel(unique(g)) < 2
            pVals.(vn) = NaN;
        else
            pVals.(vn) = anova1(x, g, 'off');
        end
    end

    % Sex / number of females: chi-square test of sex distribution across groups
    sex = T.(sexVar);
    g   = T.(groupVar);

    validIdx = ~isnan(sex) & ~ismissing(g) & ismember(sex, [0 1]);
    sex = sex(validIdx);
    g   = g(validIdx);

    if isempty(sex) || numel(unique(g)) < 2
        pVals.N_female = NaN;
    else
        % Build 2 x 3 contingency table: rows = female/male, cols = groups
        groupLevels = string(requestedRaw);
        obs = zeros(2, numel(groupLevels));

        for j = 1:numel(groupLevels)
            idx = (g == groupLevels(j));
            obs(1,j) = sum(sex(idx) == 0); % females
            obs(2,j) = sum(sex(idx) == 1); % males
        end

        rowSums = sum(obs, 2);
        colSums = sum(obs, 1);
        totalN  = sum(obs(:));

        expected = (rowSums * colSums) / totalN;

        if any(expected(:) == 0)
            pVals.N_female = NaN;
        else
            chi2 = sum((obs - expected).^2 ./ expected, 'all');
            df = (size(obs,1)-1) * (size(obs,2)-1);
            pVals.N_female = 1 - chi2cdf(chi2, df);
        end
    end
end

%% ===========================================================================================
%% ======================== 2. Counting segments per subject =================================
%% ===========================================================================================

% Scans all *_trimmed25.set in trimmed_path
% Outputs (saved in '5_Data_analysis' folder):
%   - channel_inventory_segments.csv / .mat   (one row per segment)
%   - channel_inventory_subject_summary.csv / .mat (one row per subject)
%
% Requires EEGLAB on path (for pop_loadset). Will try to launch eeglab nogui if needed.

addpath('/home/mathiasha/MATLAB_Add-Ons/Collections/eeglab2026.0.0/')
savepath

fprintf('\n[Channel inventory] Scanning segments and summarizing channels per subject...\n');


% ---------------------------- USER CONFIG (optional) ----------------------------------------
if ~exist('trimmed_path','var') || ~(ischar(trimmed_path) || isstring(trimmed_path))
    % >>>> CHANGE THIS if the data lives elsewhere
    trimmed_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/4_Trimmed_files/';
end
trimmed_path = char(trimmed_path);

% Load data_analysis output folder

data_analysis_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/5_Data_analysis_files/';
data_analysis_path = char(data_analysis_path);

% ----------------------------- EEGLAB I/O availability -------------------------------------
if exist('pop_loadset','file')~=2
    try
        eeglab nogui; close all;
    catch
        error('EEGLAB pop_loadset not found on path. Please add EEGLAB to MATLAB path.');
    end
end

% ------------------------------- File listing & guards --------------------------------------
% >>> MODIFIED LINE: only load files containing "step12"
seg_files = dir(fullfile(trimmed_path, '*step12*_trimmed25.set'));

if isempty(seg_files)
    error('No *_trimmed25.set files found in %s', trimmed_path);
end

% Helpers
toStrList = @(cellstrs) strjoin(string(cellstrs(:))', ',');  % comma-separated list

% EXG exclusion: match EXG1..EXG8 or EXG_1..EXG_8, case-insensitive
% Returns true for any label that is EXG #1-8 (with or without underscore)
is_exg = @(lab) ~isempty( regexpi(strtrim(char(lab)), '^EXG_?([1-8])$','once') );

% Containers
SegRows = table('Size',[0 8], ...
    'VariableTypes', {'string','string','double','double','double','string','string','string'}, ...
    'VariableNames', {'Subject','File','IntervalIdx','N_All','N_Kept','AllLabels','KeptLabels','ExcludedLabels'});

% Per-subject accumulation
subj_union   = containers.Map('KeyType','char','ValueType','any');  % set (cellstr) of kept labels
subj_inter   = containers.Map('KeyType','char','ValueType','any');  % set (cellstr) of kept labels (intersection)
subj_nsegs   = containers.Map('KeyType','char','ValueType','double');

% -------------------------------------- Main walk ------------------------------------------
nFiles = numel(seg_files);
for k = 1:nFiles
    fname = seg_files(k).name;
    fpath = seg_files(k).folder;
    try
        [~, base] = fileparts(fname);

        % Parse Subject (first 3 digits) and interval index from "timepoint_<start>-timepoint_<end>"
        subj_id = regexp(base, '^\d{3}', 'match', 'once');
        toks    = regexp(base, 'timepoint_(\d+)-timepoint_(\d+)', 'tokens', 'once');
        if isempty(subj_id) || isempty(toks)
            fprintf('  ⚠️ Skipping (unparsable name): %s\n', fname);
            continue;
        end
        start_pt = str2double(toks{1});
        if ~isfinite(start_pt)
            fprintf('  ⚠️ Skipping (bad start time): %s\n', fname);
            continue;
        end
        interval_idx = round(start_pt/30) + 1; % 1..12

        % Load header/data (EEGLAB)
        EEG = pop_loadset('filename', fname, 'filepath', fpath);
        if isempty(EEG) || ~isfield(EEG,'chanlocs') || isempty(EEG.chanlocs)
            fprintf('  ⚠️ Skipping (no chanlocs): %s\n', fname);
            continue;
        end

        % Extract channel labels present in file
        file_labels = strings(1, numel(EEG.chanlocs));
        for ch = 1:numel(EEG.chanlocs)
            if isfield(EEG.chanlocs(ch),'labels') && ~isempty(EEG.chanlocs(ch).labels)
                file_labels(ch) = string(EEG.chanlocs(ch).labels);
            else
                file_labels(ch) = "Ch"+string(ch);
            end
        end
        file_labels = unique(file_labels(~ismissing(file_labels)));
        file_labels = file_labels(:);

        % Apply EXG-only exclusion (EXG1..8 and EXG_1.._8)
        keep_mask = ~arrayfun(is_exg, file_labels);
        kept_labels    = file_labels(keep_mask);
        dropped_labels = file_labels(~keep_mask);

        % Add segment-level row
        SegRows = [SegRows; {
            string(subj_id), string(fname), double(interval_idx), ...
            double(numel(file_labels)), double(numel(kept_labels)), ...
            toStrList(file_labels), toStrList(kept_labels), toStrList(dropped_labels)
        }]; %#ok<AGROW>

        % Update per-subject union/intersection
        sid = char(subj_id);
        if ~isKey(subj_union, sid)
            subj_union(sid) = cellstr(kept_labels);
            subj_inter(sid) = cellstr(kept_labels);
            subj_nsegs(sid) = 1;
        else
            % union
            u = unique([subj_union(sid); cellstr(kept_labels)]);
            subj_union(sid) = u;

            % intersection
            i_prev = subj_inter(sid);
            i_now  = intersect(i_prev, cellstr(kept_labels));
            subj_inter(sid) = i_now;

            subj_nsegs(sid) = subj_nsegs(sid) + 1;
        end

        if mod(k, 30)==0 || k==nFiles
            fprintf('  processed %d/%d files...\n', k, nFiles);
        end
    catch ME
        fprintf('⚠️ Channel inventory error in %s: %s\n', fname, ME.message);
        % continue to next file
    end
end

% -------------------------------- Subject summary table ------------------------------------
all_subjects = sort(keys(subj_union));
SubjRows = table('Size',[numel(all_subjects) 6], ...
    'VariableTypes', {'string','double','double','double','string','string'}, ...
    'VariableNames', {'Subject','NSegments','UnionCount','IntersectionCount','UnionLabels','IntersectionLabels'});

for i = 1:numel(all_subjects)
    sid = all_subjects{i};
    U = subj_union(sid);
    I = subj_inter(sid);
    nseg = subj_nsegs(sid);
    SubjRows(i, :) = { string(sid), double(nseg), double(numel(U)), double(numel(I)), ...
                   toStrList(U), toStrList(I) };
end

% ---------------------------------------- Save logs ----------------------------------------
seg_csv   = fullfile(data_analysis_path, 'channel_inventory_segments.csv');
subj_csv  = fullfile(data_analysis_path, 'channel_inventory_subject_summary.csv');
seg_mat   = fullfile(data_analysis_path, 'channel_inventory_segments.mat');
subj_mat  = fullfile(data_analysis_path, 'channel_inventory_subject_summary.mat');

try
    if ~isempty(SegRows)
        writetable(SegRows, seg_csv);
        save(seg_mat, 'SegRows', '-v7.3');
    else
        warning('Segment table is empty; no segment CSV/MAT written.');
    end

    if ~isempty(SubjRows)
        writetable(SubjRows, subj_csv);
        save(subj_mat, 'SubjRows', '-v7.3');
    else
        warning('Subject table is empty; no subject CSV/MAT written.');
    end

    fprintf('[Channel inventory] Saved:\n  %s\n  %s\n  %s\n  %s\n', seg_csv, subj_csv, seg_mat, subj_mat);
catch ME
    warning('Could not save channel inventory logs: %s');
end

% ------------------------------- Quick console summary -------------------------------------
if ~isempty(SubjRows)
    [~, ord] = sort(SubjRows.UnionCount, 'descend');
    headN = min(5, height(SubjRows));
    fprintf('\n[Channel inventory] Top %d subjects by kept-channel union:\n', headN);
    for j = 1:headN
        r = SubjRows(ord(j),:);
        fprintf('  %s: union=%d, intersection=%d, nSeg=%d\n', ...
            r.Subject, r.UnionCount, r.IntersectionCount, r.NSegments);
    end
else
    fprintf('\n[Channel inventory] No subjects summarized (empty table).\n');
end

%% ===========================================================================================
%% ====================== 2.1 Counting channels and segments per group =======================
%% ===========================================================================================
%
% This script works independently of the earlier code.
%
% It reads:
%   1) channel_inventory_segments.csv
%      - must contain at least:
%           Subject   (e.g., "101")
%           N_Kept    (number of non-EXG channels kept in that segment)
%
%   2) VIA15_allkey_291124_88participants.xlsx
%      - used to map each subject to group
%
% It outputs:
%   group_segment_channel_summary.csv
%
% Output columns:
%   Group
%   N_Participants_WithSegments
%   Total_Segments_Kept
%   Avg_Segments_PerParticipant
%   Avg_Channels_PerSegment
%
% Important:
% - Avg_Segments_PerParticipant is computed among participants in that group
%   who appear in the segment inventory CSV.
% - Avg_Channels_PerSegment is computed across all kept segments in that group.
%
% For averages relative to all participants in the group from the key
% file (including participants with zero segments), that is a different quantity.
% This script does NOT do that unless modified.
%
% -------------------------------------------------------------------------------------------

clear; clc;

% -------------------- USER INPUTS ----------------------------------------------------------
inventoryCsv = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/5_Data_analysis_files/channel_inventory_segments.csv';
keyFile      = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/VIA15_allkey_291124_88participants.xlsx';
outCsv       = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/5_Data_analysis_files/group_segment_channel_summary.csv';
chanloc_file = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/biosemi128.sfp';

% Additional outputs for channels present for all participants in >=1 segment
outCommonChannelsCsv = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/5_Data_analysis_files/channels_present_for_all_participants_min1segment.csv';
outCommonChannelsPng = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/5_Data_analysis_files/channels_present_for_all_participants_min1segment_topomap.png';

% Group variable in the key file
groupVar = 'HighRiskStatus_v15';

% Subject ID variable in the key file
% Change this if the ID column has a different name.
subjectVarCandidates = {'famlbnr'};

% Candidate variable names in the inventory CSV that may store channel labels
channelVarCandidates = {'Kept_Channel_Labels','KeptChannels','Channels_Kept','ChannelLabels_Kept', ...
                        'KeptLabels','ChannelLabels','Channels','Labels','Kept_Channels'};

% Raw group codes in the key file -> output labels
groupMap = containers.Map( ...
    {'SZ','BP','K'}, ...
    {'FHR_SZ','FHR_BP','PBC'} ...
);

requestedRawGroups = {'SZ','BP','K'};

% -------------------- LOAD INVENTORY CSV ---------------------------------------------------
if ~exist(inventoryCsv, 'file')
    error('Inventory CSV not found: %s', inventoryCsv);
end

Seg = readtable(inventoryCsv, 'TextType', 'string');

requiredInvVars = {'Subject','N_Kept'};
for i = 1:numel(requiredInvVars)
    if ~ismember(requiredInvVars{i}, Seg.Properties.VariableNames)
        error('Missing required variable "%s" in inventory CSV.', requiredInvVars{i});
    end
end

% Find channel-label variable automatically
channelVar = "";
for i = 1:numel(channelVarCandidates)
    if ismember(channelVarCandidates{i}, Seg.Properties.VariableNames)
        channelVar = string(channelVarCandidates{i});
        break;
    end
end

if channelVar == ""
    error(['Could not find a channel label column in the inventory CSV. ', ...
           'Looked for: %s'], strjoin(channelVarCandidates, ', '));
end
channelVar = char(channelVar);

% Clean Subject
Seg.Subject = string(Seg.Subject);
Seg.Subject = strtrim(Seg.Subject);

% Clean N_Kept
if ~isnumeric(Seg.N_Kept)
    if iscell(Seg.N_Kept)
        Seg.N_Kept = double(string(Seg.N_Kept));
    elseif isstring(Seg.N_Kept)
        Seg.N_Kept = double(Seg.N_Kept);
    elseif iscategorical(Seg.N_Kept)
        Seg.N_Kept = double(string(Seg.N_Kept));
    else
        error('Unsupported type for Seg.N_Kept.');
    end
end

% Clean channel label variable
Seg.(channelVar) = string(Seg.(channelVar));
Seg.(channelVar) = strtrim(Seg.(channelVar));

% Remove rows with missing essential info
validSeg = ~ismissing(Seg.Subject) & strlength(Seg.Subject) > 0 & ~isnan(Seg.N_Kept);
Seg = Seg(validSeg,:);

if isempty(Seg)
    error('No valid rows found in inventory CSV after cleaning.');
end

% -------------------- LOAD KEY FILE --------------------------------------------------------
if ~exist(keyFile, 'file')
    error('Key file not found: %s', keyFile);
end

K = readtable(keyFile, 'TextType', 'string');

if ~ismember(groupVar, K.Properties.VariableNames)
    error('Group variable "%s" not found in key file.', groupVar);
end

% Find subject ID column automatically
subjectVar = "";
for i = 1:numel(subjectVarCandidates)
    if ismember(subjectVarCandidates{i}, K.Properties.VariableNames)
        subjectVar = string(subjectVarCandidates{i});
        break;
    end
end

if subjectVar == ""
    error(['Could not find a subject ID column in the key file. ', ...
           'Looked for: %s'], strjoin(subjectVarCandidates, ', '));
end

subjectVar = char(subjectVar);

% Clean subject IDs
K.(subjectVar) = string(K.(subjectVar));
K.(subjectVar) = strtrim(K.(subjectVar));

% Keep only needed columns
K = K(:, {subjectVar, groupVar});
K.Properties.VariableNames = {'Subject','GroupRaw'};

% Clean group variable
K.GroupRaw = string(K.GroupRaw);
K.GroupRaw = strtrim(K.GroupRaw);

% Keep only requested groups
K = K(ismember(K.GroupRaw, string(requestedRawGroups)), :);

if isempty(K)
    error('No matching requested groups (%s) found in key file.', strjoin(requestedRawGroups, ', '));
end

% Remove duplicate subjects in key file, but fail loudly if conflicting group assignments exist
[uSubs, ~, ic] = unique(K.Subject);
keepIdx = true(height(K),1);

for i = 1:numel(uSubs)
    idx = (ic == i);
    g = unique(K.GroupRaw(idx));
    g = g(~ismissing(g));

    if numel(g) > 1
        error('Subject %s has multiple group assignments in key file: %s', ...
            uSubs(i), strjoin(cellstr(g), ', '));
    end

    firstRow = find(idx, 1, 'first');
    dupRows = find(idx);
    dupRows(dupRows == firstRow) = [];
    keepIdx(dupRows) = false;
end

K = K(keepIdx,:);

% -------------------- MERGE SEGMENTS WITH GROUP --------------------------------------------
SegGroup = outerjoin(Seg, K, ...
    'Keys', 'Subject', ...
    'MergeKeys', true, ...
    'Type', 'left');

% Warn about segment subjects not found in key file
missingGroupIdx = ismissing(SegGroup.GroupRaw) | strlength(SegGroup.GroupRaw) == 0;
if any(missingGroupIdx)
    missingSubs = unique(SegGroup.Subject(missingGroupIdx));
    warning('%d subject(s) in inventory CSV were not found in key file and will be excluded: %s', ...
        numel(missingSubs), strjoin(cellstr(missingSubs), ', '));
    SegGroup = SegGroup(~missingGroupIdx,:);
end

if isempty(SegGroup)
    error('After merging with the key file, no segment rows remained.');
end

% -------------------- MAP RAW GROUP CODES TO OUTPUT LABELS ---------------------------------
SegGroup.Group = strings(height(SegGroup),1);

for i = 1:height(SegGroup)
    rawG = char(SegGroup.GroupRaw(i));
    if isKey(groupMap, rawG)
        SegGroup.Group(i) = string(groupMap(rawG));
    else
        SegGroup.Group(i) = missing;
    end
end

SegGroup = SegGroup(~ismissing(SegGroup.Group), :);

if isempty(SegGroup)
    error('No rows remained after group mapping.');
end

%%-------------------- COMPUTE GROUP-LEVEL SUMMARY ------------------------------------------
outGroupOrder = {'FHR_SZ','FHR_BP','PBC'};

Summary = table('Size', [0 5], ...
    'VariableTypes', {'string','double','double','double','double'}, ...
    'VariableNames', {'Group', ...
                      'N_Participants_WithSegments', ...
                      'Total_Segments_Kept', ...
                      'Avg_Segments_PerParticipant', ...
                      'Avg_Channels_PerSegment'});

for i = 1:numel(outGroupOrder)
    thisGroup = string(outGroupOrder{i});
    idxG = (SegGroup.Group == thisGroup);

    if ~any(idxG)
        Summary = [Summary; {thisGroup, 0, 0, NaN, NaN}]; %#ok<AGROW>
        continue;
    end

    Tg = SegGroup(idxG,:);

    % Total number of kept segments in group = number of rows
    totalSegments = height(Tg);

    % Number of participants with at least one segment in this group
    subjList = unique(Tg.Subject);
    nParticipants = numel(subjList);

    % Average number of segments per participant
    segsPerSubj = zeros(nParticipants,1);
    for s = 1:nParticipants
        segsPerSubj(s) = sum(Tg.Subject == subjList(s));
    end
    avgSegsPerParticipant = mean(segsPerSubj);

    % Average number of kept channels per segment
    avgChannelsPerSegment = mean(Tg.N_Kept, 'omitnan');

    Summary = [Summary; {thisGroup, ...
                         double(nParticipants), ...
                         double(totalSegments), ...
                         double(avgSegsPerParticipant), ...
                         double(avgChannelsPerSegment)}]; %#ok<AGROW>
end

%%-------------------- CHANNELS PRESENT FOR ALL PARTICIPANTS IN >=1 SEGMENT -----------------
allSubjectsWithSegments = unique(SegGroup.Subject);
nSubjectsWithSegments = numel(allSubjectsWithSegments);

if nSubjectsWithSegments == 0
    error('No participants with segments found after merging and cleaning.');
end

subjectChannelSets = cell(nSubjectsWithSegments,1);
subjectsWithParsableChannels = false(nSubjectsWithSegments,1);

for s = 1:nSubjectsWithSegments
    thisSub = allSubjectsWithSegments(s);
    idxSub = (SegGroup.Subject == thisSub);
    Tsub = SegGroup(idxSub,:);

    unionChannelsThisSubject = strings(0,1);

    for r = 1:height(Tsub)
        chanStr = Tsub.(channelVar)(r);
        chanList = parse_channel_string(chanStr);

        if ~isempty(chanList)
            unionChannelsThisSubject = union(unionChannelsThisSubject, chanList(:), 'stable');
        end
    end

    unionChannelsThisSubject = unique(unionChannelsThisSubject, 'stable');
    subjectChannelSets{s} = unionChannelsThisSubject;
    subjectsWithParsableChannels(s) = ~isempty(unionChannelsThisSubject);
end

if ~all(subjectsWithParsableChannels)
    badSubs = allSubjectsWithSegments(~subjectsWithParsableChannels);
    warning(['%d subject(s) had segments but no parsable channel labels in "%s" and were excluded ', ...
             'from the common-channel intersection: %s'], ...
             numel(badSubs), channelVar, strjoin(cellstr(badSubs), ', '));
end

validSubjectChannelSets = subjectChannelSets(subjectsWithParsableChannels);
validSubjects = allSubjectsWithSegments(subjectsWithParsableChannels);
nValidSubjects = numel(validSubjects);

if nValidSubjects == 0
    warning(['No parsable channel labels were found for any participant. ', ...
             'CSV will be saved empty, and no topographic image will be created.']);
    commonChannels = strings(0,1);
else
    commonChannels = validSubjectChannelSets{1};
    for s = 2:nValidSubjects
        commonChannels = intersect(commonChannels, validSubjectChannelSets{s}, 'stable');
    end
    commonChannels = sort(commonChannels);
end

CommonChannelsTable = table(commonChannels, 'VariableNames', {'Channel'});
writetable(CommonChannelsTable, outCommonChannelsCsv);

if isempty(commonChannels)
    warning(['No channels were found that are present for every participant in at least one segment. ', ...
             'CSV was saved, but no topographic image will be created.']);
else
    if ~exist(chanloc_file, 'file')
        warning('Chanloc file not found: %s. CSV was saved, but no topographic image was created.', chanloc_file);
    else
        if exist('readlocs', 'file') ~= 2
            warning('EEGLAB function readlocs not found on path. CSV was saved, but no topographic image was created.');
        elseif exist('topoplot', 'file') ~= 2
            warning('EEGLAB function topoplot not found on path. CSV was saved, but no topographic image was created.');
        else
            chanlocs = readlocs(chanloc_file);

            allLocLabels = strings(numel(chanlocs),1);
            for c = 1:numel(chanlocs)
                allLocLabels(c) = upper(strtrim(string(chanlocs(c).labels)));
            end

            commonChannelsNorm = upper(strtrim(commonChannels));
            matchIdx = ismember(allLocLabels, commonChannelsNorm);

            if ~any(matchIdx)
                warning(['Common channels were found in the CSV, but none matched labels in the chanloc file. ', ...
                         'CSV was saved, but no topographic image was created.']);
            else
                topoVals = zeros(numel(chanlocs),1);
                topoVals(matchIdx) = 1;

                figure('Color','w','Position',[100 100 900 800]);
                topoplot(topoVals, chanlocs, ...
                    'style', 'map', ...
                    'electrodes', 'labelpoint', ...
                    'plotrad', 0.6, ...
                    'headrad', 0.6);

                title(sprintf(['Channels present for all participants in >=1 segment\n', ...
                               '(N = %d channels; %d participants)'], ...
                               numel(commonChannels), nValidSubjects), ...
                      'FontWeight', 'bold');

                exportgraphics(gcf, outCommonChannelsPng, 'Resolution', 300);
                close(gcf);
            end
        end
    end
end

% -------------------- SAVE OUTPUT ----------------------------------------------------------
writetable(Summary, outCsv);

fprintf('\nDone.\nSaved group summary to:\n%s\n\n', outCsv);
disp(Summary);

fprintf('Saved common-channel list to:\n%s\n', outCommonChannelsCsv);
if exist(outCommonChannelsPng, 'file')
    fprintf('Saved common-channel topographic image to:\n%s\n\n', outCommonChannelsPng);
else
    fprintf('Common-channel topographic image was not created.\n\n');
end

%% -------------------- LOCAL FUNCTIONS -----------------------------------------------------
function chanList = parse_channel_string(chanStr)

chanStr = string(chanStr);
chanStr = strtrim(chanStr);

if ismissing(chanStr) || strlength(chanStr) == 0
    chanList = strings(0,1);
    return;
end

% Remove common wrappers/brackets/quotes
chanStr = regexprep(chanStr, '[\[\]\{\}\(\)"'']', '');

% Also replace colons/equal signs that sometimes appear in exported text
chanStr = regexprep(chanStr, '[:=]', ' ');

% Split on common delimiters
parts = regexp(char(chanStr), '[,;|/\s]+', 'split');
parts = string(parts(:));
parts = strtrim(parts);
parts = upper(parts);

% Remove empties and obvious non-channel tokens
parts = parts(~ismissing(parts) & strlength(parts) > 0);
parts = parts(~ismember(parts, ["NAN","MISSING","NONE","NULL"]));

chanList = unique(parts, 'stable');
end


%% ===== 2.2 Evaluating no. of channels per participant at each preprocessing step ===========
%
% ============================================================
%  Count channels from QC CSV files across preprocessing steps
%
%  Input:
%    *_qc.csv files in:
%    /mnt/projects/VIA_MHA/VIA15_Rest/Final/1_Preprocessed_files/Logs/
%
%
%  IMPORTANT:
%  - This script uses ONLY files ending in "_qc.csv"
%  - It EXCLUDES files ending in "_qc_summary.csv"
%  - It extracts channels from the "Channel" column in each CSV
%
%  Output:
%    Excel file with 2 sheets:
%      Sheet 1: subjects x steps, values = number of channels
%      Sheet 2: per step:
%               row 1 = number of channels shared by all subjects
%               row 2 = names of shared channels
% ============================================================

clear; clc;

% -------------------- USER SETTINGS -------------------------
inputFolder = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/1_Preprocessed_files/Logs/';
outputFile  = fullfile(inputFolder, 'channel_count_overview_from_qc_csv.xlsx');

% Set to true to print progress in Command Window
verbose = true;
% ------------------------------------------------------------

% Check input folder
if ~isfolder(inputFolder)
    error('Input folder does not exist:\n%s', inputFolder);
end

% Get all CSV files
allCsvFiles = dir(fullfile(inputFolder, '*.csv'));

if isempty(allCsvFiles)
    error('No .csv files found in:\n%s', inputFolder);
end

% Keep only files ending in "_qc.csv" and exclude "_qc_summary.csv"
keepIdx = false(numel(allCsvFiles), 1);
for i = 1:numel(allCsvFiles)
    fname = allCsvFiles(i).name;
    if endsWith(fname, '_qc.csv') && ~endsWith(fname, '_qc_summary.csv')
        keepIdx(i) = true;
    end
end

fileList = allCsvFiles(keepIdx);

if isempty(fileList)
    error('No files ending in "_qc.csv" (excluding "_qc_summary.csv") were found in:\n%s', inputFolder);
end

% -----------------------------------------------------------------------
%  Parse filenames
%  Expected format:
%    SUBJECT_STEPNAME_qc.csv
%
%  Example:
%    025_step01_loaded_qc.csv
%
%  Subject = everything before first "_step"
%  Step    = everything after subject + "_" and before "_qc.csv"
% -----------------------------------------------------------------------
subjects = {};
steps    = {};

parsedInfo = struct( ...
    'filename', {}, ...
    'subject',  {}, ...
    'step',     {} );

for i = 1:numel(fileList)
    fname = fileList(i).name;

    % Match subject + step, only for *_qc.csv
    tok = regexp(fname, '^(.*?)_(step.*)_qc\.csv$', 'tokens', 'once');

    if isempty(tok)
        warning('Skipping file with unexpected name format: %s', fname);
        continue;
    end

    subjID   = strtrim(tok{1});
    stepName = strtrim(tok{2});

    parsedInfo(end+1).filename = fname; %#ok<SAGROW>
    parsedInfo(end).subject    = subjID;
    parsedInfo(end).step       = stepName;

    subjects{end+1} = subjID; %#ok<SAGROW>
    steps{end+1}    = stepName; %#ok<SAGROW>
end

if isempty(parsedInfo)
    error('No files could be parsed. Check filename format.');
end

subjects = unique(subjects, 'stable');
steps    = unique(steps, 'stable');

% Sort subjects numerically if possible
subjNum = nan(numel(subjects),1);
for i = 1:numel(subjects)
    tmp = str2double(subjects{i});
    if ~isnan(tmp)
        subjNum(i) = tmp;
    end
end
if all(~isnan(subjNum))
    [~, idxSort] = sort(subjNum);
    subjects = subjects(idxSort);
end

% Sort steps by step number first, then alphabetically within same number
stepNum = nan(numel(steps),1);
for i = 1:numel(steps)
    tok = regexp(steps{i}, '^step(\d+)', 'tokens', 'once');
    if ~isempty(tok)
        stepNum(i) = str2double(tok{1});
    end
end

[~, idxStepSort] = sortrows([stepNum(:), (1:numel(steps))']);
steps = steps(idxStepSort);

nSubj = numel(subjects);
nStep = numel(steps);

% Create lookup maps
subjectMap = containers.Map(subjects, 1:nSubj);
stepMap    = containers.Map(steps,    1:nStep);

% Preallocate results
channelCountMatrix = nan(nSubj, nStep);

% Store channel labels for each subject x step
channelLabels = cell(nSubj, nStep);

% Track duplicates
seenMatrix = false(nSubj, nStep);

% -------------------- LOAD FILES AND EXTRACT CHANNEL INFO ----------------
for i = 1:numel(parsedInfo)
    fname    = parsedInfo(i).filename;
    subjID   = parsedInfo(i).subject;
    stepName = parsedInfo(i).step;

    rowIdx = subjectMap(subjID);
    colIdx = stepMap(stepName);

    if seenMatrix(rowIdx, colIdx)
        warning(['Duplicate file detected for subject %s and step %s. ' ...
                 'Later file will overwrite earlier one.\nFile: %s'], ...
                 subjID, stepName, fname);
    end

    fullPath = fullfile(inputFolder, fname);

    if verbose
        fprintf('Loading %s\n', fname);
    end

    try
        T = readtable(fullPath, 'TextType', 'string');
    catch ME
        warning('Could not load %s\nReason: %s', fname, ME.message);
        continue;
    end

    if isempty(T)
        warning('File %s is empty. Skipping.', fname);
        continue;
    end

    % Find the Channel column robustly
    varNames = T.Properties.VariableNames;
    chanColIdx = find(strcmpi(varNames, 'Channel'), 1);

    if isempty(chanColIdx)
        warning('File %s does not contain a "Channel" column. Skipping.', fname);
        continue;
    end

    % Extract channel labels
    rawLabels = T{:, chanColIdx};

    % Convert to string safely
    if iscell(rawLabels)
        rawLabels = string(rawLabels);
    elseif ischar(rawLabels)
        rawLabels = string(cellstr(rawLabels));
    elseif iscategorical(rawLabels)
        rawLabels = string(rawLabels);
    elseif isnumeric(rawLabels)
        rawLabels = string(rawLabels);
    elseif ~isstring(rawLabels)
        try
            rawLabels = string(rawLabels);
        catch
            warning('Could not convert Channel column to strings in file %s. Skipping.', fname);
            continue;
        end
    end

    % Clean labels: trim spaces, remove missing/empty
    rawLabels = strtrim(rawLabels);
    rawLabels = rawLabels(~ismissing(rawLabels));
    rawLabels = rawLabels(rawLabels ~= "");

    % Keep unique while preserving order
    labels = unique(cellstr(rawLabels), 'stable');

    if isempty(labels)
        warning('No valid channel labels found in file %s. Skipping.', fname);
        continue;
    end

    nChan = numel(labels);

    channelCountMatrix(rowIdx, colIdx) = nChan;
    channelLabels{rowIdx, colIdx}      = labels;
    seenMatrix(rowIdx, colIdx)         = true;
end

% -------------------- SHEET 1 TABLE: SUBJECTS x STEPS --------------------
sheet1Table = array2table(channelCountMatrix, ...
    'VariableNames', matlab.lang.makeValidName(steps, 'ReplacementStyle', 'delete'));

sheet1Table = addvars(sheet1Table, subjects(:), 'Before', 1, 'NewVariableNames', 'Subject');

% -------------------- SHEET 2: SHARED CHANNELS PER STEP ------------------
sharedCount = nan(1, nStep);
sharedNames = cell(1, nStep);

for s = 1:nStep
    labelsThisStep = channelLabels(:, s);

    % Only include subjects that actually have that step
    hasData = ~cellfun(@isempty, labelsThisStep);

    if ~any(hasData)
        sharedCount(s) = NaN;
        sharedNames{s} = '';
        continue;
    end

    validLabelSets = labelsThisStep(hasData);

    % Start intersection with first available subject
    commonLabels = validLabelSets{1};

    for k = 2:numel(validLabelSets)
        commonLabels = intersect(commonLabels, validLabelSets{k}, 'stable');
    end

    sharedCount(s) = numel(commonLabels);

    if isempty(commonLabels)
        sharedNames{s} = '';
    else
        sharedNames{s} = strjoin(commonLabels, ', ');
    end
end

% Build Sheet 2 as a table with first column describing the row
sheet2Cell = cell(2, nStep + 1);
sheet2Cell(1,1) = {'Shared_channel_count'};
sheet2Cell(2,1) = {'Shared_channel_names'};

for s = 1:nStep
    sheet2Cell{1, s+1} = sharedCount(s);
    sheet2Cell{2, s+1} = sharedNames{s};
end

sheet2Table = cell2table(sheet2Cell, ...
    'VariableNames', ['Metric', matlab.lang.makeValidName(steps, 'ReplacementStyle', 'delete')]);

% -------------------- WRITE EXCEL FILE -----------------------------------
if exist(outputFile, 'file')
    delete(outputFile);
end

try
    writetable(sheet1Table, outputFile, 'Sheet', 'Channel_Counts', 'WriteMode', 'overwritesheet');
    writetable(sheet2Table, outputFile, 'Sheet', 'Shared_Channels', 'WriteMode', 'overwritesheet');
catch ME
    error('Could not write Excel file:\n%s\nReason: %s', outputFile, ME.message);
end

% -------------------- OPTIONAL SUMMARY IN COMMAND WINDOW -----------------
fprintf('\nDone.\n');
fprintf('Excel file saved to:\n%s\n\n', outputFile);
fprintf('Number of subjects: %d\n', nSubj);
fprintf('Number of steps:    %d\n', nStep);

missingEntries = sum(isnan(channelCountMatrix), 'all');
fprintf('Missing subject-step entries: %d\n', missingEntries);


%% ===========================================================================================
%% ==================== 3. Computation of complexity measures ================================
%% ===========================================================================================

%% -- %% Complexity measures computation (NaN-aware) — NOW: HFD + Permutation Entropy ONLY

clear; clc;
eeglab nogui;

% ---------------- User paths ----------------
trimmed_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/4_Trimmed_files/';
trimmed_path = char(trimmed_path);
data_analysis_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/5_Data_analysis_files/';
data_analysis_path = char(data_analysis_path);
excel_file   = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/VIA15_Masterfile_Cleaned.xlsx';
chanloc_file = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/biosemi128.sfp';
results_file = fullfile(data_analysis_path, 'complexity_results_all_steps_final.mat');  % contains per-channel results now

% ---------------- Channels ------------------
exg_channels = {'EXG1','EXG2','EXG3','EXG4','EXG5','EXG6','EXG7','EXG8'};
excluded_channels = unique([exg_channels]);

% ---------------- Intervals -----------------
interval_labels = { ...
 'timepoint_0_to_30','timepoint_30_to_60','timepoint_60_to_90','timepoint_90_to_120', ...
 'timepoint_120_to_150','timepoint_150_to_180','timepoint_180_to_210','timepoint_210_to_240', ...
 'timepoint_240_to_270','timepoint_270_to_300','timepoint_300_to_330','timepoint_330_to_360'};

% --------------- Speed knobs ----------------
target_fs_entropy = 200;   % Hz for PE (downsample if fs is higher)
max_N_entropy     = 3000;  % max samples for PE after downsampling
KmaxFD            = 10;    % Higuchi FD Kmax
mPE               = 4; tauPE = 1;     % Permutation entropy params
min_run_seconds   = 2;     % minimum contiguous non-NaN run length

% --------------- Load groups ----------------
T = readtable(excel_file, 'VariableNamingRule','preserve');
vars = T.Properties.VariableNames;
use_col = '';
if any(strcmp(vars,'hgr_status')), use_col = 'hgr_status';
elseif any(strcmp(vars,'fhr_group')), use_col = 'fhr_group';
else, error('Missing hgr_status/fhr_group in Excel.'); end

subject_groups = containers.Map('KeyType','char','ValueType','char');
for i = 1:height(T)
    if isnan(T.id(i)), continue; end
    sid = sprintf('%03d', T.id(i));
    v = T.(use_col)(i); if iscell(v), v = v{1}; end
    v = string(v);
    if ~ismissing(v) && strlength(v)>0
        subject_groups(sid) = char(v);
    end
end

% --------------- Files & results ------------
segment_files = dir(fullfile(trimmed_path, '*_trimmed25.set'));
results = struct('subj_id',{},'group',{},'condition',{}, ...
                 'interval_idx',{},'interval_key',{}, ...
                 'preprocessing_step',{}, ...
                 'channel_labels_all',{},'included_mask',{},'channel_labels_included',{}, ...
                 'fd',{},'permEnt',{});

% ----------------- Main loop ----------------
for f = 1:length(segment_files)
    try
        t0 = tic;
        file = segment_files(f).name;
        [~, name] = fileparts(file);

        % subj_id = first three digits at the start of the filename (e.g., '408')
        subj_id = regexp(name, '^\d{3}', 'match', 'once');
        if isempty(subj_id), continue; end
        
        % Extract preprocessing step from filename (e.g., 'step01', 'step12')
        step_tok = regexp(name, '_(step\d{2})_', 'tokens', 'once');
        if isempty(step_tok)
            preprocessing_step = '';
        else
            preprocessing_step = step_tok{1};
        end
        
        % Extract timepoint pair robustly from any step-prefixed filename
        % Examples handled:
        % 519_segment_timepoint_0-timepoint_30_trimmed25
        % 519_step09_ica_segment_timepoint_0-timepoint_30_trimmed25
        tok = regexp(name, 'timepoint_(\d+)-timepoint_(\d+)_trimmed25$', 'tokens', 'once');
        if isempty(tok), continue; end
        
        start_pt = tok{1};
        end_pt   = tok{2};
        if isempty(start_pt) || isempty(end_pt), continue; end
        
        interval_key = ['timepoint_' start_pt '_to_' end_pt];    % e.g., 'timepoint_60_to_90'
        interval_idx = find(strcmp(interval_labels, interval_key), 1);
        if isempty(interval_idx), continue; end

        condition = ternary(mod(interval_idx,2)==1, 'open', 'closed');
        if ~isKey(subject_groups, subj_id), continue; end
        group = subject_groups(subj_id);

        EEG = pop_loadset('filename', file, 'filepath', trimmed_path);
        if isempty(EEG) || isempty(EEG.data), continue; end

        if isempty(EEG.chanlocs) || all(arrayfun(@(c) ~isfield(c,'X')||isempty(c.X), EEG.chanlocs))
            EEG = pop_chanedit(EEG, 'lookup', chanloc_file);
        end

        n_channels = size(EEG.data, 1);
        fs = EEG.srate;

        % Channel labels (fill missing as generic)
        ch_labels_all = cell(1, n_channels);
        for ch = 1:n_channels
            if ch <= numel(EEG.chanlocs) && isfield(EEG.chanlocs(ch), 'labels') && ~isempty(EEG.chanlocs(ch).labels)
                ch_labels_all{ch} = EEG.chanlocs(ch).labels;
            else
                ch_labels_all{ch} = sprintf('Ch%03d', ch);
            end
        end

        % Masks for inclusion/exclusion
        included_mask = true(1, n_channels);
        for ch = 1:n_channels
            if ismember(ch_labels_all{ch}, excluded_channels)
                included_mask(ch) = false;
            end
        end
        channel_labels_included = ch_labels_all(included_mask);

        % Per-channel measures (NaN for excluded channels)
        fds = nan(1, n_channels);
        pe  = nan(1, n_channels);

        for ch = 1:n_channels
            if ~included_mask(ch), continue; end

            x = double(EEG.data(ch, :));
            if ~any(isfinite(x)), continue; end

            % Split into contiguous non-NaN runs of at least min_run_seconds
            runs = get_non_nan_runs(x, fs, min_run_seconds);
            if isempty(runs), continue; end

            % Compute metrics per run, then weighted average by run length
            fd_runs    = nan(1, numel(runs));
            pe_runs    = nan(1, numel(runs));
            fd_weights = nan(1, numel(runs));
            pe_weights = nan(1, numel(runs));

            for r = 1:numel(runs)
                xr = runs{r};                 % raw run (no NaNs)
                if numel(xr) < 3 || all(xr == xr(1)), continue; end

                % --- FD on raw (run) ---
                fd_runs(r)    = compute_hfd(xr, KmaxFD);
                fd_weights(r) = numel(xr);

                % --- Downsampled copy for PE ---
                [xd, ~] = downsample_for_entropy(xr, fs, target_fs_entropy, max_N_entropy);

                % z-score safely (avoid /0)
                sd = std(xd);
                if ~isfinite(sd) || sd == 0
                    zx = zeros(size(xd));
                else
                    zx = (xd - mean(xd)) / sd;
                end

                % --- Permutation Entropy ---
                pe_runs(r) = compute_perm_entropy(zx, mPE, tauPE);
                pe_weights(r) = numel(zx);
            end

            % Channel = weighted average across valid runs
            valid_fd = isfinite(fd_runs) & isfinite(fd_weights) & (fd_weights > 0);
            if any(valid_fd)
                fds(ch) = sum(fd_runs(valid_fd) .* fd_weights(valid_fd)) / sum(fd_weights(valid_fd));
            end

            valid_pe = isfinite(pe_runs) & isfinite(pe_weights) & (pe_weights > 0);
            if any(valid_pe)
                pe(ch) = sum(pe_runs(valid_pe) .* pe_weights(valid_pe)) / sum(pe_weights(valid_pe));
            end
        end

        % Append full per-channel results for this subject+segment
        idx = numel(results) + 1;
        results(idx).subj_id                  = subj_id;
        results(idx).group                    = group;
        results(idx).condition                = condition;
        results(idx).interval_idx             = interval_idx;   % 1..12
        results(idx).interval_key             = interval_key;   % e.g., 'timepoint_0_to_30'
        results(idx).preprocessing_step       = preprocessing_step;
        results(idx).channel_labels_all       = ch_labels_all;  % 1..n_channels
        results(idx).included_mask            = included_mask;   % logical mask
        results(idx).channel_labels_included  = channel_labels_included; % labels actually used
        results(idx).fd                       = fds;             % 1 x n_channels (NaN where excluded)
        results(idx).permEnt                  = pe;              % 1 x n_channels (NaN where excluded)

        % Log line: quick per-segment summary (means over included channels)
        avg_fd = mean(fds(included_mask), 'omitnan');
        avg_pe = mean(pe(included_mask),  'omitnan');

        fprintf('✓ %s | %s | %s | int %d (%s) | FD=%.4f PE=%.3f | %.1fs\n', ...
                file, subj_id, preprocessing_step, interval_idx, condition, avg_fd, avg_pe, toc(t0));
        drawnow limitrate;  % keep the session responsive

    catch ME
        fprintf('⚠️ Error in file %s: %s\n', segment_files(f).name, ME.message);
        continue;
    end
end

% Save once at the end
save(results_file, 'results');
fprintf('💾 Saved per-channel results to %s\n', results_file);

%% ----------------- Helpers -----------------
function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end

function runs = get_non_nan_runs(x, fs, min_sec)
% Split a vector into contiguous finite-valued runs of at least min_sec.
    if nargin < 3, min_sec = 2; end
    x = x(:)'; ok = isfinite(x);
    if ~any(ok), runs = {}; return; end
    d = diff([false, ok, false]);   % rising edges = +1, falling = -1
    starts = find(d == 1);
    stops  = find(d == -1) - 1;
    min_len = ceil(min_sec * fs);
    keep = (stops - starts + 1) >= min_len;
    starts = starts(keep);
    stops  = stops(keep);
    runs = cell(1, numel(starts));
    for i = 1:numel(starts)
        seg = x(starts(i):stops(i));
        % Safety: drop if constant or empty after trimming
        if isempty(seg) || all(seg == seg(1))
            runs{i} = [];
        else
            runs{i} = seg;
        end
    end
    runs = runs(~cellfun(@isempty, runs));
end

function [y, fs_out] = downsample_for_entropy(x, fs_in, fs_target, maxN)
% Anti-aliased resample downwards if needed; cap length at maxN.
    x = x(:)'; fs_out = fs_in;
    if isfinite(fs_target) && fs_in > fs_target
        if exist('resample','file')
            y = resample(x, fs_target, fs_in);
        else
            % Fallback: simple decimation (basic LPF with moving average)
            d = max(1, round(fs_in/fs_target));
            y = movmean(x, d); y = y(1:d:end);
        end
        fs_out = fs_target;
    else
        y = x;
    end
    if numel(y) > maxN
        % Keep a centered chunk of length maxN
        s = floor((numel(y)-maxN)/2)+1;
        y = y(s:s+maxN-1);
    end
end

function kFD = compute_hfd(X, Kmax)
% 1: Higuchi Fractal Dimension (raw signal)
    X = X(:)'; N = numel(X);
    if nargin<2 || isempty(Kmax), Kmax = 10; end
    if N < 4, kFD = NaN; return; end
    Kmax = max(2, min(Kmax, floor(N/4)));
    L = nan(Kmax,1); x = nan(Kmax,1);
    for k = 1:Kmax
        Lk = nan(1,k);
        for m = 1:k
            idx = m:k:N; n = numel(idx);
            if n > 1
                Lmk = sum(abs(diff(X(idx)))) * (N - 1) / (k * (n - 1) * k);
                Lk(m) = Lmk;
            end
        end
        L(k) = mean(Lk,'omitnan'); x(k) = log(1/k);
    end
    y = log(L);
    valid = isfinite(x) & isfinite(y);
    if sum(valid) < 2
        kFD = NaN;
    else
        p = polyfit(x(valid), y(valid), 1);
        kFD = p(1);
    end
end

function pe = compute_perm_entropy(x, m, tau)
% 2: Standard normalized Permutation Entropy; x should be z-scored.
    if nargin<2, m=4; end
    if nargin<3, tau=1; end

    x = x(:)';
    N = numel(x);
    L = N - (m-1)*tau;
    if L <= 1, pe = NaN; return; end

    pat = zeros(L, m);
    for i = 1:m
        pat(:,i) = x(1+(i-1)*tau : L+(i-1)*tau);
    end

    % Handle ties with tiny unbiased random jitter
    sdx = std(x);
    if ~isfinite(sdx) || sdx == 0
        sdx = 1;
    end
    stream = RandStream('mt19937ar','Seed',1);
    pat = pat + (1e-12 * sdx) * randn(stream, size(pat));

    % Ordinal patterns
    [~, ord] = sort(pat, 2, 'ascend');

    % Count observed ordinal patterns
    [~, ~, ic] = unique(ord, 'rows');
    counts = accumarray(ic, 1);

    % Probability distribution
    p = counts / sum(counts);
    p = p(p>0);

    % Normalized permutation entropy in [0,1]
    pe = -sum(p .* log(p)) / log(factorial(m));
end

%% ========================================================================================== %% 
%% ==================== 3.1 Ploting HFD and Permutation Entropy ============================= %%
%% ========================================================================================== %%

clearvars

% Paths
data_analysis_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/5_Data_analysis_files/';
data_analysis_path = char(data_analysis_path);
results_file = fullfile(data_analysis_path, 'complexity_results_all_steps_final.mat');  % contains per-channel results: fd, permEnt
trimmed_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/4_Trimmed_files/';
trimmed_path = char(trimmed_path);
excel_file   = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/VIA15_Masterfile_Cleaned.xlsx';

% If interval_labels is in workspace, keep it; otherwise define the 12 labels:
if ~exist('interval_labels','var') || isempty(interval_labels)
    interval_labels = { ...
     'timepoint_0_to_30','timepoint_30_to_60','timepoint_60_to_90','timepoint_90_to_120', ...
     'timepoint_120_to_150','timepoint_150_to_180','timepoint_180_to_210','timepoint_210_to_240', ...
     'timepoint_240_to_270','timepoint_270_to_300','timepoint_300_to_330','timepoint_330_to_360'};
end

% Load results (if not already in workspace)
S = load(results_file);
results = S.results;

% --- Filter results to only step12 files ---
is_step12 = strcmp({results.preprocessing_step}, 'step12');
results = results(is_step12);

% --- Extract subject IDs once, so averaging can happen within subject before group plotting ---
subject_ids = strings(1, numel(results));

for i = 1:numel(results)
    if isfield(results, 'subj_id') && ~isempty(results(i).subj_id)
        sid = results(i).subj_id;

    elseif isfield(results, 'filename') && ~isempty(results(i).filename)
        tok = regexp(char(results(i).filename), '(^\d+)', 'tokens', 'once');
        if isempty(tok)
            error('Could not extract subject ID from results(%d).filename', i);
        end
        sid = tok{1};

    elseif isfield(results, 'file_name') && ~isempty(results(i).file_name)
        tok = regexp(char(results(i).file_name), '(^\d+)', 'tokens', 'once');
        if isempty(tok)
            error('Could not extract subject ID from results(%d).file_name', i);
        end
        sid = tok{1};

    elseif isfield(results, 'setname') && ~isempty(results(i).setname)
        tok = regexp(char(results(i).setname), '(^\d+)', 'tokens', 'once');
        if isempty(tok)
            error('Could not extract subject ID from results(%d).setname', i);
        end
        sid = tok{1};

    else
        error(['Could not find a subject identifier field in results. ', ...
               'Expected one of: subject_id, subject, subj, participant_id, participant, id, ID, filename, file_name, setname.']);
    end

    if isnumeric(sid)
        subject_ids(i) = string(sid);
    else
        subject_ids(i) = string(char(sid));
    end
end

% --- Collect groups present in results ---
all_groups = string({results.group});
groups = unique(all_groups, 'stable');
G = numel(groups);
if G == 0
    error('No groups found in results.');
end
fprintf('Groups detected: %s\n', strjoin(cellstr(groups), ', '));

% --- Intervals ---
K = numel(interval_labels);
x = 1:K;
interval_idx_all = [results.interval_idx];

% ----- ONLY the two measures that are actually computed in the code above -----
measures = {
    'avg_fd',      'Higuchi Fractal Dimension';
    'avg_permEnt', 'Permutation Entropy'
};

% How to compute each measure from a results struct (use included channels only)
% (These fields exist in the computation code: r.fd, r.permEnt, r.included_mask)
metric_funcs = struct( ...
    'avg_fd',      @(r) mean(r.fd(r.included_mask),      'omitnan'), ...
    'avg_permEnt', @(r) mean(r.permEnt(r.included_mask), 'omitnan') ...
);

% For filenames
safe = @(s) regexprep(lower(s), '\W+', '_');

outdir = fullfile(data_analysis_path, 'Plots_Complexity_ByGroup');
if ~exist(outdir, 'dir'), mkdir(outdir); end

% --- Colors ---
color_map = containers.Map( ...
    {'FHR_SZ','FHR_BP','PBC'}, ...
    {[0 175 194]/255, [140 208 219]/255, [148 192 28]/255} );

for m = 1:size(measures,1)
    field = measures{m,1};
    ylab  = measures{m,2};

    if ~isfield(metric_funcs, field)
        error('No metric function defined for %s', field);
    end
    compute_metric = metric_funcs.(field);

    MU  = nan(G, K);
    SEM = nan(G, K);
    N   = zeros(G, K);

    for gi = 1:G
        gname = groups(gi);
        is_g  = (all_groups == gname);

        for k = 1:K
            is_k = (interval_idx_all == k);
            idx  = find(is_g & is_k);

            if isempty(idx)
                MU(gi,k)   = NaN;
                SEM(gi,k)  = NaN;
                N(gi,k)    = 0;
            else
                % vals = per-file average-across-included-channels metric
                vals = arrayfun(@(rr) compute_metric(rr), results(idx));
                subj_here = subject_ids(idx);

                % Average within subject first so participants with more files
                % do not contribute more strongly to the group mean/SEM
                [uniq_subj, ~, subj_map] = unique(subj_here, 'stable');
                subj_vals = nan(numel(uniq_subj), 1);

                for si = 1:numel(uniq_subj)
                    subj_vals(si) = mean(vals(subj_map == si), 'omitnan');
                end

                MU(gi,k)   = mean(subj_vals, 'omitnan');
                N(gi,k)    = sum(isfinite(subj_vals));
                sd_k       = std(subj_vals, 'omitnan');

                if N(gi,k) > 1
                    SEM(gi,k) = sd_k / sqrt(N(gi,k));
                elseif N(gi,k) == 1
                    SEM(gi,k) = 0;   % one sample -> no error bar
                else
                    SEM(gi,k) = NaN;
                end
            end
        end
    end

    % ---- PLOT ----
    figure('Color','w', 'Position', [100 100 1500 600]); hold on;
    set(gca, 'FontSize', 11, 'FontName', 'Helvetica', 'FontWeight','normal');

    % mean ± SEM (no individual points beyond mean markers)
    h_for_legend = gobjects(1,G);
    for gi = 1:G
        gname_char = char(groups(gi));
        if isKey(color_map, gname_char)
            c = color_map(gname_char);
        else
            c = [0 0 0];
        end

        h_for_legend(gi) = errorbar(x, MU(gi,:), SEM(gi,:), '-o', ...
            'Color', c, ...
            'MarkerFaceColor', c, ...
            'LineWidth', 1.6, 'MarkerSize', 5, ...
            'CapSize', 12, ...
            'DisplayName', sprintf('%s (mean ± SEM)', gname_char));
    end

    grid on; box on;
    xlim([0.5 K+0.5]);
    xticks(x);
    xticklabels(compose('%d', x));
    xlabel('Segment no.', 'FontName','Helvetica');
    ylabel(ylab, 'Interpreter','tex', 'FontName','Helvetica');
    title(sprintf('%s across 12 segments', ylab), ...
          'Interpreter','tex', 'FontName','Helvetica', 'FontWeight','normal');

    % -------- Dynamic y-limits that fit the data (considering MU ± SEM) --------
    y_candidates = [MU(:); (MU(:)-SEM(:)); (MU(:)+SEM(:))];
    y_candidates = y_candidates(isfinite(y_candidates));

    if isempty(y_candidates)
        y_min = 0; y_max = 1;
    else
        y_min = min(y_candidates);
        y_max = max(y_candidates);
        if y_min == y_max
            delta = max(0.1*max(abs(y_min),1), 1e-3);
            y_min = y_min - delta;
            y_max = y_max + delta;
        else
            pad = 0.08 * (y_max - y_min);
            y_min = y_min - pad;
            y_max = y_max + pad;
        end
    end

    % --- Keep forced HFD axis  ---
    if strcmp(field, 'avg_fd')
        ylim([1.30, 1.60]);  % adjust if the HFD range differs
    else
        ylim([y_min, y_max]);
    end

    % --- Legend: enforce order PBC → FHR_BP → FHR_SZ (if present) ---
    desired = {'FHR_SZ','FHR_BP','PBC'};
    [tf, loc_in_groups] = ismember(desired, cellstr(groups));
    order = loc_in_groups(tf & loc_in_groups > 0);
    labels = cellfun(@(s) sprintf('%s (mean ± SEM)', s), desired(tf), 'uni', 0);

    if ~isempty(order)
        lgd = legend(h_for_legend(order), labels, 'Location','southeast', 'FontName','Helvetica');
    else
        lgd = legend(h_for_legend, 'Location','southeast', 'FontName','Helvetica');
    end
    set(lgd, 'Interpreter','none');

    % filename + save
    fname = fullfile(outdir, sprintf('plot_%s_by_group_meanSEM.png', safe(ylab)));
    exportgraphics(gca, fname, 'Resolution', 200);
    fprintf('Saved: %s\n', fname);

    close(gcf);
end

%% ================= 3.1.1 HFD: Raincloud plot of Higuchi FD per condition (each dot = 1 segment) =================
if ~exist('results','var')
    S = load(results_file); results = S.results;

    % --- Filter results to only step12 files ---
    is_step12 = strcmp({results.preprocessing_step}, 'step12');
    results = results(is_step12);
end

all_groups     = string({results.group});
all_conditions = string({results.condition});

groups = ["FHR_SZ","FHR_BP","PBC"];  % enforce fixed order
conditions = unique(all_conditions, 'stable');  % typically 'open','closed'
G = numel(groups);
C = numel(conditions);

% Custom colors (fixed order)
color_map_fd = containers.Map( ...
    {'PBC','FHR_BP','FHR_SZ'}, ...
    {[148 192 28]/255, [140 208 219]/255, [0 175 194]/255} );

outdir_fd = fullfile(data_analysis_path, 'Plots_Complexity_ByGroup');
if ~exist(outdir_fd, 'dir'), mkdir(outdir_fd); end

% ---- Combined figure with subplots ----
fig = figure('Color','w', 'Position', [100 100 1100 750]);  % height = 500*1.5 = 750
set(fig, 'DefaultTextFontName','Arial', 'DefaultAxesFontName','Arial');

for ci = 1:C
    cond = conditions(ci);

    % Collect pooled values per group
    data_by_group = cell(1,G);
    for gi = 1:G
        gname = groups(gi);
        idx = find(all_groups == gname & all_conditions == cond);

        if isempty(idx)
            data_by_group{gi} = NaN;
        else
            vals = arrayfun(@(r) mean(r.fd(r.included_mask),'omitnan'), results(idx));
            data_by_group{gi} = vals(isfinite(vals));
        end
    end

    % --- Subplot for this condition ---
    ax = subplot(1,C,ci); hold on;
    set(ax, 'FontSize', 11, 'FontName', 'Arial', 'FontWeight','normal');

    for gi = 1:G
        gname = groups(gi);
        vals  = data_by_group{gi};
        if isempty(vals), continue; end

        c = color_map_fd(gname);

        % --- Violin (kernel density) ---
        [f,xi] = ksdensity(vals, 'Bandwidth', 0.01);
        f = f ./ max(f) * 0.3;  % normalize width
        patch([gi+f fliplr(gi-f)], [xi fliplr(xi)], c, ...
              'FaceAlpha', 0.3, 'EdgeColor', 'none');

        % --- Jittered scatter of individual values ---
        jitter = (rand(size(vals))-0.5) * 0.15;
        scatter(gi + jitter, vals, 15, 'MarkerFaceColor', c, ...
                'MarkerEdgeColor', 'k', 'MarkerFaceAlpha', 0.6);

        % --- Mean ± SD overlay ---
        mu  = mean(vals, 'omitnan');
        sd  = std(vals, 'omitnan');
        errorbar(gi, mu, sd, 'k', 'LineWidth', 1.6, 'CapSize', 12);
        plot(gi, mu, 'ko', 'MarkerFaceColor', 'w', 'MarkerSize', 6, 'LineWidth', 1.2);
    end

    % Axes formatting
    grid on; box on;
    xlim([0.5 G+0.5]);
    ylim([1.1 2]);   % fixed y-axis range
    xticks(1:G);
    xticklabels(groups);  
    set(ax, 'TickLabelInterpreter','none');  % prevents "_" subscript issue

    xlabel('Group', 'FontName','Arial');
    ylabel('Higuchi Fractal Dimension', 'FontName','Arial');

    % Condition label
    if strcmpi(cond, "open")
        cond_label = "Open eyes";
    elseif strcmpi(cond, "closed")
        cond_label = "Closed eyes";
    else
        cond_label = cond; % fallback
    end
    title(cond_label, 'FontName','Arial','FontWeight','normal');
end

% Save combined figure
fname = fullfile(outdir_fd, 'raincloud_fd_conditions_combined_SD.png');
exportgraphics(fig, fname, 'Resolution', 200);
fprintf('Saved raincloud plot: %s\n', fname);

close(fig);

%% ================= 3.1.2 HFD: Raincloud plot of Higuchi FD per condition — (each dot = 1 subject) =================
if ~exist('results','var')
    S = load(results_file); results = S.results;

    % --- Filter results to only step12 files ---
    is_step12 = strcmp({results.preprocessing_step}, 'step12');
    results = results(is_step12);
end

all_groups     = string({results.group});
all_conditions = string({results.condition});

% --- Detect a subject identifier field once (now includes 'subj_id') ---
cand_fields = {'subj_id','subject','subj','participant','id','ID'};
subj_field = '';
for f = cand_fields
    if isfield(results, f{1})
        subj_field = f{1};
        break;
    end
end
if isempty(subj_field)
    error('Could not find a subject identifier field in results. Expected one of: %s', strjoin(cand_fields, ', '));
end
all_subjects = string({results.(subj_field)});

% Enforce fixed order
groups = ["FHR_SZ","FHR_BP","PBC"];
conditions = unique(all_conditions, 'stable');  % typically 'open','closed'
G = numel(groups);
C = numel(conditions);

% Custom colors (fixed order)
color_map_fd = containers.Map( ...
    {'PBC','FHR_BP','FHR_SZ'}, ...
    {[148 192 28]/255, [140 208 219]/255, [0 175 194]/255} );

outdir_fd = fullfile(data_analysis_path, 'Plots_Complexity_ByGroup');
if ~exist(outdir_fd, 'dir'), mkdir(outdir_fd); end

% ---- Combined figure with subplots ----
fig = figure('Color','w', 'Position', [100 100 1100 750]);  % height = 500*1.5 = 750
set(fig, 'DefaultTextFontName','Arial', 'DefaultAxesFontName','Arial');

for ci = 1:C
    cond = conditions(ci);

    % Collect SUBJECT-LEVEL means per group (each entry = one subject in this condition)
    subj_means_by_group = cell(1,G);

    for gi = 1:G
        gname = groups(gi);

        % Entries for this group & condition
        idx_gc = find(all_groups == gname & all_conditions == cond);
        if isempty(idx_gc)
            subj_means_by_group{gi} = [];
            continue;
        end

        % Unique subjects present in this subset
        subs_gc = unique(all_subjects(idx_gc));

        subj_means = nan(numel(subs_gc),1);

        for si = 1:numel(subs_gc)
            s = subs_gc(si);

            % All records (segments) for this subject in this group & condition
            idx_sub = idx_gc(all_subjects(idx_gc) == s);

            % Compute a per-record (segment) value = mean FD over included channels
            rec_vals = nan(numel(idx_sub),1);
            for k = 1:numel(idx_sub)
                r = results(idx_sub(k));
                if isfield(r,'included_mask') && islogical(r.included_mask) && numel(r.included_mask)==numel(r.fd)
                    rec_vals(k) = mean(r.fd(r.included_mask), 'omitnan');
                else
                    rec_vals(k) = mean(r.fd(:), 'omitnan');
                end
            end

            % Subject-level mean across that subject's segments in this condition
            subj_means(si) = mean(rec_vals, 'omitnan');
        end

        % Keep only finite means
        subj_means_by_group{gi} = subj_means(isfinite(subj_means));
    end

    % --- Subplot for this condition ---
    ax = subplot(1,C,ci); hold on;
    set(ax, 'FontSize', 11, 'FontName', 'Arial', 'FontWeight','normal');

    for gi = 1:G
        gname = groups(gi);
        subj_means  = subj_means_by_group{gi};
        if isempty(subj_means), continue; end

        c = color_map_fd(gname);

        % --- Violin (kernel density) over SUBJECT MEANS ---
        try
            [f,xi] = ksdensity(subj_means, 'Bandwidth', 0.01);
            f = f ./ max(f) * 0.3;  % normalize width
            patch([gi+f fliplr(gi-f)], [xi fliplr(xi)], c, ...
                  'FaceAlpha', 0.3, 'EdgeColor', 'none');
        catch
            % ksdensity may fail for single-point data; skip violin gracefully
        end

        % --- Jittered scatter of SUBJECT MEANS (one dot = one subject) ---
        jitter = (rand(size(subj_means))-0.5) * 0.15;
        scatter(gi + jitter, subj_means, 26, 'MarkerFaceColor', c, ...
                'MarkerEdgeColor', 'k', 'MarkerFaceAlpha', 0.8);

        % --- Single Group Mean ± SD computed across SUBJECT MEANS ---
        mu_group  = mean(subj_means, 'omitnan');
        sd_group  = std(subj_means,  'omitnan');
        errorbar(gi, mu_group, sd_group, 'k', 'LineWidth', 1.8, 'CapSize', 12);
        plot(gi, mu_group, 'ko', 'MarkerFaceColor', 'w', 'MarkerSize', 6, 'LineWidth', 1.2);
    end

    % Axes formatting
    grid on; box on;
    xlim([0.5 G+0.5]);
    ylim([1.1 1.95]);   % adjust if needed for the HFD scale
    xticks(1:G);
    xticklabels(groups);
    set(ax, 'TickLabelInterpreter','none');  % prevents "_" subscript issue

    xlabel('Group', 'FontName','Arial');
    ylabel('Higuchi Fractal Dimension', 'FontName','Arial');

    % Condition label
    if strcmpi(cond, "open")
        cond_label = "Open eyes";
    elseif strcmpi(cond, "closed")
        cond_label = "Closed eyes";
    else
        cond_label = cond; % fallback
    end
    title(cond_label, 'FontName','Arial','FontWeight','normal');
end

% Save combined figure
fname = fullfile(outdir_fd, 'raincloud_fd_conditions_subjectlevel_groupMeanSD.png');
exportgraphics(fig, fname, 'Resolution', 200);
fprintf('Saved raincloud plot (subject-level with single group mean±SD): %s\n', fname);

close(fig);

%% ================= 3.1.3 Topographical complexity plots (HFD + PE) ================
% Self-contained: can be run independently of previous sections.
% Saves two versions per measure: with labels and without labels.
% Plots ONLY: Higuchi FD (HFD) and Permutation Entropy (PE)
% All text set to Helvetica.

% ---------- EDIT THESE PATHS IF NEEDED ----------
eeglab nogui;
data_analysis_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/5_Data_analysis_files/';
trimmed_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/4_Trimmed_files/'; %#ok<NASGU>
results_file = fullfile(data_analysis_path, 'complexity_results_all_steps_final.mat');  % saved by the analysis script
chanloc_file = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/biosemi128.sfp';
excel_file   = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/VIA15_Masterfile_Cleaned.xlsx';
% ------------------------------------------------

% Ensure EEGLAB plotting functions are available
if exist('topoplot','file')~=2
    try
        eeglab nogui;  % will no-op if EEGLAB already on path
        close all;
    catch
        error('EEGLAB (topoplot) not found on path. Please add EEGLAB to MATLAB path.');
    end
end

% Set default font everywhere to Helvetica
set(groot, 'DefaultTextFontName', 'Helvetica');
set(groot, 'DefaultAxesFontName', 'Helvetica');
set(groot, 'DefaultUicontrolFontName', 'Helvetica');
set(groot, 'DefaultLegendFontName', 'Helvetica');
set(groot, 'DefaultColorbarFontName', 'Helvetica');

% Load results
if ~exist(results_file, 'file')
    error('results_file not found: %s', results_file);
end
S = load(results_file);
if ~isfield(S,'results') || isempty(S.results)
    error('No ''results'' variable found in %s or it is empty.', results_file);
end
results = S.results;

% If needed, define interval_labels here as well
if ~exist('interval_labels','var') || isempty(interval_labels)
    interval_labels = { ...
     'timepoint_0_to_30','timepoint_30_to_60','timepoint_60_to_90','timepoint_90_to_120', ...
     'timepoint_120_to_150','timepoint_150_to_180','timepoint_180_to_210','timepoint_210_to_240', ...
     'timepoint_240_to_270','timepoint_270_to_300','timepoint_300_to_330','timepoint_330_to_360'};
end

% --- Filter results to only step12 files ---
if isfield(results, 'preprocessing_step')
    is_step12 = strcmp({results.preprocessing_step}, 'step12');
    results = results(is_step12);
else
    warning(['Field "preprocessing_step" not found in results loaded from: ' results_file ...
             '. Section 3.1.3 will run on all entries in that file. ' ...
             'For step12-only topoplots, load a results file that contains preprocessing_step.']);
end

% Infer groups (force order: PBC, FHR_BP, FHR_SZ; append any others if present)
all_groups = string({results.group});
groups_unique = unique(all_groups, 'stable');

desired_order = ["FHR_SZ","FHR_BP","PBC"];  % enforce fixed order
ordered = desired_order(ismember(desired_order, groups_unique));
others  = groups_unique(~ismember(groups_unique, desired_order));
groups = [ordered, others];  % final order
if isempty(groups)
    error('No groups detected in results.');
end

% Infer conditions from results (keep internal keys), then make pretty labels
all_conditions = string({results.condition});
conditions_unique = unique(all_conditions, 'stable');
pref_order = ["open","closed"]; % internal keys (case-insensitive)
conditions = [pref_order(ismember(pref_order, lower(conditions_unique))), ...
              conditions_unique(~ismember(lower(conditions_unique), pref_order))];
C = numel(conditions);

% Pretty labels for column headers
header_labels = strings(1, C);
for ci = 1:C
    key = lower(string(conditions(ci)));
    if contains(key, "open")
        header_labels(ci) = "Open eyes";
    elseif contains(key, "closed")
        header_labels(ci) = "Closed eyes";
    else
        header_labels(ci) = string(conditions(ci));
    end
end

% Load common channel locations (BioSemi 128)
if exist('readlocs','file')==2
    common_chanlocs = readlocs(chanloc_file, 'filetype', 'sfp');
else
    EEGtmp = eeg_emptyset();
    EEGtmp = pop_chanedit(EEGtmp, 'load',{chanloc_file 'filetype' 'sfp'});
    common_chanlocs = EEGtmp.chanlocs;
end
if isempty(common_chanlocs)
    error('Failed to load channel locations from %s', chanloc_file);
end

% Label map for the common montage
common_labels = arrayfun(@(c) c.labels, common_chanlocs, 'uni', 0);
nCommon = numel(common_labels);
label_to_idx = containers.Map('KeyType','char','ValueType','double');
for i = 1:nCommon
    lab = common_labels{i};
    if ~isempty(lab)
        label_to_idx(lab) = i;
    end
end

% Exclude only EXG-like labels; keep outermost ring
exg_like = startsWith(string(common_labels), "EXG", 'IgnoreCase', true);
final_exclude_mask = exg_like';  % logical column nCommon×1

% Measures: field in results (per-channel vector) -> pretty label
% ONLY plot HFD + PE
measures_topo = {
    'fd',      'Higuchi FD';
    'permEnt', 'Permutation Entropy'
};

% Output directory
topo_dir = fullfile(data_analysis_path, 'Plots_Complexity_ByGroup', 'Topos');
if ~exist(topo_dir, 'dir'), mkdir(topo_dir); end
safe = @(s) regexprep(lower(s), '\W+', '_');

% --------------- Aggregate and plot ---------------
for m = 1:size(measures_topo,1)
    field  = measures_topo{m,1};
    pretty = measures_topo{m,2};

    % nCommon × (#groups) × (#conditions)
    topo_mean = nan(nCommon, numel(groups), C);

    for gi = 1:numel(groups)
        gname = groups(gi);
        in_group = (all_groups == gname);

        for ci = 1:C
            cname = conditions(ci);
            in_cond = (lower(all_conditions) == lower(cname));  % case-insensitive match

            idx = find(in_group & in_cond);
            if isempty(idx)
                topo_mean(:, gi, ci) = nan(nCommon,1);
                continue;
            end

            % Get subject IDs for this group-condition combination
            subj_ids = strings(numel(idx),1);
            for k = 1:numel(idx)
                r = results(idx(k));
                if ~isfield(r, 'subj_id')
                    error('Expected field "subj_id" missing in results(%d).', idx(k));
                end
                subj_ids(k) = string(r.subj_id);
            end
            unique_subj = unique(subj_ids, 'stable');

            % First average within subject, then average across subjects
            subj_stack = nan(nCommon, numel(unique_subj));

            for si = 1:numel(unique_subj)
                this_subj = unique_subj(si);
                subj_idx = idx(subj_ids == this_subj);

                % Align each entry for this subject to common montage and stack
                seg_stack = nan(nCommon, numel(subj_idx));
                for k = 1:numel(subj_idx)
                    r = results(subj_idx(k));

                    if ~isfield(r, field)
                        error('Expected field "%s" missing in results(%d).', field, subj_idx(k));
                    end

                    v = r.(field);               % per-channel values for this entry
                    mask = r.included_mask;      % logical per-channel
                    v(~mask) = NaN;              % drop excluded channels from this entry

                    % Align by label into common order
                    v_aligned = nan(nCommon,1);
                    labels_r = r.channel_labels_all;
                    for jj = 1:numel(labels_r)
                        lab = labels_r{jj};
                        if isKey(label_to_idx, lab)
                            v_aligned(label_to_idx(lab)) = v(jj);
                        end
                    end

                    % Apply final exclusion (EXG only)
                    v_aligned(final_exclude_mask) = NaN;

                    seg_stack(:,k) = v_aligned;
                end

                % Subject-level mean across segments
                subj_stack(:,si) = mean(seg_stack, 2, 'omitnan');
            end

            % Group-condition mean across subjects
            topo_mean(:, gi, ci) = mean(subj_stack, 2, 'omitnan');
        end
    end

    % --------- Compute a consistent color scale per figure ----------
    v_all = topo_mean(:);
    finite_vals = v_all(isfinite(v_all));
    if isempty(finite_vals)
        clim_low = 0; clim_high = 1;
    else
        clim_low  = prctile(finite_vals, 5);
        clim_high = prctile(finite_vals, 95);
        if ~isfinite(clim_low) || ~isfinite(clim_high) || clim_low==clim_high
            clim_low  = min(finite_vals);
            clim_high = max(finite_vals);
            if ~(isfinite(clim_low) && isfinite(clim_high)) || clim_low==clim_high
                clim_low = 0; clim_high = 1;
            end
        end
    end

    % --------- Make two versions: with labels and without labels ----------
    for label_mode = ["labels","off"]  % "labels" -> show labels; "off" -> no labels
        show_labels = char(label_mode);
        label_suffix = "_nolabels";
        if strcmp(show_labels,'labels')
            label_suffix = "_labels";
        end

        nRows = numel(groups);
        nCols = C;

        % Figure: Helvetica for all text
        fig = figure('Color','w', 'Position', [100 100 800 980]);
        set(fig, 'DefaultTextFontName','Helvetica', 'DefaultAxesFontName','Helvetica');

        % Use 'none' to minimize spacing between tiles; tiny left/right padding
        tl = tiledlayout(nRows, nCols, 'Padding','compact', 'TileSpacing','none'); %#ok<NASGU>

        % Plot tiles
        ax_mat = gobjects(nRows, nCols); %#ok<NASGU>
        for gi = 1:numel(groups)
            for ci = 1:C
                ax = nexttile;
                ax_mat(gi,ci) = ax; %#ok<NASGU>
                set(ax, 'FontName', 'Helvetica');

                vals = topo_mean(:, gi, ci);
                if ~any(isfinite(vals))
                    axis(ax,'off');
                    text(ax, 0.5, 0.5, 'No data', ...
                        'HorizontalAlignment','center', ...
                        'FontName','Helvetica');
                else
                    topoplot(vals, common_chanlocs, ...
                             'electrodes', show_labels, ...  % 'labels' or 'off'
                             'style','map', ...
                             'plotrad', 0.5, ...
                             'maplimits', [clim_low, clim_high]); %#ok<TOPLOT>
                    axis(ax,'tight');
                end

                % Column headers: pretty names above first row of each column
                if gi == 1
                    text(ax, 0.5, 1.08, char(header_labels(ci)), 'Units','normalized', ...
                        'HorizontalAlignment','center','VerticalAlignment','bottom', ...
                        'Interpreter','none','FontName','Helvetica','Clipping','off');
                end

                % Row labels: group name to the left of the first column (HORIZONTAL)
                if ci == 1
                    text(ax, -0.13, 0.50, char(groups(gi)), 'Units','normalized', ...
                        'HorizontalAlignment','right','VerticalAlignment','middle', ...
                        'Interpreter','none','FontName','Helvetica','Clipping','off');
                end
            end
        end

        % Shared colorbar
        cb = colorbar;
        cb.Layout.Tile = 'east';
        cb.FontName = 'Helvetica';

        % Save
        fname = fullfile(topo_dir, sprintf('topos_%s_%dx%d%s.png', safe(pretty), nRows, nCols, label_suffix));
        exportgraphics(fig, fname, 'Resolution', 200);
        fprintf('Saved: %s\n', fname);
        close(fig);
    end
end


%% ========================================================================================== %%
%% ============ 3.2 Statistical testing of HFD group differences ============================ %%
%% ========================================================================================== %%

%% ================= 3.2.1: Linear Mixed-Effects models: HFD at subject level
% ---------- EDIT THESE PATHS IF NEEDED ----------
eeglab nogui;
data_analysis_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/5_Data_analysis_files/';
trimmed_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/4_Trimmed_files/'; %#ok<NASGU>
results_file = fullfile(data_analysis_path, 'complexity_results_all_steps_final.mat');  % saved by the analysis script
chanloc_file = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/biosemi128.sfp';
excel_file   = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/VIA15_Masterfile_Cleaned.xlsx';

if ~exist('results','var')
    S = load(results_file); results = S.results;
end

% --- Filter results to only step12 files ---
if isfield(results, 'preprocessing_step')
    is_step12 = strcmp({results.preprocessing_step}, 'step12');
    results = results(is_step12);
else
    warning(['Field "preprocessing_step" not found in results loaded from: ' results_file ...
             '. Section 3.2.3 will run on all entries in that file. ' ...
             'For step12-only analyses, load a results file that contains preprocessing_step.']);
end

all_groups     = string({results.group});
all_conditions = string({results.condition});
all_subjects   = regexprep(strtrim(string({results.subj_id})), '^0+', '');

% --- MINIMAL CHANGE: put PBC first so it becomes the reference level ---
groups = ["PBC","FHR_BP","FHR_SZ"];  % enforce fixed order AND reference = PBC
% ----------------------------------------------------------------------

conditions = unique(all_conditions, 'stable');  % typically 'open','closed'

% ---- Load covariates (age15EEG, gender) from Excel and clean ----
cov_file   = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/VIA15_Masterfile_Cleaned.xlsx';

% Detect options and make sure age uses comma as decimal separator
opts = detectImportOptions(cov_file);
if any(strcmpi(opts.VariableNames,'age15EEG'))
    opts = setvaropts(opts, 'age15EEG', 'DecimalSeparator', ',');
end
cov = readtable(cov_file, opts);

% Harmonize subject ID column name (case-sensitive in MATLAB tables)
if any(strcmpi(cov.Properties.VariableNames,'id'))
    cov.SubjectID = string(cov.id);
elseif any(strcmpi(cov.Properties.VariableNames,'Id'))
    cov.SubjectID = string(cov.Id);
elseif any(strcmpi(cov.Properties.VariableNames,'subj_id'))
    cov.SubjectID = string(cov.subj_id);
else
    error('Could not find subject ID column (expected ''id'', ''Id'' or ''subj_id'') in covariate file.');
end
cov.SubjectID = regexprep(strtrim(cov.SubjectID), '^0+', '');

% Parse Age (age15EEG) robustly in case it came in as text with commas
if any(strcmpi(cov.Properties.VariableNames,'age15EEG'))
    rawAge = cov.age15EEG;
else
    error('Could not find ''age15EEG'' in covariate file.');
end
if iscell(rawAge) || isstring(rawAge)
    Age = str2double(strrep(string(rawAge), ',', '.'));
else
    Age = double(rawAge);
end

% Map gender 0=female, 1=male to categorical
if any(strcmpi(cov.Properties.VariableNames,'gender'))
    graw = cov.gender;
else
    error('Could not find ''gender'' in covariate file.');
end
if iscell(graw) || isstring(graw)
    gnum = str2double(string(graw));
else
    gnum = double(graw);
end
Gender = categorical(gnum, [0 1], {'Female','Male'});

cov_keep = table(cov.SubjectID, Age, Gender, 'VariableNames', {'SubjectID','Age','Gender'});

fprintf('\n===== Mixed-effects tests of Higuchi FD per condition (adjusted for Age, Gender) =====\n');

% ===================== SUBJECT-LEVEL OUTCOME PER CONDITION =====================
% Compute one HFD value per segment first, then average within Subject x Condition
% so that each participant contributes equally within each condition,
% regardless of the number of valid segments.

seg_vals      = [];
seg_subj      = strings(0,1);
seg_group     = strings(0,1);
seg_condition = strings(0,1);

for i = 1:numel(results)
    r = results(i);
    if isempty(r.fd) || ~any(r.included_mask), continue; end
    fd_val = mean(r.fd(r.included_mask), 'omitnan');
    if ~isfinite(fd_val), continue; end

    seg_vals(end+1,1)      = fd_val;
    seg_subj(end+1,1)      = regexprep(strtrim(string(r.subj_id)), '^0+', '');
    seg_group(end+1,1)     = string(r.group);
    seg_condition(end+1,1) = string(r.condition);
end

SegT = table(seg_vals, seg_subj, seg_group, seg_condition, ...
    'VariableNames', {'HFD_seg','SubjectID','Group_str','Condition_str'});

% Ensure consistent condition coding and ordering (keep existing 'stable' order)
% If open/closed exist, enforce open as reference to keep interpretation consistent.
if any(conditions == "open") && any(conditions == "closed")
    conditions = ["open","closed"];
end

% Average segment-level HFD within Subject x Group x Condition
[G, subj_u, group_u, cond_u] = findgroups(SegT.SubjectID, SegT.Group_str, SegT.Condition_str);
HFD_subjcond = splitapply(@(x) mean(x,'omitnan'), SegT.HFD_seg, G);
N_segments   = splitapply(@numel, SegT.HFD_seg, G); %#ok<NASGU>

SubjCondT = table(HFD_subjcond, subj_u, group_u, cond_u, ...
    'VariableNames', {'HFD','SubjectID','Group_str','Condition_str'});

Tbase = table( ...
    SubjCondT.HFD, ...
    categorical(SubjCondT.Group_str, groups), ...
    categorical(SubjCondT.Condition_str, conditions), ...
    categorical(SubjCondT.SubjectID), ...
    string(SubjCondT.SubjectID), ...
    'VariableNames', {'HFD','Group','Condition','Subject','SubjectID'} );

% Left join (drop rows with missing covariates afterward)
tbl = outerjoin(Tbase, cov_keep, 'Keys','SubjectID', 'MergeKeys',true, 'Type','left');

% Drop rows without Age or Gender
miss = isnan(tbl.Age) | isundefined(tbl.Gender);
if any(miss)
    tbl(miss,:) = [];
end

% (Optional) center Age for stability
tbl.Age_c = (tbl.Age - mean(tbl.Age,'omitnan')) / std(tbl.Age,'omitnan');

% ===================== MODEL: Group * Condition + Age + Gender + (1|Subject) =====================
% Reference: Group=PBC, Condition=first level in "conditions" (ideally open), Gender=Female
lme = fitlme(tbl, 'HFD ~ Group * Condition + Age_c + Gender + (1|Subject)');

% Omnibus tests
a = anova(lme, 'DFMethod','satterthwaite');
disp(lme);
fprintf(' Fixed-effect tests (Satterthwaite):\n');
disp(a)

% ========= Pairwise comparisons (Holm-Bonferroni) =========
coefNames = string(lme.CoefficientNames);

% Indices for main group effects
idx_BP = find(coefNames == "Group_FHR_BP", 1);
idx_SZ = find(coefNames == "Group_FHR_SZ", 1);
if isempty(idx_BP) || isempty(idx_SZ)
    error('Could not find group coefficient names in the fitted model.');
end

% Indices for condition and interaction terms (robust to level naming)
cond_levels = categories(tbl.Condition);
if numel(cond_levels) ~= 2
    error('Expected exactly 2 Condition levels (e.g., open/closed). Found %d.', numel(cond_levels));
end
cond_ref   = string(cond_levels{1}); % reference (baseline)
cond_other = string(cond_levels{2}); % typically 'closed' if baseline is 'open'

% In MATLAB, the coefficient is named like: "Condition_<otherLevel>"
idx_CondOther = find(coefNames == "Condition_" + cond_other, 1);

% Interactions: "Group_FHR_BP:Condition_<otherLevel>" etc.
idx_Int_BP = find(coefNames == "Group_FHR_BP:Condition_" + cond_other, 1);
idx_Int_SZ = find(coefNames == "Group_FHR_SZ:Condition_" + cond_other, 1);

% If condition exists but interaction names differ, fail loudly
if isempty(idx_CondOther)
    error('Could not find condition coefficient name (expected "Condition_%s") in the fitted model.', cond_other);
end
if isempty(idx_Int_BP) || isempty(idx_Int_SZ)
    error('Could not find interaction coefficient names in the fitted model.');
end

[beta,~,statsFE] = fixedEffects(lme,'DFMethod','satterthwaite');
if isfield(statsFE,'Covariance')
    CovB = statsFE.Covariance;
else
    CovB = lme.CoefficientCovariance;
end

fprintf('\n===== Pairwise group comparisons within each condition (Holm-Bonferroni) =====\n');

for ci = 1:numel(conditions)
    cond = string(conditions(ci));
    fprintf('\n--- Condition: %s ---\n', cond);

    p = numel(coefNames);

    % Build contrasts for:
    % 1) FHR_BP vs PBC
    % 2) FHR_SZ vs PBC
    % 3) FHR_BP vs FHR_SZ
    %
    % For reference condition: use main group effects only.
    % For other condition: main group effect + interaction term.

    C1 = zeros(1,p);
    C2 = zeros(1,p);
    C3 = zeros(1,p);

    if cond == cond_ref
        % Group differences at reference condition
        C1(idx_BP) = 1;                  % FHR_BP - PBC
        C2(idx_SZ) = 1;                  % FHR_SZ - PBC
        C3(idx_BP) = 1; C3(idx_SZ) = -1; % FHR_BP - FHR_SZ
    elseif cond == cond_other
        % Group differences at other condition = main + interaction
        C1(idx_BP) = 1; C1(idx_Int_BP) = 1;                     % (BP - PBC) at other condition
        C2(idx_SZ) = 1; C2(idx_Int_SZ) = 1;                     % (SZ - PBC) at other condition
        C3(idx_BP) = 1; C3(idx_SZ) = -1; C3(idx_Int_BP) = 1; C3(idx_Int_SZ) = -1; % (BP - SZ) at other condition
    else
        error('Unexpected Condition level: %s', cond);
    end

    C = [C1; C2; C3];
    pair_names = { 'FHR_BP vs PBC'; 'FHR_SZ vs PBC'; 'FHR_BP vs FHR_SZ' };

    raw_p  = nan(3,1);
    est    = nan(3,1);
    se     = nan(3,1);
    df2    = nan(3,1);

    for j = 1:3
        [p_j, ~, ~, df2_j] = coefTest(lme, C(j,:));
        raw_p(j) = p_j;
        df2(j)   = df2_j;

        est(j) = C(j,:)*beta;
        se(j)  = sqrt(C(j,:)*CovB*C(j,:)');
    end

    % Holm-Bonferroni
    m = numel(raw_p);
    [p_sorted, idx_sorted] = sort(raw_p);
    adj = nan(m,1);
    for k = 1:m
        adj(idx_sorted(k)) = min((m - k + 1) * p_sorted(k), 1);
    end

    % 95% CI with Satterthwaite df
    for j = 1:3
        alpha = 0.05;
        tcrit = tinv(1 - alpha/2, df2(j));
        ci_lo = est(j) - tcrit*se(j);
        ci_hi = est(j) + tcrit*se(j);

        switch j
            case 1, dir_txt = ternary(est(j)>0, 'FHR_BP > PBC', ternary(est(j)<0,'PBC > FHR_BP','No clear direction'));
            case 2, dir_txt = ternary(est(j)>0, 'FHR_SZ > PBC', ternary(est(j)<0,'PBC > FHR_SZ','No clear direction'));
            case 3, dir_txt = ternary(est(j)>0, 'FHR_BP > FHR_SZ', ternary(est(j)<0,'FHR_SZ > FHR_BP','No clear direction'));
        end

        fprintf('  %s: est = %.5f, SE = %.5f, 95%% CI [%.5f, %.5f], raw p = %.4f, Holm p = %.4f (%s)\n', ...
                pair_names{j}, est(j), se(j), ci_lo, ci_hi, raw_p(j), adj(j), dir_txt);
    end
end
%% ==========================================================================================
%% ======== 4. Plotting of robustness of HFD group differences via k_max variation ==========
%% ==========================================================================================

%% ================= 4.1 Calculation of HFD with varying k_max ==============================
clear; clc;
eeglab nogui;

% ---------------- User paths ----------------
trimmed_path       = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/4_Trimmed_files/';
trimmed_path       = char(trimmed_path);
data_analysis_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/5_Data_analysis_files/';
data_analysis_path = char(data_analysis_path);
excel_file         = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/VIA15_Masterfile_Cleaned.xlsx';
chanloc_file       = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/biosemi128.sfp';

results_file = fullfile(data_analysis_path, 'complexity_results_HFD_kmax3to100.mat');

% ---------------- Channels ------------------
exg_channels = {'EXG1','EXG2','EXG3','EXG4','EXG5','EXG6','EXG7','EXG8'};
excluded_channels = unique([exg_channels]);

% ---------------- Intervals -----------------
interval_labels = { ...
 'timepoint_0_to_30','timepoint_30_to_60','timepoint_60_to_90','timepoint_90_to_120', ...
 'timepoint_120_to_150','timepoint_150_to_180','timepoint_180_to_210','timepoint_210_to_240', ...
 'timepoint_240_to_270','timepoint_270_to_300','timepoint_300_to_330','timepoint_330_to_360'};

% --------------- HFD sweep ------------------
Kmax_values      = 3:100;   % requested sweep
min_run_seconds  = 2;       % same as existing code

% --------------- Load groups ----------------
T = readtable(excel_file, 'VariableNamingRule','preserve');
vars = T.Properties.VariableNames;

use_col = '';
if any(strcmp(vars,'hgr_status'))
    use_col = 'hgr_status';
elseif any(strcmp(vars,'fhr_group'))
    use_col = 'fhr_group';
else
    error('Missing hgr_status/fhr_group in Excel.');
end

subject_groups = containers.Map('KeyType','char','ValueType','char');
for i = 1:height(T)
    if isnan(T.id(i)), continue; end
    sid = sprintf('%03d', T.id(i));
    v = T.(use_col)(i);
    if iscell(v), v = v{1}; end
    v = string(v);
    if ~ismissing(v) && strlength(v) > 0
        subject_groups(sid) = char(v);
    end
end

% --------------- Files & results ------------
segment_files = dir(fullfile(trimmed_path, '*_trimmed25.set'));

results = struct( ...
    'subj_id',{}, ...
    'group',{}, ...
    'condition',{}, ...
    'interval_idx',{}, ...
    'interval_key',{}, ...
    'channel_labels_all',{}, ...
    'included_mask',{}, ...
    'channel_labels_included',{}, ...
    'kmax_values',{}, ...
    'fd_by_kmax',{} );   % size = [nChannels x nKmax]

% ----------------- Main loop ----------------
for f = 1:length(segment_files)
    try
        t0 = tic;
        file = segment_files(f).name;
        [~, name] = fileparts(file);

        % Subject ID = first 3 digits
        subj_id = regexp(name, '^\d{3}', 'match', 'once');
        if isempty(subj_id), continue; end

        % Parse interval key
        tok = regexp(name, '_segment_(timepoint_\d+-timepoint_\d+)_trimmed25$', 'tokens', 'once');
        if isempty(tok), continue; end
        raw_interval_key = tok{1};

        tokens   = split(raw_interval_key, '-');
        start_pt = regexp(tokens{1}, '\d+', 'match', 'once');
        end_pt   = regexp(tokens{2}, '\d+', 'match', 'once');
        if isempty(start_pt) || isempty(end_pt), continue; end

        interval_key = ['timepoint_' start_pt '_to_' end_pt];
        interval_idx = find(strcmp(interval_labels, interval_key), 1);
        if isempty(interval_idx), continue; end

        % Same open/closed logic as the existing code
        condition = ternary(mod(interval_idx,2)==1, 'open', 'closed');

        if ~isKey(subject_groups, subj_id), continue; end
        group = subject_groups(subj_id);

        % Load EEG
        EEG = pop_loadset('filename', file, 'filepath', trimmed_path);
        if isempty(EEG) || isempty(EEG.data), continue; end

        if isempty(EEG.chanlocs) || all(arrayfun(@(c) ~isfield(c,'X') || isempty(c.X), EEG.chanlocs))
            EEG = pop_chanedit(EEG, 'lookup', chanloc_file);
        end

        n_channels = size(EEG.data, 1);
        fs = EEG.srate;
        nK = numel(Kmax_values);

        % Channel labels
        ch_labels_all = cell(1, n_channels);
        for ch = 1:n_channels
            if ch <= numel(EEG.chanlocs) && isfield(EEG.chanlocs(ch), 'labels') && ~isempty(EEG.chanlocs(ch).labels)
                ch_labels_all{ch} = EEG.chanlocs(ch).labels;
            else
                ch_labels_all{ch} = sprintf('Ch%03d', ch);
            end
        end

        % Inclusion mask (same logic as the existing code)
        included_mask = true(1, n_channels);
        for ch = 1:n_channels
            if ismember(ch_labels_all{ch}, excluded_channels)
                included_mask(ch) = false;
            end
        end
        channel_labels_included = ch_labels_all(included_mask);

        % HFD results: one row per channel, one column per Kmax
        fd_by_kmax = nan(n_channels, nK);

        % ---------- Per-channel loop ----------
        for ch = 1:n_channels
            if ~included_mask(ch), continue; end

            x = double(EEG.data(ch, :));
            if ~any(isfinite(x)), continue; end

            % Same NaN-run splitting as the existing script
            runs = get_non_nan_runs(x, fs, min_run_seconds);
            if isempty(runs), continue; end

            % For each Kmax, compute HFD on each run and average across runs
            for kk = 1:nK
                thisK = Kmax_values(kk);
                fd_runs = nan(1, numel(runs));

                for r = 1:numel(runs)
                    xr = runs{r};
                    if numel(xr) < 3 || all(xr == xr(1)), continue; end
                    fd_runs(r) = compute_hfd_exact(xr, thisK);  % same formula as before
                end

                fd_by_kmax(ch, kk) = mean(fd_runs, 'omitnan');
            end
        end

        % Save entry
        idx = numel(results) + 1;
        results(idx).subj_id                 = subj_id;
        results(idx).group                   = group;
        results(idx).condition               = condition;
        results(idx).interval_idx            = interval_idx;
        results(idx).interval_key            = interval_key;
        results(idx).channel_labels_all      = ch_labels_all;
        results(idx).included_mask           = included_mask;
        results(idx).channel_labels_included = channel_labels_included;
        results(idx).kmax_values             = Kmax_values;
        results(idx).fd_by_kmax              = fd_by_kmax;

        % Quick console summary: average across included channels for each Kmax
        avg_curve = mean(fd_by_kmax(included_mask, :), 1, 'omitnan');
        fprintf('✓ %s | %s | int %d (%s) | Kmax %d:%d | mean(HFD) range = [%.4f %.4f] | %.1fs\n', ...
            file, subj_id, interval_idx, condition, ...
            Kmax_values(1), Kmax_values(end), ...
            min(avg_curve, [], 'omitnan'), max(avg_curve, [], 'omitnan'), toc(t0));
        drawnow limitrate;

    catch ME
        fprintf('⚠️ Error in file %s: %s\n', segment_files(f).name, ME.message);
        continue;
    end
end

% Save once at the end
save(results_file, 'results', '-v7.3');
fprintf('💾 Saved HFD Kmax-sweep results to %s\n', results_file);

%% ----------------- Helpers -----------------


function kFD = compute_hfd_exact(X, Kmax)
% Exact same HFD computation logic as in the current code
    X = X(:)'; 
    N = numel(X);

    if nargin < 2 || isempty(Kmax)
        Kmax = 10;
    end
    if N < 4
        kFD = NaN;
        return;
    end

    Kmax = max(2, min(Kmax, floor(N/4)));

    L = nan(Kmax,1);
    x = nan(Kmax,1);

    for k = 1:Kmax
        Lk = nan(1,k);
        for m = 1:k
            idx = m:k:N;
            n = numel(idx);
            if n > 1
                Lmk = sum(abs(diff(X(idx)))) * (N - 1) / (k * (n - 1) * k);
                Lk(m) = Lmk;
            end
        end
        L(k) = mean(Lk, 'omitnan');
        x(k) = log(1/k);
    end

    y = log(L);
    valid = isfinite(x) & isfinite(y);

    if sum(valid) < 2
        kFD = NaN;
    else
        p = polyfit(x(valid), y(valid), 1);
        kFD = p(1);
    end
end


%% ================= 4.2 Plotting Group-level HFD with varying k_max ===========================

clear; clc;

% ---------------- Paths ----------------
data_analysis_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/5_Data_analysis_files/';
data_analysis_path = char(data_analysis_path);

results_file = fullfile(data_analysis_path, 'complexity_results_HFD_kmax3to100.mat');
outdir = fullfile(data_analysis_path, 'Plots_HFD_KmaxSweep');
if ~exist(outdir, 'dir')
    mkdir(outdir);
end

% ---------------- Load -----------------
S = load(results_file);
results = S.results;

if isempty(results)
    error('No results found in %s', results_file);
end

% ---------------- Colors ----------------
color_map = containers.Map( ...
    {'FHR_SZ','FHR_BP','PBC'}, ...
    {[0 175 194]/255, [140 208 219]/255, [148 192 28]/255} );

group_order = {'FHR_SZ','FHR_BP','PBC'};
conditions_to_plot = {'open','closed'};

% Infer Kmax vector from first valid entry
k_entry = [];
for i = 1:numel(results)
    if isfield(results(i), 'kmax_values') && ~isempty(results(i).kmax_values)
        k_entry = i;
        break;
    end
end

if isempty(k_entry)
    error('No valid kmax_values found in results.');
end

Kmax_values = results(k_entry).kmax_values(:)';   % force row vector
nK = numel(Kmax_values);

% Force metadata vectors to column vectors to avoid logical indexing bugs
all_groups = string({results.group})';
all_conditions = string({results.condition})';

% Require subject IDs for within-subject averaging across segments
if ~isfield(results, 'subj_id')
    error('results does not contain subj_id, which is required for within-subject averaging.');
end
all_subjects = string({results.subj_id})';

% ---------- Build one segment-level curve per results-entry ----------
% Each results-entry = one segment file
% Curve = mean HFD across included channels, for each Kmax
segment_curves = nan(numel(results), nK);

for i = 1:numel(results)
    r = results(i);

    if ~isfield(r, 'fd_by_kmax') || isempty(r.fd_by_kmax)
        continue;
    end
    if ~isfield(r, 'included_mask') || isempty(r.included_mask)
        continue;
    end

    fdmat = r.fd_by_kmax;      % expected size = [nChannels x nK]
    mask  = logical(r.included_mask(:));   % force column logical vector

    if isempty(fdmat) || isempty(mask)
        continue;
    end

    if size(fdmat,1) ~= numel(mask)
        warning('Skipping result %d because size mismatch between fd_by_kmax and included_mask.', i);
        continue;
    end

    if size(fdmat,2) ~= nK
        warning('Skipping result %d because fd_by_kmax has %d columns, expected %d.', ...
            i, size(fdmat,2), nK);
        continue;
    end

    included_rows = find(mask);
    if isempty(included_rows)
        continue;
    end

    segment_curves(i,:) = mean(fdmat(included_rows, :), 1, 'omitnan');
end

% ---------- Plot one figure for open and one for closed ----------
for ci = 1:numel(conditions_to_plot)
    cond = conditions_to_plot{ci};

    fig = figure('Color','w', 'Position', [100 100 950 650]);
    hold on;
    set(gca, 'FontSize', 12, 'FontName', 'Helvetica', 'Box', 'off', 'LineWidth', 1.2);

    h_leg = gobjects(1, numel(group_order));

    for gi = 1:numel(group_order)
        gname = group_order{gi};

        idx = (all_groups == string(gname)) & (all_conditions == string(cond));
        idx = idx(:);   % force column vector

        curves_g = segment_curves(idx, :);
        subjects_g = all_subjects(idx);
        subjects_g = subjects_g(:);   % force column vector

        % Keep only rows that have at least one finite value
        valid_curve_rows   = any(isfinite(curves_g), 2);
        valid_subject_rows = ~ismissing(subjects_g) & (strlength(subjects_g) > 0);

        % Safety check
        if numel(valid_curve_rows) ~= numel(valid_subject_rows)
            warning('Skipping %s | %s because row counts do not match.', gname, cond);
            continue;
        end

        valid_rows = valid_curve_rows & valid_subject_rows;

        curves_g = curves_g(valid_rows, :);
        subjects_g = subjects_g(valid_rows);

        if isempty(curves_g)
            fprintf('No data for %s | %s\n', gname, cond);
            continue;
        end

        % ---------- Average segments within subject first ----------
        unique_subjects = unique(subjects_g, 'stable');
        unique_subjects = unique_subjects(:);   % force column vector

        subject_curves = nan(numel(unique_subjects), nK);

        for si = 1:numel(unique_subjects)
            sid = unique_subjects(si);
            idx_sub = (subjects_g == sid);

            if any(idx_sub)
                subject_curves(si, :) = mean(curves_g(idx_sub, :), 1, 'omitnan');
            end
        end

        % Keep only subjects that have at least one finite value
        valid_subjects = any(isfinite(subject_curves), 2);
        subject_curves = subject_curves(valid_subjects, :);

        if isempty(subject_curves)
            fprintf('No valid subject-level data for %s | %s\n', gname, cond);
            continue;
        end

        % ---------- Then average across subjects ----------
        mu = mean(subject_curves, 1, 'omitnan');
        n  = sum(isfinite(subject_curves), 1);
        sd = std(subject_curves, 0, 1, 'omitnan');

        sem = nan(1, nK);
        sem(n > 1) = sd(n > 1) ./ sqrt(n(n > 1));
        sem(n == 1) = 0;

        c = color_map(gname);

        % Only plot finite points
        valid_k = isfinite(mu) & isfinite(sem) & isfinite(Kmax_values);

        if ~any(valid_k)
            fprintf('No plottable finite values for %s | %s\n', gname, cond);
            continue;
        end

        x_plot = Kmax_values(valid_k);
        mu_plot = mu(valid_k);
        sem_plot = sem(valid_k);

        % Shaded SEM
        x_fill = [x_plot, fliplr(x_plot)];
        y_fill = [mu_plot + sem_plot, fliplr(mu_plot - sem_plot)];
        fill(x_fill, y_fill, c, ...
            'FaceAlpha', 0.20, ...
            'EdgeColor', 'none', ...
            'HandleVisibility', 'off');

        % Mean line
        h_leg(gi) = plot(x_plot, mu_plot, ...
            'Color', c, ...
            'LineWidth', 2.2, ...
            'DisplayName', gname);
    end

    xlabel('K_{max}', 'FontName', 'Helvetica');
    ylabel('Higuchi Fractal Dimension', 'FontName', 'Helvetica');

    if strcmpi(cond, 'open')
        title('Open eyes', 'FontName', 'Helvetica', 'FontWeight', 'normal');
    elseif strcmpi(cond, 'closed')
        title('Closed eyes', 'FontName', 'Helvetica', 'FontWeight', 'normal');
    else
        title(cond, 'FontName', 'Helvetica', 'FontWeight', 'normal');
    end

    grid on;
    xlim([min(Kmax_values), max(Kmax_values)]);
    ylim([1.2,1.8])
    
    % Legend in requested order, only for groups that were actually plotted
    plotted = isgraphics(h_leg);
    if any(plotted)
        legend(h_leg(plotted), group_order(plotted), ...
            'Location', 'southeast', ...
            'FontSize', 16, ...
            'Box', 'off', ...
            'FontName', 'Helvetica', ...
            'Interpreter','none');
    end

    % Save
    outname = fullfile(outdir, sprintf('HFD_vs_Kmax_%s_meanSEM.png', lower(cond)));
    exportgraphics(fig, outname, 'Resolution', 200);
    fprintf('Saved: %s\n', outname);

    close(fig);
end



%% ==========================================================================================
%% ========================= 5. HFD per preprocessing step ==================================
%% ==========================================================================================

%% ==========================================================================================
%% ================= 5.1 Plotting HFD per preprocessing step ================================
%% ==========================================================================================
% This code:
% 1) loads the saved `results`
% 2) computes one HFD value per segment as the mean across included channels
% 3) averages segments WITHIN each subject for each preprocessing step and condition
% 4) computes group mean and SEM across subjects
% 5) makes:
%       - 1 plot for open eyes
%       - 1 plot for closed eyes
%    with faded SEM bands around the group means

clearvars; clc;

% ---------------- Paths ----------------
data_analysis_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/5_Data_analysis_files/';
data_analysis_path = char(data_analysis_path);
results_file = fullfile(data_analysis_path, 'complexity_results_all_steps_final.mat');

outdir = fullfile(data_analysis_path, 'Plots_HFD_PreprocessingSteps');
if ~exist(outdir, 'dir')
    mkdir(outdir);
end

% ---------------- Colors ----------------
color_map = containers.Map( ...
    {'FHR_SZ','FHR_BP','PBC'}, ...
    {[0 175 194]/255, [140 208 219]/255, [148 192 28]/255} );

group_order = {'FHR_SZ','FHR_BP','PBC'};
conditions_to_plot = {'open','closed'};

% ---------------- Load results ----------------
S = load(results_file);
results = S.results;

if isempty(results)
    error('The results structure is empty.');
end

% ---------------- Keep only entries with a preprocessing step ----------------
has_step = ~cellfun(@isempty, {results.preprocessing_step});
results = results(has_step);

if isempty(results)
    error('No results with preprocessing_step were found.');
end

% ---------------- Keep only selected preprocessing steps ----------------
steps_to_keep = {'step03','step04','step05','step06','step08','step12'};
keep_mask = ismember({results.preprocessing_step}, steps_to_keep);
results = results(keep_mask);

if isempty(results)
    error('No results remained after filtering to selected preprocessing steps.');
end

% ---------------- Define preprocessing-step order and display labels ----------------
step_labels = {'step03','step04','step05','step06','step08','step12'};
step_display_labels = {'Raw', ...
                       'Resampling 256 Hz', ...
                       'Bandpass 0.5-100 Hz', ...
                       'Notch filter 49-51, 99-101 Hz', ...
                       'Average rereference', ...
                       'Artifact NaN masking'};

nSteps = numel(step_labels);
x = 1:nSteps;

fprintf('Detected preprocessing steps to plot:\n');
disp(step_labels(:));

% ==========================================================================================
% Build subject-level table:
% For each segment result:
%   segment_hfd = mean(fd across included channels)
% Then average within subject for each condition + preprocessing step
% ==========================================================================================

subj_ids   = {results.subj_id}';
groups_all = {results.group}';
conds_all  = {results.condition}';
steps_all  = {results.preprocessing_step}';

segment_hfd = nan(numel(results),1);

for i = 1:numel(results)
    r = results(i);

    if ~isfield(r, 'fd') || isempty(r.fd) || ~isfield(r, 'included_mask') || isempty(r.included_mask)
        continue;
    end

    vals = r.fd(r.included_mask);
    if isempty(vals)
        segment_hfd(i) = NaN;
    else
        segment_hfd(i) = mean(vals, 'omitnan');
    end
end

% Remove rows without finite segment HFD
valid = isfinite(segment_hfd) & ~cellfun(@isempty, subj_ids) & ~cellfun(@isempty, groups_all) ...
        & ~cellfun(@isempty, conds_all) & ~cellfun(@isempty, steps_all);

subj_ids    = subj_ids(valid);
groups_all  = groups_all(valid);
conds_all   = conds_all(valid);
steps_all   = steps_all(valid);
segment_hfd = segment_hfd(valid);

if isempty(segment_hfd)
    error('No valid segment-level HFD values found.');
end

% Create a table for easier grouping
Tseg = table(subj_ids, groups_all, conds_all, steps_all, segment_hfd, ...
    'VariableNames', {'subj_id','group','condition','step','segment_hfd'});

% Average segments within subject for each condition + step
[Gsubj, subj_key, group_key, cond_key, step_key] = findgroups( ...
    Tseg.subj_id, Tseg.group, Tseg.condition, Tseg.step);

subject_mean_hfd = splitapply(@(x) mean(x, 'omitnan'), Tseg.segment_hfd, Gsubj);

Tsubj = table(subj_key, group_key, cond_key, step_key, subject_mean_hfd, ...
    'VariableNames', {'subj_id','group','condition','step','subject_mean_hfd'});

% ==========================================================================================
% Plot: one figure for open, one for closed
% ==========================================================================================

for c = 1:numel(conditions_to_plot)
    current_condition = conditions_to_plot{c};

    % Preallocate
    MU  = nan(numel(group_order), nSteps);
    SEM = nan(numel(group_order), nSteps);
    N   = zeros(numel(group_order), nSteps);

    % Compute group mean and SEM across SUBJECT means
    for g = 1:numel(group_order)
        current_group = group_order{g};

        for s = 1:nSteps
            current_step = step_labels{s};

            idx = strcmp(Tsubj.condition, current_condition) & ...
                  strcmp(Tsubj.group, current_group) & ...
                  strcmp(Tsubj.step, current_step);

            vals = Tsubj.subject_mean_hfd(idx);

            vals = vals(isfinite(vals));

            if isempty(vals)
                MU(g,s)  = NaN;
                SEM(g,s) = NaN;
                N(g,s)   = 0;
            else
                MU(g,s) = mean(vals, 'omitnan');
                N(g,s)  = numel(vals);

                if numel(vals) > 1
                    SEM(g,s) = std(vals, 'omitnan') / sqrt(numel(vals));
                else
                    SEM(g,s) = 0;
                end
            end
        end
    end

    % ---------------- Figure ----------------
    fig = figure('Color','w', 'Position', [100 100 1400 650]);
    hold on;

    set(gca, 'FontSize', 12, 'FontName', 'Helvetica', 'LineWidth', 1);

    h_line = gobjects(numel(group_order),1);

    % Plot SEM as faded patch, then mean line on top
    for g = 1:numel(group_order)
        current_group = group_order{g};

        if isKey(color_map, current_group)
            this_color = color_map(current_group);
        else
            this_color = [0 0 0];
        end

        mu  = MU(g,:);
        sem = SEM(g,:);

        valid_pts = isfinite(mu) & isfinite(sem);

        if any(valid_pts)
            xv = x(valid_pts);
            upper = mu(valid_pts) + sem(valid_pts);
            lower = mu(valid_pts) - sem(valid_pts);

            patch([xv, fliplr(xv)], [upper, fliplr(lower)], this_color, ...
                'FaceAlpha', 0.18, ...
                'EdgeColor', 'none', ...
                'HandleVisibility', 'off');
        end

        h_line(g) = plot(x, mu, '-o', ...
            'Color', this_color, ...
            'MarkerFaceColor', this_color, ...
            'MarkerEdgeColor', this_color, ...
            'LineWidth', 2.2, ...
            'MarkerSize', 6, ...
            'DisplayName', current_group);
    end

    % ---------------- Axes formatting ----------------
    xlim([0.5, nSteps + 0.5]);
    xticks(x);
    xticklabels(step_display_labels);
    xtickangle(45);

    ylabel('Mean HFD', 'FontName', 'Helvetica');
    xlabel('Preprocessing step', 'FontName', 'Helvetica');

    if strcmpi(current_condition, 'open')
        title('Open eyes: mean HFD across preprocessing steps', ...
            'FontName', 'Helvetica', 'FontWeight', 'normal');
    else
        title('Closed eyes: mean HFD across preprocessing steps', ...
            'FontName', 'Helvetica', 'FontWeight', 'normal');
    end

    grid on;
    box on;

    % Y-limits
    y_min = 1.35;
    y_max = 1.85;
    ylim([y_min y_max]);

    legend(h_line, group_order, ...
    'Location', 'best', ...
    'Box', 'off', ...
    'FontName', 'Helvetica', ...
    'Interpreter', 'none');


    % ---------------- Save ----------------
    outname_png = fullfile(outdir, sprintf('HFD_by_preprocessing_step_%s.png', current_condition));
    exportgraphics(fig, outname_png, 'Resolution', 300);

    fprintf('Saved plot: %s\n', outname_png);

    close(fig);
end


fprintf('\nSubject counts per group/step/condition were based on subject-averaged segment HFD values.\n');
fprintf('That means all segments within a subject were averaged first, before group means and SEM were computed.\n');

%% ========================================================================================== %%
%% ============================== 6. SPECTRAL INVESTIGATION ================================= %%
%% ========================================================================================== %%

%% ============ 6.1 Compute per-condition relative band power (per group) ==================
% Computes relative power per band per channel from each *_trimmed25.set file,
% aligns to BioSemi-128 montage, excludes ONLY EXG channels, groups by condition (open/closed),
% averages over subjects/intervals within each group & condition, then saves to .mat.
%
% Output data file: {trimmed_path}/Plots_Bandpower_ByGroup/bandpower_by_group_cond.mat

% ---------- EDIT THESE PATHS IF NEEDED ----------
excel_file        = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/VIA15_Masterfile_Cleaned.xlsx';
data_analysis_path= '/mnt/projects/VIA_MHA/VIA15_Rest/Final/5_Data_analysis_files/';
trimmed_path      = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/4_Trimmed_files/';
chanloc_file      = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/biosemi128.sfp';

% -------- Minimum continuous data required per channel (in seconds) --------
min_continuous_sec = 15;   % only use channels with ≥15 s of continuous usable data

addpath('/home/mathiasha/MATLAB_Add-Ons/Collections/eeglab2026.0.0/')
savepath

eeglab nogui;

% ------------------------------------------------

% Ensure EEGLAB plotting functions are available
if exist('topoplot','file')~=2
    try
        eeglab nogui; close all;
    catch
        error('EEGLAB (topoplot) not found on path. Please add EEGLAB to MATLAB path.');
    end
end

% -------- Bands (Hz) --------
bands = struct( ...
    'theta', [4 8], ...
    'alpha', [8 13], ...
    'beta',  [13 30], ...
    'gamma', [30 100] );      % extend gamma to 100 Hz to match the plots
band_names = fieldnames(bands);
B = numel(band_names);

% -------- Total range for relative power normalization --------
% Make the denominator automatically cover ALL band edges defined.
all_edges   = cell2mat(struct2cell(bands));   % 2 x B stacked as a vector
all_edges   = reshape(all_edges, 2, []).';    % B x 2 [lo hi]
total_range = [min(all_edges(:,1)), max(all_edges(:,2))];   % e.g., [0.5 100]

% -------- Conditions ----------
cond_names = ["open","closed"];  % fixed order
C = numel(cond_names);

% -------- Group mapping from Excel (hgr_status or fhr_group) --------
T    = readtable(excel_file, 'VariableNamingRule','preserve');
vars = T.Properties.VariableNames;
use_col = '';
if any(strcmp(vars,'hgr_status'))
    use_col = 'hgr_status';
elseif any(strcmp(vars,'fhr_group'))
    use_col = 'fhr_group';
else
    error('Missing hgr_status/fhr_group in Excel.');
end

subject_groups = containers.Map('KeyType','char','ValueType','char');
for i = 1:height(T)
    if isnan(T.id(i)), continue; end
    sid = sprintf('%03d', T.id(i));
    v   = T.(use_col)(i); if iscell(v), v = v{1}; end
    v   = string(v);
    if ~ismissing(v) && strlength(v)>0
        subject_groups(sid) = char(v);
    end
end

% -------- Files --------
segment_files = dir(fullfile(trimmed_path, '*step12*_trimmed25.set'));
if isempty(segment_files)
    error('No *_trimmed25.set files found in %s', trimmed_path);
end

% -------- Load common channel locations (BioSemi 128) --------
if exist('readlocs','file')==2
    common_chanlocs = readlocs(chanloc_file, 'filetype', 'sfp');
else
    EEGtmp = eeg_emptyset();
    EEGtmp = pop_chanedit(EEGtmp, 'load',{chanloc_file 'filetype' 'sfp'});
    common_chanlocs = EEGtmp.chanlocs;
end
if isempty(common_chanlocs)
    error('Failed to load channel locations from %s', chanloc_file);
end
common_labels = arrayfun(@(c) c.labels, common_chanlocs, 'uni', 0);
nCommon       = numel(common_labels);

label_to_idx = containers.Map('KeyType','char','ValueType','double');
for i = 1:nCommon
    lab = common_labels{i};
    if ~isempty(lab)
        label_to_idx(lab) = i;
    end
end

% -------- Exclude ONLY EXG channels --------
is_exg_common      = startsWith(string(common_labels), "EXG", 'IgnoreCase', true);
final_exclude_mask = is_exg_common'; % logical nCommon×1; only EXG

% -------- Prepare aggregation --------
all_group_names = {};
for f = 1:numel(segment_files)
    nm  = segment_files(f).name;
    sid = regexp(nm, '^\d{3}', 'match', 'once');
    if ~isempty(sid) && isKey(subject_groups, sid)
        all_group_names{end+1} = subject_groups(sid); %#ok<AGROW>
    end
end
groups_unique = unique(string(all_group_names), 'stable');
desired_order = ["FHR_SZ","FHR_BP","PBC"]; % Group order
ordered       = desired_order(ismember(desired_order, groups_unique));
others        = groups_unique(~ismember(groups_unique, desired_order));
groups        = [ordered, others];
if isempty(groups)
    error('No recognizable groups in files/Excel.');
end
G = numel(groups);

% Stacks: for each band × group × condition → nCommon × N_subjects
band_stacks_cond = cell(B, G, C);
for bi = 1:B
    for gi = 1:G
        for ci = 1:C
            band_stacks_cond{bi,gi,ci} = [];
        end
    end
end

% Accumulate SEGMENTS within each subject first, then average within subject
subject_sum_map   = containers.Map('KeyType','char','ValueType','any');
subject_count_map = containers.Map('KeyType','char','ValueType','any');
subject_group_map = containers.Map('KeyType','char','ValueType','char');
subject_cond_map  = containers.Map('KeyType','char','ValueType','char');

fprintf('Computing relative bandpower per file/channel, split by condition, aggregating by group...\n');

for f = 1:numel(segment_files)
    try
        file        = segment_files(f).name;
        [~, name]   = fileparts(file);

        % subj_id = first three digits at the start of the filename (e.g., '408')
        subj_id = regexp(name, '^\d{3}', 'match', 'once');
        if isempty(subj_id) || ~isKey(subject_groups, subj_id), continue; end
        gname = string(subject_groups(subj_id));
        gi    = find(groups==gname, 1);
        if isempty(gi), continue; end

        % ---- Robust parse of condition from filename (works regardless of nested groups)
        % Expect "..._segment_timepoint_<start>-timepoint_<end>_trimmed25"
        nums = regexp(name, 'timepoint_(\d+)-timepoint_(\d+)', 'tokens', 'once');
        if isempty(nums), continue; end
        start_pt = str2double(nums{1});   % e.g., 0,30,60,...
        if ~isfinite(start_pt), continue; end
        interval_idx = round(start_pt/30) + 1; % 1..12
        cond = ternary(mod(interval_idx,2)==1, "open", "closed");
        ci   = find(cond_names==cond, 1);
        if isempty(ci), continue; end

        EEG = pop_loadset('filename', file, 'filepath', trimmed_path);
        if isempty(EEG) || isempty(EEG.data), continue; end
        if isempty(EEG.chanlocs) || all(arrayfun(@(c) ~isfield(c,'X')||isempty(c.X), EEG.chanlocs))
            EEG = pop_chanedit(EEG, 'lookup', chanloc_file);
        end

        fs = EEG.srate;
        if ~isfinite(fs) || fs<=0, continue; end

        % Channel labels present in this file
        nCh         = size(EEG.data,1);
        file_labels = cell(1,nCh);
        for ch = 1:nCh
            if ch <= numel(EEG.chanlocs) && isfield(EEG.chanlocs(ch),'labels') && ~isempty(EEG.chanlocs(ch).labels)
                file_labels{ch} = EEG.chanlocs(ch).labels;
            else
                file_labels{ch} = sprintf('Ch%03d', ch);
            end
        end

        % PSD via Welch
        win   = max(round(2*fs), 256);
        nover = round(0.5*win);

        rel_power_aligned = nan(nCommon, B);

        for ch = 1:nCh
            lab = file_labels{ch};
            if ~isKey(label_to_idx, lab), continue; end
            common_idx = label_to_idx(lab);
            if final_exclude_mask(common_idx), continue; end % skip EXG only

            x = double(EEG.data(ch,:));

            % ---- NaN-safe cleanup & continuous-data criterion ----
            ok = isfinite(x);

            % require at least 15 s of *continuous* finite data
            min_cont_samples = round(min_continuous_sec * fs);

            if nnz(ok) < min_cont_samples
                continue;
            end

            % compute longest run of consecutive finite samples
            max_run     = 0;
            current_run = 0;
            for i_s = 1:numel(ok)
                if ok(i_s)
                    current_run = current_run + 1;
                    if current_run > max_run
                        max_run = current_run;
                    end
                else
                    current_run = 0;
                end
            end
            if max_run < min_cont_samples
                continue;
            end

            % After enforcing continuity, do the usual interpolation to clean gaps
            if ~all(ok)
                t  = 1:numel(x);
                ti = t(ok);
                xi = x(ok);
                x(~ok) = interp1(ti, xi, t(~ok), 'linear', 'extrap');
                firstIdx = find(ok,1,'first');
                lastIdx  = find(ok,1,'last');
                if firstIdx>1, x(1:firstIdx-1) = x(firstIdx); end
                if lastIdx < numel(x), x(lastIdx+1:end) = x(lastIdx); end
            end

            if ~any(isfinite(x)) || std(x)==0, continue; end
            % inline detrend_local: subtract mean
            x = x - mean(x, 'omitnan');

            % PSD
            try
                [Pxx, fvec] = pwelch(x, win, nover, [], fs);
            catch
                continue;
            end
            if ~all(isfinite(Pxx)) || ~all(isfinite(fvec)) || numel(Pxx)~=numel(fvec), continue; end

            % Total power for normalization (relative power denominator)
            sel_tot = fvec >= total_range(1) & fvec <= total_range(2);
            if nnz(sel_tot) < 2, continue; end
            Ptot = trapz(fvec(sel_tot), Pxx(sel_tot));
            if ~isfinite(Ptot) || Ptot <= 0, continue; end

            % Band powers → relative
            for bi = 1:B
                fr  = bands.(band_names{bi});
                sel = fvec >= fr(1) & fvec <= fr(2);
                if nnz(sel) < 2
                    bp = NaN;
                else
                    bp = trapz(fvec(sel), Pxx(sel));
                end
                rel_power_aligned(common_idx, bi) = bp / Ptot;   % fraction of total power
            end
        end % end ch loop

        % Accumulate this segment into its subject-specific condition average
        subj_key = sprintf('%s__%s', subj_id, char(cond));
        if ~isKey(subject_sum_map, subj_key)
            subject_sum_map(subj_key)   = zeros(nCommon, B);
            subject_count_map(subj_key) = zeros(nCommon, B);
            subject_group_map(subj_key) = char(gname);
            subject_cond_map(subj_key)  = char(cond);
        end

        sum_mat   = subject_sum_map(subj_key);
        count_mat = subject_count_map(subj_key);

        valid_mask = isfinite(rel_power_aligned);
        sum_mat(valid_mask)   = sum_mat(valid_mask) + rel_power_aligned(valid_mask);
        count_mat(valid_mask) = count_mat(valid_mask) + 1;

        subject_sum_map(subj_key)   = sum_mat;
        subject_count_map(subj_key) = count_mat;

        if mod(f,25)==0
            fprintf('  processed %d/%d files...\n', f, numel(segment_files));
        end

    catch ME
        fprintf('⚠️ Error in %s: %s\n', segment_files(f).name, ME.message);
        continue;
    end
end % end f loop

% Convert accumulated segment-level data to subject-level means,
% so each subject contributes equally regardless of number of segments
subj_keys = keys(subject_sum_map);
for k = 1:numel(subj_keys)
    subj_key   = subj_keys{k};
    sum_mat    = subject_sum_map(subj_key);
    count_mat  = subject_count_map(subj_key);
    gname_sub  = string(subject_group_map(subj_key));
    cond_sub   = string(subject_cond_map(subj_key));

    gi = find(groups==gname_sub, 1);
    ci = find(cond_names==cond_sub, 1);
    if isempty(gi) || isempty(ci), continue; end

    subj_mean = nan(nCommon, B);
    valid_counts = count_mat > 0;
    subj_mean(valid_counts) = sum_mat(valid_counts) ./ count_mat(valid_counts);

    for bi = 1:B
        band_stacks_cond{bi,gi,ci} = [band_stacks_cond{bi,gi,ci}, subj_mean(:,bi)]; %#ok<AGROW>
    end
end

% Compute group×condition means (nCommon x G x C x B)
topo_mean_cond = nan(nCommon, G, C, B);
for bi = 1:B
    for gi = 1:G
        for ci = 1:C
            X = band_stacks_cond{bi,gi,ci};
            if isempty(X)
                topo_mean_cond(:,gi,ci,bi) = nan(nCommon,1);
            else
                topo_mean_cond(:,gi,ci,bi) = mean(X, 2, 'omitnan');
            end
        end
    end
end

% Save to disk for plotting in 6.2
bp_out_dir  = fullfile(data_analysis_path, 'Plots_Bandpower_ByGroup');
if ~exist(bp_out_dir, 'dir'), mkdir(bp_out_dir); end
bp_mat_file = fullfile(bp_out_dir, 'bandpower_by_group_cond.mat');
save(bp_mat_file, 'topo_mean_cond', 'bands', 'band_names', 'cond_names', 'groups', 'common_chanlocs', 'common_labels');
fprintf('💾 Saved per-condition bandpower aggregates to %s\n', bp_mat_file);


%% ================== PART 6.2 Plot topoplots per condition per band ==================
% Rows = [PBC, FHR_BP, FHR_SZ], Columns = bands (lowest -> highest frequency).
% - All text in Arial
% - Prevent subscripts in labels with underscores (Interpreter='none')
% - Column labels = Band name + frequency span in Hz (Capitalized)
% - Gamma span (when names-only): 30–100 Hz
% - No global title; labels spaced further from topos. Column labels drawn with TEXT above axes.

% ---------- EDIT THIS OUTPUT IS MOVED ----------
bp_out_dir   = fullfile(data_analysis_path, 'Plots_Bandpower_ByGroup');
bp_mat_file  = fullfile(bp_out_dir, 'bandpower_by_group_cond.mat');
% ------------------------------------------------------

if ~exist(bp_mat_file, 'file')
    error('Aggregate file not found: %s. Run PART A first.', bp_mat_file);
end
S = load(bp_mat_file);
topo_mean_cond  = S.topo_mean_cond;    % nCommon x G x C x B
bands           = S.bands;             % may be numeric/struct/cell
band_names      = S.band_names;
cond_names      = S.cond_names;
groups          = S.groups;
common_chanlocs = S.common_chanlocs;

G = numel(groups);
C = numel(cond_names);
B = numel(band_names);

% --- Helpers
safe = @(s) regexprep(lower(char(string(s))), '\W+', '_');

% --- Group row order
desired_order = {'PBC','FHR_BP','FHR_SZ'};
grp_str = cellstr(string(groups));
[~, idx_in_groups] = ismember(desired_order, grp_str);
row_order  = idx_in_groups(idx_in_groups > 0);
row_labels = desired_order(idx_in_groups > 0);

% --- Band order + frequency spans
col_order = 1:B; lo_freq = nan(1,B); hi_freq = nan(1,B);
try
    if isnumeric(bands) && size(bands,2) >= 2
        lo_freq = bands(:,1).'; hi_freq = bands(:,2).';
        [~, col_order] = sort(hi_freq, 'ascend');  % LOW -> HIGH
    else
        for b = 1:B
            nm = char(lower(string(band_names{b})));
            [lo, hi] = default_span_from_name(nm);  % gamma -> [30 100]
            lo_freq(b)=lo; hi_freq(b)=hi;
        end
        [~, col_order] = sort(hi_freq,'ascend','MissingPlacement','last');
    end
catch
    col_order = 1:B;
end

% Column labels (text content)
col_titles = cell(1,B);
for c = 1:B
    bi = col_order(c);
    nm = ucfirst(lower(strip(char(string(band_names{bi})))));
    if isfinite(lo_freq(bi)) && isfinite(hi_freq(bi))
        col_titles{c} = sprintf('%s (%s)', nm, fmtSpan(lo_freq(bi), hi_freq(bi)));
    else
        col_titles{c} = nm;
    end
end

% Color limits
clims_low = zeros(1,B); clims_high = zeros(1,B);
for b = 1:B
    v = topo_mean_cond(:,:,:,b); v = v(:); v = v(isfinite(v));
    if isempty(v), clims_low(b)=0; clims_high(b)=1;
    else
        lo = prctile(v,5); hi = prctile(v,95);
        if ~isfinite(lo)||~isfinite(hi)||lo==hi, lo=0; hi=1; end
        clims_low(b)=lo; clims_high(b)=hi;
    end
end

out_dir = fullfile(bp_out_dir,'Topos_ConditionGrid_3xB_LoToHi');
if ~exist(out_dir,'dir'), mkdir(out_dir); end

% --- Tunable spacing for labels ---
label_y = 1.18;     % vertical position for column labels in normalized axes units (>1 puts them above the axes)
row_label_x = -0.30; % horizontal position for row labels (negative pushes left)

% ---------- Plot ----------
for ci = 1:C
    fig = figure('Color','w','Position',[100 100 1350 850]); % roomy

    % Global defaults: Arial, non-bold, +2 sizes
    baseTextSize = get(0,'DefaultTextFontSize');
    baseAxesSize = get(0,'DefaultAxesFontSize');
    if isempty(baseTextSize), baseTextSize = 10; end
    if isempty(baseAxesSize), baseAxesSize = 10; end
    set(fig, 'DefaultTextFontName','Arial', 'DefaultAxesFontName','Arial', ...
             'DefaultTextFontWeight','normal', 'DefaultAxesFontWeight','normal', ...
             'DefaultTextFontSize', baseTextSize+2, ...
             'DefaultAxesFontSize', baseAxesSize+2);

    tl = tiledlayout(numel(row_order),B,'Padding','loose','TileSpacing','loose');

    for r = 1:numel(row_order)
        gi = row_order(r);
        for c = 1:B
            bi_sorted = col_order(c);
            ax = nexttile(tl,(r-1)*B+c);
            dat = topo_mean_cond(:,gi,ci,bi_sorted);
            if ~any(isfinite(dat))
                axis(ax,'off');
                text(ax,0.5,0.5,'No data','HorizontalAlignment','center', ...
                    'FontName','Arial','Interpreter','none', 'FontWeight','normal', ...
                    'FontSize', baseTextSize+2);
            else
                topoplot(dat,common_chanlocs,'electrodes','off','style','map','plotrad',0.5, ...
                         'maplimits',[clims_low(bi_sorted),clims_high(bi_sorted)]);
                axis(ax,'tight');
            end

            % --- Column labels for the first row: draw as TEXT above the axis (not as title)
            if r==1
                text(ax, 0.5, label_y, col_titles{c}, ...
                    'Units','normalized', 'HorizontalAlignment','center', 'VerticalAlignment','bottom', ...
                    'FontWeight','normal', 'Interpreter','none', 'FontName','Arial', 'Clipping','off', ...
                    'FontSize', baseTextSize+2);
            end
        end

        % --- Row labels on the left
        firstTileAx = nexttile(tl,(r-1)*B+1);
        hold(firstTileAx,'on');
        text(firstTileAx, row_label_x, 0.5, row_labels{r}, ...
            'Units','normalized','HorizontalAlignment','right','VerticalAlignment','middle', ...
            'FontWeight','normal','Interpreter','none','FontName','Arial','Clipping','off', ...
            'FontSize', baseTextSize+2);
    end

    cb = colorbar;
    cb.Layout.Tile = 'east';
    cb.FontName = 'Arial';
    cb.FontWeight = 'normal';
    cb.FontSize = baseAxesSize+2;

    % No global title

    fname = fullfile(out_dir,sprintf('topogrid_%s_%dx%d.png',safe(cond_names(ci)),numel(row_order),B));
    exportgraphics(fig,fname,'Resolution',200);
    fprintf('Saved: %s\n',fname);
    close(fig);
end

fprintf('✅ Saved plots in:\n  %s\n',out_dir);


%% ----------------- Local helper functions -----------------
function s=fmtHz(x)
    if ~isfinite(x), s='NaN'; return; end
    if abs(x-round(x))<1e-6, s=sprintf('%d',round(x));
    else, s=sprintf('%.1f',round(x,1)); end
end
function s=fmtSpan(lo,hi), s=sprintf('%s–%s Hz',fmtHz(lo),fmtHz(hi)); end
function [lo,hi]=default_span_from_name(name_lower)
    lo=NaN; hi=NaN; n=regexprep(name_lower,'[^a-z0-9]+','');
    if contains(n,'highgamma')||contains(n,'hgamma'), lo=60; hi=150;
    elseif contains(n,'gamma'), lo=30; hi=100;
    elseif contains(n,'beta'), lo=13; hi=30;
    elseif contains(n,'alpha')||strcmp(n,'mu'), lo=8; hi=13;
    elseif contains(n,'theta'), lo=4; hi=8;
    elseif contains(n,'ultrahigh'), lo=150; hi=250;
    elseif contains(n,'infra'), lo=0.1; hi=0.5;
    elseif contains(n,'low'), lo=0.5; hi=4;
    end
end
function s=ucfirst(str_in)
    if isempty(str_in), s=str_in; return; end
    str_in=char(str_in); s=[upper(str_in(1)) lower(str_in(2:end))];
end


%% ================== PART 6.3 Spectral vs HFD ==================

% Goal:
% For each CONDITION, make 5 panels (theta/alpha/beta/gamma).
% Each dot is a SEGMENT (one of the 12), with:
%   x = relative power in that band (channel-avg, segment-level)
%   y = HFD (mean over included channels, segment-level)
% Dots are colored by GROUP.
%
% Uses:
% - HFD per-segment already saved in results_file (mean over included chans).
% - Segment files in trimmed_path to compute RELATIVE BAND POWER per segment.
%
% Notes:
% * EXG channels are excluded (only those), matching earlier parts.
% * Channels are aligned to BioSemi-128 using chanloc_file.
% * Robust filename parsing: expects "..._segment_timepoint_<start>-timepoint_<end>_trimmed25.set"

chanloc_file = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/biosemi128.sfp';
trimmed_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/4_Trimmed_files';
excel_file   = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/VIA15_Masterfile_Cleaned.xlsx'; %#ok<NASGU> % (not used here but kept for context)
data_analysis_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/5_Data_analysis_files/';
results_file = fullfile(data_analysis_path, 'complexity_results_all_steps_final.mat');  % contains per-channel results now

% Path to cached calc results
power_fd_segments_file = fullfile(trimmed_path, 'power_fd_segments.mat');

% Toggle to force recomputation even if cache exists
force_recompute = false;

% ----------------------- Bands & plotting order -----------------------
bands = struct( ...
  'theta', [4 8], ...
  'alpha', [8 13], ...
  'beta',  [13 30], ...
  'gamma', [30 100] );
band_names = {'theta','alpha','beta','gamma'};
B = numel(band_names);

% ----------------------- Colors by group (consistent with earlier) -----------------------
color_map = containers.Map( ...
  {'PBC','FHR_BP','FHR_SZ'}, ...
  {[148 192 28]/255, [140 208 219]/255, [0 175 194]/255} );

% =============================== CALCULATION PART ===============================
% (Runs once and caches to power_fd_segments_file; later runs can just load and plot)
need_calc = force_recompute || ~exist('power_fd_segments','var') || isempty(power_fd_segments);
if ~need_calc
  % Still verify the variables required for plotting exist
  need_calc = ~istable(power_fd_segments) || ~all(ismember({'Subject','Group','Condition','IntervalIdx','Band','RelPower','HFD'}, power_fd_segments.Properties.VariableNames));
end

if ~need_calc && ~isfile(power_fd_segments_file)
  % We have a variable in memory but no cache on disk; that's fine—no calc needed.
elseif ~need_calc && isfile(power_fd_segments_file)
  % Prefer in-memory, but ensure it's consistent with the saved file if needed
  % (No action required; skipping load to avoid overwriting current workspace state)
elseif isfile(power_fd_segments_file) && ~force_recompute
  % Load from cache
  S_cache = load(power_fd_segments_file);
  if isfield(S_cache,'power_fd_segments') && istable(S_cache.power_fd_segments)
    power_fd_segments = S_cache.power_fd_segments;
  else
    % Cache corrupted/incomplete -> recompute
    need_calc = true;
  end
else
  % No cache -> must compute
  need_calc = true;
end

if need_calc
  % ----------------------- Load saved HFD (per-segment) -----------------------
  if ~exist('results','var') || isempty(results)
    if ~exist('results_file','var') || ~isfile(results_file)
      error('results_file not found. Expected at: %s', char(string(results_file)));
    end
    S = load(results_file);
    if ~isfield(S,'results') || isempty(S.results)
      error('No variable "results" inside %s.', results_file);
    end
    results = S.results;
  end

  % Build a lookup: (subj, interval_idx) -> mean HFD over included chans
  segHFD_map   = containers.Map('KeyType','char','ValueType','double');
  segGroup_map = containers.Map('KeyType','char','ValueType','char');
  segCond_map  = containers.Map('KeyType','char','ValueType','char');

  for i = 1:numel(results)
    r = results(i);

    % Keep only step12 HFD results
    if ~isfield(r, 'preprocessing_step') || ~strcmpi(string(r.preprocessing_step), "step12")
        continue;
    end

    if isempty(r.fd) || isempty(r.included_mask) || ~any(r.included_mask)
        continue;
    end

    mHFD = mean(r.fd(r.included_mask), 'omitnan');
    if ~isfinite(mHFD)
        continue;
    end

    k = sprintf('%s_%d', char(string(r.subj_id)), r.interval_idx);

    segHFD_map(k)   = mHFD;
    segGroup_map(k) = char(string(r.group));
    segCond_map(k)  = char(string(r.condition));
 end

  % ----------------------- Ensure EEGLAB and montage -----------------------
  if exist('pop_loadset','file')~=2
    try
      eeglab nogui; close all;
    catch
      error('EEGLAB pop_loadset not found on path.');
    end
  end

  if exist('readlocs','file')==2
    common_chanlocs = readlocs(chanloc_file, 'filetype', 'sfp');
  else
    EEGtmp = eeg_emptyset();
    EEGtmp = pop_chanedit(EEGtmp, 'load',{chanloc_file 'filetype' 'sfp'});
    common_chanlocs = EEGtmp.chanlocs;
  end
  if isempty(common_chanlocs)
    error('Failed to load channel locations from %s', chanloc_file);
  end

  common_labels = arrayfun(@(c) c.labels, common_chanlocs, 'uni', 0);
  nCommon = numel(common_labels);

  label_to_idx = containers.Map('KeyType','char','ValueType','double');
  for i = 1:nCommon
    lab = common_labels{i};
    if ~isempty(lab), label_to_idx(lab) = i; end
  end

  % Exclude ONLY EXG channels
  is_exg_common = startsWith(string(common_labels), "EXG", 'IgnoreCase', true);
  final_exclude_mask = is_exg_common'; % logical

  % ----------------------- Walk segment files; compute per-segment relative power -----------------------
  if exist('dir','var'); clear dir; end % avoid shadowing built-in
  segment_files = builtin('dir', fullfile(trimmed_path, '*step12*_trimmed25.set'));
  if isempty(segment_files)
    error('No *_trimmed25.set files found in %s', trimmed_path);
  end

  SegRows = table(); % Subject | Group | Condition | IntervalIdx | Band | RelPower | HFD

  fprintf('Computing per-segment relative band power and pairing with HFD...\n');
  for f = 1:numel(segment_files)
    try
      fname = segment_files(f).name;
      [~, base] = fileparts(fname);

      % Parse subject id (first 3 digits) and interval index from timepoints
      subj_id = regexp(base, '^\d{3}', 'match', 'once');
      toks    = regexp(base, 'timepoint_(\d+)-timepoint_(\d+)', 'tokens', 'once');
      if isempty(subj_id) || isempty(toks), continue; end

      start_pt = str2double(toks{1});
      if ~isfinite(start_pt), continue; end
      interval_idx = round(start_pt/30) + 1; % 1..12

      % Find HFD for this subject/segment
      k = strcat(subj_id, "_", string(interval_idx));
      if ~isKey(segHFD_map, char(k)), continue; end

      mHFD = segHFD_map(char(k));
      grp  = segGroup_map(char(k));
      cond = segCond_map(char(k));

      % Load EEG for spectral power
      EEG = pop_loadset('filename', fname, 'filepath', trimmed_path);
      if isempty(EEG) || isempty(EEG.data), continue; end
      if isempty(EEG.chanlocs) || all(arrayfun(@(c) ~isfield(c,'X')||isempty(c.X), EEG.chanlocs))
        EEG = pop_chanedit(EEG, 'lookup', chanloc_file);
      end
      fs = EEG.srate;
      if ~isfinite(fs) || fs<=0, continue; end

      % Map file channel labels to common montage
      nCh = size(EEG.data,1);
      file_labels = cell(1,nCh);
      for ch = 1:nCh
        if ch <= numel(EEG.chanlocs) && isfield(EEG.chanlocs(ch),'labels') && ~isempty(EEG.chanlocs(ch).labels)
          file_labels{ch} = EEG.chanlocs(ch).labels;
        else
          file_labels{ch} = sprintf('Ch%03d', ch);
        end
      end

      % Welch params
      win  = max(round(2*fs), 256);
      nover= round(0.5*win);

      % Accumulate channel-wise relative power, then average across channels
      relp_by_band_ch = nan(nCommon, B);

      for ch = 1:nCh
        lab = file_labels{ch};
        if ~isKey(label_to_idx, lab), continue; end
        cidx = label_to_idx(lab);
        if final_exclude_mask(cidx), continue; end

        x = double(EEG.data(ch,:));
        ok = isfinite(x);
        if nnz(ok) < fs, continue; end

        % Simple interpolation for brief NaNs; edge-hold outside valid span
        if ~all(ok)
          t = 1:numel(x); xi = x(ok); ti = t(ok);
          x(~ok) = interp1(ti, xi, t(~ok), 'linear', 'extrap');
          firstIdx = find(ok,1,'first'); lastIdx = find(ok,1,'last');
          if firstIdx>1, x(1:firstIdx-1) = x(firstIdx); end
          if lastIdx < numel(x), x(lastIdx+1:end) = x(lastIdx); end
        end
        if ~any(isfinite(x)) || std(x)==0, continue; end

        x = x - mean(x,'omitnan');
        try
          [Pxx, fvec] = pwelch(x, win, nover, [], fs);
        catch
          continue;
        end
        if ~all(isfinite(Pxx)) || ~all(isfinite(fvec)) || numel(Pxx)~=numel(fvec), continue; end

        % Total power over the union of all band edges
        all_edges   = cell2mat(struct2cell(bands));
        all_edges   = reshape(all_edges, 2, []).';
        total_range = [min(all_edges(:,1)), max(all_edges(:,2))];
        sel_tot = fvec >= total_range(1) & fvec <= total_range(2);
        if nnz(sel_tot) < 2, continue; end
        Ptot = trapz(fvec(sel_tot), Pxx(sel_tot));
        if ~isfinite(Ptot) || Ptot<=0, continue; end

        % Relative power per band
        rp = nan(1,B);
        for bi = 1:B
          fr  = bands.(band_names{bi});
          sel = fvec >= fr(1) & fvec <= fr(2);
          if nnz(sel) >= 2
            bp   = trapz(fvec(sel), Pxx(sel));
            rp(bi)= bp / Ptot;
          end
        end
        relp_by_band_ch(cidx, :) = rp;
      end

      % Channel-average rel power per band (across mapped, non-EXG channels)
      relp_band = squeeze(mean(relp_by_band_ch(~final_exclude_mask, :), 1, 'omitnan'));

      % Append one row per band for this segment
      for bi = 1:B
        if ~isfinite(relp_band(bi)), continue; end
        SegRows = [SegRows; table( ...
          string(subj_id), string(grp), string(cond), interval_idx, ...
          string(band_names{bi}), relp_band(bi), mHFD, ...
          'VariableNames', {'Subject','Group','Condition','IntervalIdx','Band','RelPower','HFD'})]; %#ok<AGROW>
      end

      if mod(f,25)==0
        fprintf(' processed %d/%d files...\n', f, numel(segment_files));
      end
    catch ME
      fprintf('⚠️ Error in %s: %s\n', segment_files(f).name, ME.message);
      continue;
    end
  end

  % Keep a tidy table in workspace and cache to disk
  power_fd_segments = SegRows; % one row per (segment × band)
  try
    save(power_fd_segments_file, 'power_fd_segments', '-v7.3');
    fprintf('Saved: %s\n', power_fd_segments_file);
  catch ME
    warning('Could not save power_fd_segments to disk: %s');
  end
end

%% =============================== PLOTTING PART ===============================
chanloc_file = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/biosemi128.sfp';
trimmed_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/4_Trimmed_files';
excel_file   = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/VIA15_Masterfile_Cleaned.xlsx'; %#ok<NASGU> % (not used here but kept for context)
data_analysis_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/5_Data_analysis_files/';
results_file = fullfile(data_analysis_path, 'complexity_results_all_steps_final.mat');  % contains per-channel results now

% Path to cached calc results
power_fd_segments_file = fullfile(trimmed_path, 'power_fd_segments.mat');

S = load(power_fd_segments_file);
power_fd_segments = S.power_fd_segments;

% ----------------------- Bands & plotting order -----------------------
bands = struct( ...
  'theta', [4 8], ...
  'alpha', [8 13], ...
  'beta',  [13 30], ...
  'gamma', [30 100] );
band_names = {'theta','alpha','beta','gamma'};
B = numel(band_names);

% ----------------------- Colors by group (consistent with earlier) -----------------------
color_map = containers.Map( ...
  {'PBC','FHR_BP','FHR_SZ'}, ...
  {[148 192 28]/255, [140 208 219]/255, [0 175 194]/255} );


% Normalize types
G    = string(power_fd_segments.Group);
C    = string(power_fd_segments.Condition);
BAND = string(power_fd_segments.Band);

% Group ordering for plotting (requested: FHR_SZ, FHR_BP, PBC)
desired_order  = ["FHR_SZ","FHR_BP","PBC"];
present_groups = unique(G, 'stable');
ordered = desired_order(ismember(desired_order, present_groups));  ordered = ordered(:).';
extras  = present_groups(~ismember(present_groups, desired_order)); extras = extras(:).';
disp_groups = [ordered, extras];  % final order for plotting

conds = unique(C, 'stable');

% Visual order and their positions in a 2x2 grid
% Use tiles 1, 2 (top row), and 3, 4 (bottom row)
band_order = {'theta','alpha','beta','gamma'};  % visual order
tile_pos   = [1, 2, 3, 4];                            % positions in tiledlayout(2,2)

% Color for fit & text (dark red)
dark_red = [0.55 0 0];

for ci = 1:numel(conds)
  cond = conds(ci);
  fig = figure('Color','w','Name',sprintf('Segments: HFD vs RelPower — %s', cond), ...
               'Position',[60 60 1900 760]); % wider & taller
  tl = tiledlayout(fig, 2, 2, 'TileSpacing','compact', 'Padding','compact');

  for vi = 1:numel(band_order)
    bname = band_order{vi};
    bi    = find(strcmp(band_names, bname), 1);  % index into the bands struct
    if isempty(bi), continue; end

    ax = nexttile(tl, tile_pos(vi)); hold(ax,'on'); grid(ax,'on'); box(ax,'on');

    % Title with proper lettering and frequency span
    fr = bands.(band_names{bi});
    bandLabel = [upper(bname(1)) bname(2:end)];  % e.g., "Beta"
    title(ax, sprintf('%s (%.1f–%.1f Hz)', bandLabel, fr(1), fr(2)), ...
            'FontSize', 16, 'FontWeight', 'bold');

    % Scatter segments (all groups separately for color), in requested order
    for gi = 1:numel(disp_groups)
      grp  = disp_groups(gi);
      rows = (C==cond) & (BAND==string(bname)) & (G==grp);
      x = power_fd_segments.RelPower(rows);
      y = power_fd_segments.HFD(rows);
      if isempty(x), continue; end

      if isKey(color_map, char(grp)), cc = color_map(char(grp)); else, cc = [0 0 0]; end
      scatter(ax, x, y, 36, 'o', 'MarkerFaceColor', cc, 'MarkerEdgeColor', 'k');
    end

    xlabel(ax, 'Relative power', 'FontSize',14);
    ylabel(ax, 'HFD', 'FontSize',14);
    ax.FontSize = 14;

    % ---- Fit across ALL groups for this band/condition ----
    rows_all = (C==cond) & (BAND==string(bname));
    x_all = power_fd_segments.RelPower(rows_all);
    y_all = power_fd_segments.HFD(rows_all);

    if numel(x_all) > 3
      % Correlation (Spearman), robust to non-linear monotonic trends
      [rho,pval] = corr(x_all, y_all, 'Type','Spearman','Rows','complete');

      % Candidate fits (linear vs quadratic)
      linFit   = fit(x_all(:), y_all(:), 'poly1');
      poly2Fit = fit(x_all(:), y_all(:), 'poly2');

      % AIC computation
      sse_lin = sum((y_all(:) - feval(linFit,   x_all(:))).^2);
      sse_p2  = sum((y_all(:) - feval(poly2Fit, x_all(:))).^2);
      n = numel(y_all);
      AIC_lin = n*log(sse_lin/n) + 2*2; % 2 params (slope, intercept)
      AIC_p2  = n*log(sse_p2/n)  + 2*3; % 3 params (quad, slope, intercept)

      % Selection rule:
      deltaAIC = AIC_p2 - AIC_lin; % positive -> poly1 better; negative -> poly2 better
      if abs(deltaAIC) < 2
        bestFit = linFit; fitType = 'poly1';
      else
        if AIC_p2 < AIC_lin
          bestFit = poly2Fit; fitType = 'poly2';
        else
          bestFit = linFit;   fitType = 'poly1';
        end
      end

      % Plot fit line in dark red
      xx = linspace(min(x_all), max(x_all), 200);
      yy = feval(bestFit, xx);
      plot(ax, xx, yy, '-', 'LineWidth', 2, 'Color', dark_red);

      % Adjust ylim to leave space on top for text
      yl = ylim(ax);
      ylim(ax, [yl(1), yl(2) + 0.04*range(yl)]);

      % ---- Annotations (bold dark red) ----
      % Top-left: rho & p (bold, lowered a bit)
      txtLP = sprintf('\\rho=%.2f, p=%.3f (%s)', rho, pval, fitType);
      text(ax, 0.01, 0.99, txtLP, 'Units','normalized', 'HorizontalAlignment','left', ...
           'VerticalAlignment','top', 'FontSize',16, 'Color',dark_red, 'FontWeight','bold');

      % Top-right: AIC values (bold, lowered a bit)
      txtAIC = sprintf('AIC poly1=%.1f, poly2=%.1f', AIC_lin, AIC_p2);
      text(ax, 0.99, 0.99, txtAIC, 'Units','normalized', 'HorizontalAlignment','right', ...
           'VerticalAlignment','top', 'FontSize',16, 'Color',dark_red, 'FontWeight','bold');
    end
  end

  sgtitle(tl, sprintf('HFD vs Relative Band Power — %s eyes (each dot = segment avg., fit across groups)', cond), ...
          'FontWeight','normal');
end


%% === Helper function ===

function kFD = hfd(X, Kmax)
% Robust Higuchi FD implementation
    N = length(X);
    L = zeros(Kmax,1);
    x = zeros(Kmax,1);

    for k = 1:Kmax
        Lk = zeros(1,k);
        for m = 1:k
            idx = m:k:N;
            n = length(idx);
            if n > 1
                Lmk = sum(abs(diff(X(idx)))) * (N - 1) / (k * n * k);
                Lk(m) = Lmk;
            else
                Lk(m) = NaN;
            end
        end
        L(k) = nanmean(Lk);
        x(k) = log(1/k);
    end

    y = log(L);
    valid = ~isnan(x) & ~isnan(y) & ~isinf(x) & ~isinf(y);
    if sum(valid) < 2
        kFD = NaN;
    else
        p = polyfit(x(valid), y(valid), 1);
        kFD = p(1);
    end
end


%% ================== 7. Subject-level HFD vs Clinical Variables ==================
% Goal:
% Correlate subject-level Higuchi Fractal Dimension (HFD) with:
%   1) CBCL_totsc_cg_v15
%   2) PSP_cg_v15
%
% Separately for:
%   - Open eyes
%   - Closed eyes
%
% This produces 4 plots in total (2 variables × 2 conditions), using:
%   - Same group colors
%   - Same overall formatting style
%   - Same linear-vs-quadratic rule based on AIC
%
% IMPORTANT:
% This code uses SUBJECT-LEVEL mean HFD within each condition.
% That is the statistically cleaner choice because the questionnaire variables
% are subject-level variables, not segment-level variables.
%
% Assumptions about your saved HFD results:
% - Stored in: complexity_results_all_steps_final.mat
% - Variable inside file: results
% - results(i) contains at least:
%       .preprocessing_step
%       .subj_id
%       .group
%       .condition
%       .fd
%       .included_mask
%
% Study IDs in the allkey file may be 2 digits (e.g., 25), but in results they
% are 3 digits (e.g., 025). This code pads IDs automatically to 3 digits.

clearvars -except results
close all
clc

% ----------------------- Paths -----------------------
inFile = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/0_Helper_files/VIA15_allkey_291124_88participants.xlsx';
data_analysis_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/5_Data_analysis_files/';
results_file = fullfile(data_analysis_path, 'complexity_results_all_steps_final.mat');

outDir = fullfile(data_analysis_path, 'HFD_vs_clinical_variables');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

% ----------------------- Load results -----------------------
if ~exist('results','var') || isempty(results)
    if ~isfile(results_file)
        error('results_file not found: %s', results_file);
    end
    S = load(results_file);
    if ~isfield(S,'results') || isempty(S.results)
        error('No variable "results" found in %s', results_file);
    end
    results = S.results;
end

% ----------------------- Read clinical file -----------------------
if ~isfile(inFile)
    error('Clinical Excel file not found: %s', inFile);
end

Tclin = readtable(inFile);

requiredCols = {'famlbnr','CBCL_totsc_cg_v15','PSP_cg_v15'};
missingCols = requiredCols(~ismember(requiredCols, Tclin.Properties.VariableNames));
if ~isempty(missingCols)
    error('Missing required columns in clinical file: %s', strjoin(missingCols, ', '));
end

% Force clinical variables to numeric in case Excel imported them as cell/string
vars_to_numeric = {'CBCL_totsc_cg_v15','PSP_cg_v15'};

for k = 1:numel(vars_to_numeric)
    vn = vars_to_numeric{k};

    if iscell(Tclin.(vn))
        tmp = nan(height(Tclin),1);
        for ii = 1:height(Tclin)
            val = Tclin.(vn){ii};
            if isempty(val)
                tmp(ii) = NaN;
            elseif isnumeric(val)
                tmp(ii) = val(1);
            else
                tmp(ii) = str2double(string(val));
            end
        end
        Tclin.(vn) = tmp;

    elseif isstring(Tclin.(vn))
        Tclin.(vn) = str2double(Tclin.(vn));

    elseif ischar(Tclin.(vn))
        Tclin.(vn) = str2double(cellstr(Tclin.(vn)));

    elseif ~isnumeric(Tclin.(vn))
        error('Column %s could not be converted to numeric.', vn);
    end
end

% Convert study ID to padded 3-digit string
Tclin.Subject = pad_subject_ids(Tclin.famlbnr);

% Keep only needed columns
Tclin = Tclin(:, {'Subject','CBCL_totsc_cg_v15','PSP_cg_v15'});

% ----------------------- Colors by group -----------------------
color_map = containers.Map( ...
    {'PBC','FHR_BP','FHR_SZ'}, ...
    {[148 192 28]/255, [140 208 219]/255, [0 175 194]/255} );

% Requested group order
desired_order = ["FHR_SZ","FHR_BP","PBC"];

% Fit/text color
dark_red = [0.55 0 0];

% ----------------------- Build subject-level HFD table -----------------------
% We compute mean HFD across included channels for each segment,
% then average across all valid segments within each subject and condition.

rows = {};

for i = 1:numel(results)
    r = results(i);

    % Keep only step12 HFD results
    if ~isfield(r,'preprocessing_step') || ~strcmpi(string(r.preprocessing_step), "step12")
        continue;
    end

    % Must have HFD and included channels
    if ~isfield(r,'fd') || isempty(r.fd) || ~isfield(r,'included_mask') || isempty(r.included_mask)
        continue;
    end
    if ~any(r.included_mask)
        continue;
    end

    % Need subject, group, condition
    if ~isfield(r,'subj_id') || ~isfield(r,'group') || ~isfield(r,'condition')
        continue;
    end

    subj = pad_subject_ids(r.subj_id);
    grp  = string(r.group);
    cond = normalize_condition_label(string(r.condition));

    % Mean HFD over included channels for this segment
    segHFD = mean(r.fd(r.included_mask), 'omitnan');
    if ~isfinite(segHFD)
        continue;
    end

    rows(end+1, :) = {subj, grp, cond, segHFD}; %#ok<SAGROW>
end

if isempty(rows)
    error('No valid HFD rows were extracted from results.');
end

Thfd_seg = cell2table(rows, 'VariableNames', {'Subject','Group','Condition','SegmentHFD'});

% Subject-level mean HFD within condition
Thfd_subj = groupsummary(Thfd_seg, {'Subject','Group','Condition'}, 'mean', 'SegmentHFD');
Thfd_subj.Properties.VariableNames{'mean_SegmentHFD'} = 'HFD';

% ----------------------- Merge with clinical data -----------------------
Tplot = innerjoin(Thfd_subj, Tclin, 'Keys', 'Subject');

if isempty(Tplot)
    error('No overlap found between HFD subjects and clinical subjects after ID padding.');
end

% Normalize types
Tplot.Subject   = string(Tplot.Subject);
Tplot.Group     = string(Tplot.Group);
Tplot.Condition = string(Tplot.Condition);

% Present groups in requested order, extras after
present_groups = unique(Tplot.Group, 'stable');
ordered = desired_order(ismember(desired_order, present_groups));  
ordered = ordered(:).';
extras  = present_groups(~ismember(present_groups, desired_order)); 
extras  = extras(:).';
disp_groups = [ordered, extras];

% ----------------------- Variables to test -----------------------
clinical_vars = { ...
    'CBCL_totsc_cg_v15', ...
    'PSP_cg_v15'};

clinical_labels = containers.Map( ...
    {'CBCL_totsc_cg_v15','PSP_cg_v15'}, ...
    {'CBCL total score','PSP'} );

% Prefer this condition order if present
cond_order_preferred = ["open","closed"];
present_conds = unique(Tplot.Condition, 'stable');
ordered_conds = cond_order_preferred(ismember(cond_order_preferred, present_conds));
extra_conds   = present_conds(~ismember(cond_order_preferred, present_conds));
conds = [ordered_conds(:).' extra_conds(:).'];

% ----------------------- Plotting & saving -----------------------
fprintf('Creating subject-level HFD vs clinical variable plots...\n');

for ci = 1:numel(conds)
    cond = conds(ci);

    for vi = 1:numel(clinical_vars)
        vname  = clinical_vars{vi};
        vlabel = clinical_labels(vname);

        rows_cond = Tplot.Condition == cond;

        x_all = Tplot.(vname)(rows_cond);
        y_all = Tplot.HFD(rows_cond);
        g_all = Tplot.Group(rows_cond);
        subj_all = Tplot.Subject(rows_cond);

        valid = isfinite(x_all) & isfinite(y_all);
        x_all = x_all(valid);
        y_all = y_all(valid);
        g_all = g_all(valid);
        subj_all = subj_all(valid);

        % Skip empty plots
        if isempty(x_all)
            fprintf('No valid data for %s | %s\n', char(cond), vname);
            continue;
        end

        n_participants = numel(unique(subj_all));
        fprintf('Participants in plot [%s | %s]: %d\n', char(cond), vname, n_participants);

        fig = figure('Color','w', ...
            'Name', sprintf('HFD vs %s — %s eyes', vlabel, char(cond)), ...
            'Position', [100 100 1100 850]);

        ax = axes(fig); 
        hold(ax,'on'); 
        grid(ax,'on'); 
        box(ax,'on');

        % Store legend handles
        legend_handles = gobjects(0);
        legend_labels  = {};

        % Scatter by group
        for gi = 1:numel(disp_groups)
            grp = disp_groups(gi);
            idx = g_all == grp;
            if ~any(idx), continue; end

            if isKey(color_map, char(grp))
                cc = color_map(char(grp));
            else
                cc = [0 0 0];
            end

            h_scatter = scatter(ax, x_all(idx), y_all(idx), 55, 'o', ...
                'MarkerFaceColor', cc, ...
                'MarkerEdgeColor', 'k', ...
                'LineWidth', 0.8);

            legend_handles(end+1) = h_scatter; %#ok<SAGROW>
            legend_labels{end+1} = char(grp); %#ok<SAGROW>
        end

        xlabel(ax, vlabel, 'FontSize', 16);
        ylabel(ax, 'Mean HFD', 'FontSize', 16);
        ax.FontSize = 15;

        % ---- Fit across ALL groups with same AIC rule ----
        fit_handle = gobjects(0);
        fitType = '';

        if numel(x_all) > 3 && numel(unique(x_all)) > 1
            % Spearman correlation
            [rho,pval] = corr(x_all, y_all, 'Type', 'Spearman', 'Rows', 'complete');

            % Linear fit
            p1 = polyfit(x_all, y_all, 1);
            yhat1 = polyval(p1, x_all);
            sse_lin = sum((y_all - yhat1).^2, 'omitnan');

            % Quadratic fit
            p2 = polyfit(x_all, y_all, 2);
            yhat2 = polyval(p2, x_all);
            sse_p2 = sum((y_all - yhat2).^2, 'omitnan');

            n = numel(y_all);

            % Guard against log(0)
            sse_lin = max(sse_lin, eps);
            sse_p2  = max(sse_p2,  eps);

            AIC_lin = n*log(sse_lin/n) + 2*2; % intercept + slope
            AIC_p2  = n*log(sse_p2/n)  + 2*3; % quadratic + slope + intercept

            deltaAIC = AIC_p2 - AIC_lin; % positive -> poly1 better, negative -> poly2 better

            if abs(deltaAIC) < 2
                fitType = 'poly1';
            else
                if AIC_p2 < AIC_lin
                    fitType = 'poly2';
                else
                    fitType = 'poly1';
                end
            end

            xx = linspace(min(x_all), max(x_all), 200);
            if strcmp(fitType, 'poly2')
                yy = polyval(p2, xx);
            else
                yy = polyval(p1, xx);
            end

            fit_handle = plot(ax, xx, yy, '-', 'LineWidth', 2.5, 'Color', dark_red);

            % Add fit line to legend
            legend_handles(end+1) = fit_handle; %#ok<SAGROW>
            legend_labels{end+1} = sprintf('Fit (%s)', fitType); %#ok<SAGROW>

            % Add space on top
            yl = ylim(ax);
            if range(yl) > 0
                ylim(ax, [yl(1), yl(2) + 0.10*range(yl)]);
            end

            % Top-left annotation
            txtLP = sprintf('\\rho = %.2f, p = %.3f (%s)', rho, pval, fitType);
            text(ax, 0.01, 0.99, txtLP, ...
                'Units', 'normalized', ...
                'HorizontalAlignment', 'left', ...
                'VerticalAlignment', 'top', ...
                'FontSize', 15, ...
                'Color', dark_red, ...
                'FontWeight', 'bold');

            % Top-right annotation
            txtAIC = sprintf('AIC poly1 = %.1f, poly2 = %.1f', AIC_lin, AIC_p2);
            text(ax, 0.99, 0.99, txtAIC, ...
                'Units', 'normalized', ...
                'HorizontalAlignment', 'right', ...
                'VerticalAlignment', 'top', ...
                'FontSize', 15, ...
                'Color', dark_red, ...
                'FontWeight', 'bold');
        else
            text(ax, 0.5, 0.95, 'Too few valid points for fit/correlation', ...
                'Units', 'normalized', ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'top', ...
                'FontSize', 14, ...
                'Color', dark_red, ...
                'FontWeight', 'bold');
        end

        % Create legend in top-right below the existing text
        if ~isempty(legend_handles)
            lgd = legend(ax, legend_handles, legend_labels, ...
                'Location', 'none', ...
                'FontSize', 13, ...
                'Box', 'on', ...
                'Interpreter', 'none');

            % [left bottom width height] in normalized figure/axes units
            % Manually placed to sit below the top-right AIC text
            lgd.Units = 'normalized';
            lgd.Position = [0.73 0.67 0.20 0.16];
        end

        sgtitle(sprintf('Subject-level mean HFD vs %s — %s eyes', vlabel, char(cond)), ...
            'FontWeight', 'normal', 'FontSize', 18);

        % Save
        safeCond = regexprep(char(cond), '\s+', '_');
        outBase = fullfile(outDir, sprintf('HFD_vs_%s_%sEyes', vname, safeCond));

        exportgraphics(fig, [outBase '.png'], 'Resolution', 300);
        savefig(fig, [outBase '.fig']);

        fprintf('Saved: %s.png\n', outBase);
    end
end

fprintf('Done. Plots saved in:\n%s\n', outDir);

%% ================== Helper functions ==================

function subj = pad_subject_ids(x)
% Convert numeric/string/cell IDs to zero-padded 3-digit subject IDs

    % Case 1: numeric vector directly from table
    if isnumeric(x)
        subj = strings(numel(x),1);
        for ii = 1:numel(x)
            if isnan(x(ii))
                subj(ii) = "";
            else
                subj(ii) = sprintf('%03d', round(x(ii)));
            end
        end
        return
    end

    % Convert input to cell array for uniform handling
    if isstring(x)
        tmp = cellstr(x);
    elseif ischar(x)
        tmp = cellstr(x);
    elseif iscell(x)
        tmp = x;
    else
        error('Unsupported subject ID format.');
    end

    subj = strings(numel(tmp),1);

    for ii = 1:numel(tmp)
        val = tmp{ii};

        % Empty
        if isempty(val)
            subj(ii) = "";
            continue;
        end

        % Numeric scalar
        if isnumeric(val)
            if any(isnan(val))
                subj(ii) = "";
            else
                subj(ii) = sprintf('%03d', round(val(1)));
            end
            continue;
        end

        % Text-like
        s = strtrim(char(string(val)));

        if strlength(string(s)) == 0 || ismissing(string(s))
            subj(ii) = "";
            continue;
        end

        numval = str2double(s);
        if isfinite(numval)
            subj(ii) = sprintf('%03d', round(numval));
        else
            digitsOnly = regexp(s, '\d+', 'match', 'once');
            if isempty(digitsOnly)
                subj(ii) = "";
            else
                subj(ii) = sprintf('%03d', str2double(digitsOnly));
            end
        end
    end
end

function cond = normalize_condition_label(cond_in)
% Normalize condition labels to "open" / "closed" when possible

    c = lower(strtrim(char(cond_in)));

    if contains(c, 'open')
        cond = "open";
    elseif contains(c, 'closed')
        cond = "closed";
    else
        cond = string(c); % fallback, keep original label
    end
end
