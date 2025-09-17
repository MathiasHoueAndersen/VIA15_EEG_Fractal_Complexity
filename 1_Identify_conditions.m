%% Set current directory

cd('/mnt/projects/VIA_MHA/VIA15_Rest/Final')
eeglab

%% Loop of preprocessing steps

% Initialize EEGLAB
[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;

% Set paths
data_path = '/mnt/projects/VIA_MHA/VIA15_Rest/nobackup/Data_Rest/';
output_path = fullfile('/mnt/projects/VIA_MHA/VIA15_Rest/Final');
fig_path = fullfile(output_path, 'Figures');
if ~exist(output_path, 'dir'), mkdir(output_path); end
if ~exist(fig_path, 'dir'), mkdir(fig_path); end

% Get all BDF files
bdf_files = dir(fullfile(data_path, '*_Rest.bdf'));

if isempty(bdf_files)
    error('No .bdf files found in %s. Check the path and filename pattern.', raw_data_path);
end

%% Loop over all subjects
for i = 1:length(bdf_files)
    filename = bdf_files(i).name;
    subj_id = erase(filename, '_Rest.bdf');
    fprintf('\n--- Processing %s (%d of %d) ---\n', subj_id, i, length(bdf_files));
    
    %% Step 1: Load data 
    % Load raw EEG data from BioSemi .bdf format using BIOSIG.
    EEG = pop_biosig(fullfile(data_path, filename));
    EEG.setname = subj_id;
    fprintf('Step 1: Raw Data Loaded\n');
    % Quality Check: Check for flat lines (dead channels), extreme drifts, or noise.
    pop_eegplot(EEG, 1, 1, 0); title('Raw Data');
    disp('Examine the plot and look for any artifacts or issues in the raw data');
    pause;

    %% Step 1.1: Detect large deviations in EXG6 and EXG7 (> 2 SD)
    exg6_idx = find(strcmpi({EEG.chanlocs.labels}, 'EXG6'));
    exg7_idx = find(strcmpi({EEG.chanlocs.labels}, 'EXG7'));

    if isempty(exg6_idx) || isempty(exg7_idx)
        warning('EXG6 or EXG7 not found. Skipping EXG inspection.');
    else
        exg6 = EEG.data(exg6_idx, :);
        exg7 = EEG.data(exg7_idx, :);

        % Compute z-scores
        z_exg6 = (exg6 - mean(exg6)) / std(exg6);
        z_exg7 = (exg7 - mean(exg7)) / std(exg7);

        % Logical indices of timepoints with large activity (> 2 SD)
        high_z_exg6 = abs(z_exg6) > 2;
        high_z_exg7 = abs(z_exg7) > 2;

        % Create time vector
        time = (0:EEG.pnts-1) / EEG.srate;

        % Plot both channels
        figure('Name', ['EXG6/EXG7 Activity > 2SD - ' subj_id], 'NumberTitle', 'off');
        subplot(2,1,1)
        plot(time, z_exg6, 'b'); hold on;
        plot(time(high_z_exg6), z_exg6(high_z_exg6), 'ro');
        yline(2, 'r--'); yline(-2, 'r--');
        title('EXG6 (under right eye) z-scored'); ylabel('Z-score'); xlabel('Time (s)');
        legend('EXG6', '>2 SD'); grid on;

        subplot(2,1,2)
        plot(time, z_exg7, 'k'); hold on;
        plot(time(high_z_exg7), z_exg7(high_z_exg7), 'mo');
        yline(2, 'r--'); yline(-2, 'r--');
        title('EXG7 (above right eye) z-scored'); ylabel('Z-score'); xlabel('Time (s)');
        legend('EXG7', '>2 SD'); grid on;

        fprintf('Step 1.1: Highlighted high EXG6 and EXG7 activity (> 2 SD)\n');
        pause;
    end

    %% Step 1.2: Interactive: Mark points of changes in condition by opposite tendencies in EXG6 and EXG7, and display raw C16/C29
    data_dir = '/mnt/projects/VIA_MHA/VIA15_Rest/nobackup/Data_Rest/';
    output_dir = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/';

    % Loop over all subjects
    for i = 1:length(subject_numbers)
        subj_num = subject_numbers(i);
        subj_id = sprintf('%03d', subj_num);
        bdf_file = fullfile(data_dir, [subj_id '_Rest.bdf']);
    
        if ~isfile(bdf_file)
            warning('File not found for subject %s: %s', subj_id, bdf_file);
            continue;
        end
    
        fprintf('\n=== Processing %s ===\n', subj_id);
        
        EEG = pop_biosig(bdf_file);
        EEG.setname = subj_id;
    
        % Get indices
        exg6_idx = find(strcmpi({EEG.chanlocs.labels}, 'EXG6'));
        exg7_idx = find(strcmpi({EEG.chanlocs.labels}, 'EXG7'));
        c16_idx = find(strcmpi({EEG.chanlocs.labels}, 'C16'));
        c29_idx = find(strcmpi({EEG.chanlocs.labels}, 'C29'));
    
        if any([isempty(exg6_idx), isempty(exg7_idx), isempty(c16_idx), isempty(c29_idx)])
            warning('One or more required channels missing for %s. Skipping.', subj_id);
            continue;
        end
    
        % Extract data
        exg6 = EEG.data(exg6_idx, :);
        exg7 = EEG.data(exg7_idx, :);
        c16 = EEG.data(c16_idx, :);
        c29 = EEG.data(c29_idx, :);
    
        % Z-scores
        z_exg6 = (exg6 - mean(exg6)) / std(exg6);
        z_exg7 = (exg7 - mean(exg7)) / std(exg7);
    
        % Time vector
        time = (0:EEG.pnts-1) / EEG.srate;
    
        % Plot
        figure('Name', ['Manual Marking - ' subj_id], 'NumberTitle', 'off');
        
        subplot(4,1,1)
        plot(time, z_exg6, 'b'); hold on;
        plot(time(abs(z_exg6)>2), z_exg6(abs(z_exg6)>2), 'ro');
        yline(2, 'r--'); yline(-2, 'r--');
        title('EXG6 (under right eye, z-scored)'); ylabel('Z-score'); grid on;
    
        subplot(4,1,2)
        plot(time, z_exg7, 'k'); hold on;
        plot(time(abs(z_exg7)>2), z_exg7(abs(z_exg7)>2), 'mo');
        yline(2, 'r--'); yline(-2, 'r--');
        title('EXG7 (above right eye, z-scored)'); ylabel('Z-score'); grid on;
    
        subplot(4,1,3)
        plot(time, c16, 'g');
        title('C16 (raw amplitude)'); ylabel('µV'); grid on;
    
        subplot(4,1,4)
        plot(time, c29, 'm');
        title('C29 (raw amplitude)'); xlabel('Time (s)'); ylabel('µV'); grid on;
    
        % Manual marking
        disp('Click 12 timepoints to mark (e.g., changes in eye condition)...');
        [x_marked, ~] = ginput(12);
        marked_points = round(x_marked(:), 2);
    
        fprintf('Marked timepoints (s) for %s:\n', subj_id);
        disp(marked_points');
    
        % Save
        col_names = arrayfun(@(x) sprintf('Timepoint_%02d', x), 1:12, 'UniformOutput', false);
        subject_row = array2table([cellstr(subj_id), num2cell(marked_points')], ...
                                  'VariableNames', ['SubjectID', col_names]);
    
        if ~exist(output_dir, 'dir'), mkdir(output_dir); end
        save_path = fullfile(output_dir, [subj_id '_manual_marked_times.csv']);
        writetable(subject_row, save_path);
        fprintf('Saved individual CSV for %s to: %s\n', subj_id, save_path);
    end
end
