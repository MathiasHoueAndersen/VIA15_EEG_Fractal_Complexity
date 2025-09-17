% Segment resting-state EEG .set files using timepoints from Excel file

%% Paths
preprocessed_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/Preprocessed_data';
excel_file = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/VIA15_Masterfile_with_age.xlsx';
segment_output_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/Batch_ASR_Pruned_5_SD';
if ~exist(segment_output_path, 'dir'), mkdir(segment_output_path); end

%% Load Excel file
T = readtable(excel_file);
tp_names = T.Properties.VariableNames(6:end); % timepoint_0, timepoint_30, ..., timepoint_360
segment_count = containers.Map(); % Count how many segments per timepoint pair

%% Launch EEGLAB
[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;

%% Loop over subjects
for i = 1:height(T)
    subj_id = sprintf('%03d', T.id(i));
    eeg_file = fullfile(preprocessed_path, [subj_id '_psdpruned.set']);

    if ~isfile(eeg_file)
        fprintf('❌ Skipping subject %s (missing EEG file)\n', subj_id);
        continue;
    end

    % Load preprocessed EEG
    EEG = pop_loadset('filename', [subj_id '_psdpruned.set'], 'filepath', preprocessed_path);
    fprintf('\n--- Processing subject %s ---\n', subj_id);
    total_duration_sec = EEG.pnts / EEG.srate;
    fprintf('📏 Total EEG duration: %.2f seconds (%d points)\n', total_duration_sec, EEG.pnts);

    %% Loop through consecutive timepoint pairs
    for j = 1:(length(tp_names) - 1)
        t1_label = tp_names{j};
        t2_label = tp_names{j + 1};

        % Extract timepoints from Excel
        t1 = T{i, t1_label};
        t2 = T{i, t2_label};
        if iscell(t1), t1 = t1{1}; end
        if iscell(t2), t2 = t2{1}; end

        % Validate timepoints
        if isempty(t1) || isempty(t2) || ~isnumeric(t1) || ~isnumeric(t2) || isnan(t1) || isnan(t2)
            continue;
        end
        if t2 <= t1
            fprintf('⚠️ Skipping %s–%s for subject %s (non-increasing: %.2f ≥ %.2f)\n', ...
                t1_label, t2_label, subj_id, t1, t2);
            continue;
        end

        % Convert to sample indices
        start_sample = round(t1 * EEG.srate);
        end_sample = round(t2 * EEG.srate);

        % Clamp end_sample to EEG length if it exceeds it
        if end_sample > EEG.pnts
            fprintf('⚠️ Clamping %s–%s for subject %s: segment end %.2fs > EEG duration %.2fs, truncating to fit.\n', ...
                t1_label, t2_label, subj_id, t2, total_duration_sec);
        end_sample = EEG.pnts; % Use last available sample
        end
        
        %% Extract and save segment
        EEG_seg = pop_select(EEG, 'point', [start_sample end_sample]);
        seg_filename = sprintf('%s_segment_%s-%s.set', subj_id, t1_label, t2_label);
        EEG_seg.setname = seg_filename;
        pop_saveset(EEG_seg, 'filename', seg_filename, 'filepath', segment_output_path);
        fprintf('✅ Saved segment: %s\n', seg_filename);

        %% Count the segment
        seg_key = sprintf('%s–%s', t1_label, t2_label);
        if isKey(segment_count, seg_key)
            segment_count(seg_key) = segment_count(seg_key) + 1;
        else
            segment_count(seg_key) = 1;
        end
    end
end

%% Segment count summary (by segment index × group)
fprintf('\n📊 Segment count summary (by segment × group):\n');

% ---- Find the 12 timepoint columns robustly and in order ----
vn = T.Properties.VariableNames;
tp_mask = ~cellfun('isempty', regexp(vn, '^timepoint_\d+$', 'once'));
tp_names_all = vn(tp_mask);
% sort by the numeric suffix to ensure correct order
tp_nums = cellfun(@(s) sscanf(s, 'timepoint_%d'), tp_names_all);
[tp_nums, order_tp] = sort(tp_nums);
tp_names_ord = tp_names_all(order_tp);
num_segments = numel(tp_names_ord) - 1;   % typically 12
if num_segments <= 0
    error('Could not detect timepoint_* columns properly in the Excel sheet.');
end

% ---- Detect the group column in the Excel table ----
group_var = '';
if any(strcmpi(vn, 'fhr_group'))
    group_var = vn{strcmpi(vn, 'fhr_group')};
elseif any(strcmpi(vn, 'group'))
    group_var = vn{strcmpi(vn, 'group')};
else
    error('Could not find a group column (expected ''fhr_group'' or ''group'') in the Excel file.');
end

% ---- Robust group normalizer -> PBC / FHR_BP / FHR_SZ ----
normalize_group = @(s) ( ...
    (contains(upper(string(s)), "PBC")) * "PBC" + ...
    (~contains(upper(string(s)), "PBC") & contains(upper(string(s)), "FHR") & ...
     (contains(upper(string(s)), "BP") | contains(upper(string(s)), "BIP"))) * "FHR_BP" + ...
    (~contains(upper(string(s)), "PBC") & contains(upper(string(s)), "FHR") & ...
     (contains(upper(string(s)), "SZ") | contains(upper(string(s)), "SCH"))) * "FHR_SZ" + ...
    (~contains(upper(string(s)), "PBC") & ~contains(upper(string(s)), "FHR")) * upper(string(s)) ...
);

group_names = ["PBC","FHR_BP","FHR_SZ"];
counts = zeros(numel(group_names), num_segments);

% ---- Build subject -> group map (3-digit keys like '101') ----
gvals_raw = T.(group_var);
if iscell(gvals_raw), gvals_raw = string(gvals_raw); end
if iscategorical(gvals_raw), gvals_raw = string(gvals_raw); end
gmap = containers.Map('KeyType','char','ValueType','char');
for r = 1:height(T)
    key = sprintf('%03d', T.id(r));
    gcanon = normalize_group(gvals_raw(r));
    if any(group_names == gcanon)
        gmap(key) = char(gcanon);
    end
end

% ---- Scan untrimmed segment files and count per segment × group ----
seg_files = dir(fullfile(segment_output_path, '*_segment_*.set'));
for f = 1:numel(seg_files)
    base = seg_files(f).name;
    [~, base] = fileparts(base);                    % e.g., 101_segment_timepoint_0-timepoint_30
    parts = strsplit(base, '_segment_');
    if numel(parts) ~= 2, continue; end
    subj_id  = parts{1};
    tp_pair  = parts{2};
    pair_parts = strsplit(tp_pair, '-');
    if numel(pair_parts) < 2, continue; end
    t1_label = pair_parts{1};                       % e.g., timepoint_0

    % segment index from ordered timepoint list
    k = find(strcmp(tp_names_ord, t1_label), 1, 'first');
    if isempty(k) || k > num_segments, continue; end

    % look up subject's group
    if ~isKey(gmap, subj_id), continue; end
    gcanon = string(gmap(subj_id));
    gi = find(group_names == gcanon, 1, 'first');
    if isempty(gi), continue; end

    counts(gi, k) = counts(gi, k) + 1;
end

% ---- Pretty print ----
for k = 1:num_segments
    fprintf('  seg%02d: ', k);
    for gi = 1:numel(group_names)
        fprintf('%s=%d', group_names(gi), counts(gi, k));
        if gi < numel(group_names), fprintf(', '); end
    end
    fprintf('\n');
end


%% TRIMMING SEGMENTS 
% Cutting first and last second of each epoch and keeping only the first
% 25 seconds of the remaining segment. Discard segments < 25 sec.

segment_output_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/Batch_ASR_Pruned_5_SD';
trimmed_output_path = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/Batch_ASR_Pruned_5_SD_Trim';
if ~exist(trimmed_output_path, 'dir'), mkdir(trimmed_output_path); end

% Reset counter for trimmed segments
trimmed_segment_count = containers.Map();

% Loop through original saved segments
segment_files = dir(fullfile(segment_output_path, '*_segment_*.set'));

for f = 1:length(segment_files)
    seg_file = segment_files(f).name;
    [~, name, ~] = fileparts(seg_file);

    % Extract subject ID and timepoint labels from filename
    parts = strsplit(name, '_segment_');
    subj_id = parts{1};
    timepoints = strrep(parts{2}, '.set', '');
    seg_key = strrep(timepoints, '_', '–'); % e.g., timepoint_0–timepoint_30

    % Load segment
    EEG = pop_loadset('filename', seg_file, 'filepath', segment_output_path);

    % Calculate trimming in samples
    trim_sec = 1; % seconds to remove from start and end
    trim_samples = round(trim_sec * EEG.srate);
    new_start = 1 + trim_samples;
    new_end = EEG.pnts - trim_samples;

    % Check if enough data remains after trimming
    trimmed_duration = (new_end - new_start + 1) / EEG.srate;
    if trimmed_duration < 25
        fprintf('⏩ Skipping %s: trimmed duration %.2fs < 25s\n', seg_file, trimmed_duration);
        continue;
    end

    % Trim segment
    EEG_trimmed = pop_select(EEG, 'point', [new_start new_end]);

    % Take first 25 seconds only
    max_25_samples = round(25 * EEG_trimmed.srate);
    if EEG_trimmed.pnts > max_25_samples
        EEG_trimmed = pop_select(EEG_trimmed, 'point', [1 max_25_samples]);
    end

    % Save trimmed 25-second segment
    trimmed_filename = [name '_trimmed25.set'];
    EEG_trimmed.setname = trimmed_filename;
    pop_saveset(EEG_trimmed, 'filename', trimmed_filename, 'filepath', trimmed_output_path);
    fprintf('✅ Saved 25s segment: %s\n', trimmed_filename);

    % Count valid segments per timepoint pair
    if isKey(trimmed_segment_count, seg_key)
        trimmed_segment_count(seg_key) = trimmed_segment_count(seg_key) + 1;
    else
        trimmed_segment_count(seg_key) = 1;
    end
end

%% Trimmed Segment Count Summary (by segment index × group)
fprintf('\n📊 25-Second Trimmed Segment Count Summary (by segment × group):\n');

group_names = ["PBC","FHR_BP","FHR_SZ"];
num_segments = numel(tp_names) - 1;   % typically 12
counts_trim = zeros(numel(group_names), num_segments);

% Reuse the subject->group map (gmap) built above. If not in scope, rebuild it:
if ~exist('gmap','var') || ~isa(gmap, 'containers.Map')
    vn = T.Properties.VariableNames;
    if any(strcmpi(vn, 'fhr_group'))
        group_var = vn{strcmpi(vn, 'fhr_group')};
    elseif any(strcmpi(vn, 'group'))
        group_var = vn{strcmpi(vn, 'group')};
    else
        error('Could not find a group column (expected ''fhr_group'' or ''group'') in the Excel file.');
    end
    ids = string(T.id);
    gvals_raw = T.(group_var);
    if iscell(gvals_raw), gvals_raw = string(gvals_raw); end
    if iscategorical(gvals_raw), gvals_raw = string(gvals_raw); end
    canon = @(s) string(upper(strrep(strrep(strtrim(string(s)), ' ', ''), '-', '_')));
    gmap = containers.Map('KeyType','char','ValueType','char');
    for r = 1:height(T)
        gmap(sprintf('%03d', T.id(r))) = char(canon(gvals_raw(r)));
    end
end

% Scan trimmed 25s segments
trim_files = dir(fullfile(trimmed_output_path, '*_segment_*_trimmed25.set'));
for f = 1:numel(trim_files)
    name = trim_files(f).name;
    [~, base] = fileparts(name);                         % e.g., 101_segment_timepoint_0-timepoint_30_trimmed25
    parts = strsplit(base, '_segment_');
    if numel(parts) ~= 2, continue; end
    subj_id = parts{1};
    tp_and_suffix = parts{2};
    % remove trailing "_trimmed25" if present
    if endsWith(tp_and_suffix, '_trimmed25')
        tp_and_suffix = extractBefore(tp_and_suffix, strlength(tp_and_suffix) - strlength('_trimmed25') + 1);
    end
    pair_parts = strsplit(tp_and_suffix, '-');
    if numel(pair_parts) < 2, continue; end
    t1_label = pair_parts{1};

    % segment index from t1_label
    k = find(strcmp(tp_names, t1_label), 1, 'first');
    if isempty(k) || k > num_segments, continue; end

    % subject’s group
    if ~isKey(gmap, subj_id), continue; end
    gcanon = string(gmap(subj_id));
    gi = find(group_names == gcanon, 1, 'first');
    if isempty(gi), continue; end

    counts_trim(gi, k) = counts_trim(gi, k) + 1;
end

% Pretty print
for k = 1:num_segments
    fprintf('  seg%02d: ', k);
    for gi = 1:numel(group_names)
        fprintf('%s=%d', group_names(gi), counts_trim(gi, k));
        if gi < numel(group_names), fprintf(', '); end
    end
    fprintf('\n');
end
