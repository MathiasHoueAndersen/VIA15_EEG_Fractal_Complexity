%% Set current directory and initialize EEGLAB
cd('/mnt/projects/VIA_MHA/VIA15_Rest/EEG')
eeglab

%% Paths and file list
data_path = '/mnt/projects/VIA_MHA/VIA15_Rest/nobackup/Data_Rest/';
output_path = fullfile('/mnt/projects/VIA_MHA/VIA15_Rest/Final/Visualization_of_conditions/');
fig_path = fullfile(output_path, 'Figures');
if ~exist(output_path, 'dir'), mkdir(output_path); end
if ~exist(fig_path, 'dir'), mkdir(fig_path); end

bdf_files = dir(fullfile(data_path, '*_Rest.bdf'));
if isempty(bdf_files)
    error('No .bdf files found in %s.', data_path);
end

masterfile = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/VIA15_Masterfile_with_age.xlsx';
[~,~,raw] = xlsread(masterfile);
headers = raw(1, :);
id_col = strcmp(headers, 'id');
timepoint_cols = startsWith(headers, 'timepoint_');

%% Loop over all subjects
for i = 1:length(bdf_files)
    filename = bdf_files(i).name;
    subj_id = erase(filename, '_Rest.bdf');
    fprintf('\n--- Processing %s (%d of %d) ---\n', subj_id, i, length(bdf_files));

    %% Step 1: Load raw EEG data
    EEG = pop_biosig(fullfile(data_path, filename));
    EEG.setname = subj_id;
    fprintf('Step 1: Raw Data Loaded\n');

    %% Step 2: Load subject timepoints from master file
    subj_num = str2double(subj_id);
    row_idx = find([raw{2:end, id_col}] == subj_num) + 1; % offset for header row

    if isempty(row_idx)
        warning('Subject %s not found in masterfile.', subj_id);
        time_sec = nan(1, sum(timepoint_cols));
    else
        timepoints = raw(row_idx, timepoint_cols);
        time_sec = cellfun(@(x) double(x), timepoints);
    end

    %% Step 3: Identify consecutive valid timepoints and create intervals for shading
    valid_idx = find(~isnan(time_sec));
    valid_times = time_sec(valid_idx);

    all_times = [];
    for j = 1:length(valid_idx)-1
        if valid_idx(j+1) == valid_idx(j) + 1  % only consecutive columns
            all_times = [all_times; valid_times(j), valid_times(j+1)];
        end
    end

    % Ensure interval starting at 0 if missing
    if isempty(all_times) || all_times(1,1) > 0
        tp0_idx = find(strcmp(headers, 'timepoint_0'));
        if ~isempty(tp0_idx)
            tp0_value = raw{row_idx, tp0_idx};
            if ~isnan(tp0_value)
                first_valid = valid_times(1);
                if first_valid > 0
                    all_times = [[tp0_value, first_valid]; all_times];
                end
            end
        end
    end

    n_intervals = size(all_times,1);
    if n_intervals < 1
        warning('No valid consecutive timepoints for %s. Using full recording interval.', subj_id);
        all_times = [0 EEG.xmax];
        n_intervals = 1;
        cond_labels = {'Full recording'};
        cond_colors = [0.8 0.8 0.8]; % light gray
    else
        cond_labels = cell(1, n_intervals);
        cond_colors = zeros(n_intervals, 3);
        for k = 1:n_intervals
            if mod(k, 2) == 1
                cond_labels{k} = sprintf('Open Eyes %d', ceil(k/2));
                cond_colors(k,:) = [0.4 0.6 1]; % blue
            else
                cond_labels{k} = sprintf('Closed Eyes %d', k/2);
                cond_colors(k,:) = [1 1 0.4]; % yellow
            end
        end
    end

    %% Step 4: Extract channel data and plot with shaded intervals
    ch_labels = {'EXG6', 'EXG7', 'C16', 'C29'}; % 2 EOG channels and the 2 EEG channels closest to each eye
    ch_data = cell(1,4);
    for c = 1:4
        ch_idx = find(strcmpi({EEG.chanlocs.labels}, ch_labels{c}));
        if isempty(ch_idx)
            warning('Channel %s not found for %s', ch_labels{c}, subj_id);
            ch_data{c} = nan(1, EEG.pnts);
        else
            ch_data{c} = EEG.data(ch_idx, :);
        end
    end

    time = (0:EEG.pnts - 1) / EEG.srate;

    fig = figure('Name', ['Condition Plot - ' subj_id], ...
                 'Position', [100, 100, 1400, 900], ...
                 'Visible', 'off');

    for c = 1:4
        subplot(4,1,c)
        plot(time, ch_data{c}, 'k'); hold on;

        ylims = ylim;

        % Shade intervals from all_times only if inside EEG time range
        for k = 1:n_intervals
            x1 = all_times(k, 1);
            x2 = all_times(k, 2);

            if x2 < time(1) || x1 > time(end)
                continue;
            end

            shade_x1 = max(x1, time(1));
            shade_x2 = min(x2, time(end));

            fill([shade_x1 shade_x2 shade_x2 shade_x1], ...
                 [ylims(1) ylims(1) ylims(2) ylims(2)], ...
                 cond_colors(k,:), 'FaceAlpha', 0.3, 'EdgeColor', 'none');
        end

        title(sprintf('%s - %s', subj_id, ch_labels{c}));
        xlabel('Time (s)');
        ylabel('Amplitude (µV)');
        grid on;
    end

    % Save figure
    fig_file = fullfile(fig_path, [subj_id '_ConditionPlot.png']);
    saveas(fig, fig_file);
    close(fig);
    fprintf('Saved figure for %s to %s\n', subj_id, fig_file);

end
