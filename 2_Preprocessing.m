========================================================================
%  Please cite:
%  Authors (202X).
%  TITLE. bioRxiv, 202X-X.
%  https://doi.org/X
% =======================================================================

%% VIA15 Rest preprocessing Pipeline
% Phase 1: Raw -> step12_reref (Script 1 steps 1–12)
% Phase 2: Re-ICA+ICLabel (p>=0.60), ASR strict masks, PSD ±3 SD remove -> *_preprocessed.set
% Phase 3: ASR-style per-channel segmented masking (flatlines + burst windows) -> *_asrseg_final.set
% Phase 4: PSD band z-score pruning (|z|>=5 in any band) -> *_psdpruned.set

% All operations are performed sequentially on the same EEG variable for each subject.
% Intermediate results + QC are saved

clear; close all;
cd('/mnt/projects/VIA_MHA/VIA15_Rest/Preprocessing');

[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab('nogui');

%% ===== Paths =====
data_path     = '/mnt/projects/VIA_MHA/VIA15_Rest/nobackup/Data_Rest/';
unified_root  = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/UNIFIED_RUN_ONEPASS';

phase1_out    = fullfile(unified_root, 'Phase1_step12_reref');           % ends at step12_reref
phase2_out    = fullfile(unified_root, 'Phase2_reICA60_ASRstrict');      % *_preprocessed.set
phase3_out    = fullfile(unified_root, 'Phase3_ASRseg_perchan');         % *_asrseg_final.set
phase4_out    = fullfile(unified_root, 'Phase4_PSDprune');               % *_psdpruned.set

dirs = {phase1_out, phase2_out, phase3_out, phase4_out};
for d = 1:numel(dirs)
    if ~exist(dirs{d},'dir'), mkdir(dirs{d}); end
    if ~exist(fullfile(dirs{d},'Logs'),'dir'), mkdir(fullfile(dirs{d},'Logs')); end
end

%% ===== Common small helper =====
save_step = @(EEG, outdir, subj, suffix) pop_saveset(EEG, 'filename', sprintf('%s_%s.set', subj, suffix), 'filepath', outdir);

%% ===== Parameters =====
% Phase 1
exg_channels  = {'EXG1','EXG2','EXG3','EXG4','EXG5','EXG6','EXG7','EXG8'};
lowcut = 0.5; highcut = 100;
line1  = [49 51]; line2 = [99 101];

% Phase 2 — Re-ICA + ICLabel + ASR strict
iclabel_prob_thr = 0.60;
z_thr        = 3;          % IC activation z threshold
blink_pad_s  = 0.10;       % padding around supra-z
spatial_thr  = 0.50;       % channel inclusion fraction of max |icawinv|
asr_flatline_sec  = 5;
asr_channel_corr  = 0.80;
asr_line_noise_sd = 4;
asr_burst_crit    = 15;
asr_window_crit   = 0.25;

% Phase 2 PSD outlier removal
psd_mean_band = [0.1 100]; % dB mean power band
psd_sd_thresh = 3;

% Phase 3 — ASR-style segmented per-channel
win_sec   = 1.0;
step_sec  = 0.25;
min_gap_s = 0.05;
asrseg_flatline_sec = 3;
asrseg_burst_zthr   = 10;

% Phase 4 — PSD band z pruning
band_defs = [ 1 4; 4 8; 8 13; 13 30; 30 100 ];
band_labels = {'delta (1-4)','theta (4-8)','alpha (8-13)','beta (13-30)','gamma (30-100)'};
z_band_thresh = 5;
welch_win_sec = 4;
welch_overlap = 0.5;

%% ===== Master loop: load once, then Phase 1 -> Phase 4 =====
bdf_files = dir(fullfile(data_path, '*_Rest.bdf'));
if isempty(bdf_files), error('No .bdf files found in %s.', data_path); end

% For final pruning summary across subjects
master_rows = {};

for i = 1:numel(bdf_files)
    %% ===== Load once =====
    filename = bdf_files(i).name;
    subj_id  = erase(filename, '_Rest.bdf');
    fprintf('\n=========== %s (%d/%d) ===========\n', subj_id, i, numel(bdf_files));

    % Per-phase logs (kept separate for clarity)
    phase1_log = cell(0,4);
    phase2_log = cell(0,4);
    phase3_log = cell(0,4);

    EEG = pop_biosig(fullfile(data_path, filename));
    EEG.setname = subj_id;

    %% ===== Phase 1: Raw -> step12_reref =====
    fprintf('--- Phase 1: Pre-ICA preprocessing ---\n');
    save_step(EEG, phase1_out, subj_id, 'step01_loaded');
    qc_save(EEG, fullfile(phase1_out,'Logs'), subj_id, 'step01_loaded');

    % Chanlocs
    EEG = pop_chanedit(EEG, 'lookup', '/mnt/projects/VIA_MHA/VIA15_Rest/Final/biosemi128.sfp');
    save_step(EEG, phase1_out, subj_id, 'step02_chanlocs');
    qc_save(EEG, fullfile(phase1_out,'Logs'), subj_id, 'step02_chanlocs');

    % Remove EXG
    rm_labels = exg_channels;
    rm_idx = find(ismember({EEG.chanlocs.labels}, rm_labels));
    if ~isempty(rm_idx)
        dur_sec = size(EEG.data,2)/EEG.srate;
        for k = 1:numel(rm_idx)
            ch_lbl = EEG.chanlocs(rm_idx(k)).labels;
            phase1_log(end+1,:) = {'Remove_Excluded', ch_lbl, size(EEG.data,2), dur_sec}; %#ok<AGROW>
        end
        EEG = pop_select(EEG, 'nochannel', rm_labels);
    end
    save_step(EEG, phase1_out, subj_id, 'step03_rm_exg');
    qc_save(EEG, fullfile(phase1_out,'Logs'), subj_id, 'step03_rm_exg');

    % Resample
    EEG = pop_resample(EEG, 256);
    save_step(EEG, phase1_out, subj_id, 'step04_resampled');
    qc_save(EEG, fullfile(phase1_out,'Logs'), subj_id, 'step04_resampled');

    % Bandpass
    EEG = pop_eegfiltnew(EEG, lowcut, highcut);
    save_step(EEG, phase1_out, subj_id, 'step05_bandpass');
    qc_save(EEG, fullfile(phase1_out,'Logs'), subj_id, 'step05_bandpass');

    % Notch
    EEG = pop_eegfiltnew(EEG, line1(1), line1(2), [], 1);
    EEG = pop_eegfiltnew(EEG, line2(1), line2(2), [], 1);
    save_step(EEG, phase1_out, subj_id, 'step06_notch');
    qc_save(EEG, fullfile(phase1_out,'Logs'), subj_id, 'step06_notch');

    % Average rereference
    EEG = pop_reref(EEG, []);
    save_step(EEG, phase1_out, subj_id, 'step12_reref');
    qc_save(EEG, fullfile(phase1_out,'Logs'), subj_id, 'step12_reref');

    % Phase 1 log
    if isempty(phase1_log)
        T1 = cell2table(cell(0,4), 'VariableNames', {'Step','Channel','Samples_Removed','Seconds_Removed'});
    else
        T1 = cell2table(phase1_log, 'VariableNames', {'Step','Channel','Samples_Removed','Seconds_Removed'});
    end
    writetable(T1, fullfile(phase1_out,'Logs', sprintf('%s_phase1_log.csv', subj_id)));

    %% ===== Phase 2: Re-ICA(0.60)+ASR strict+PSD ±3 SD =====
    fprintf('--- Phase 2: Re-ICA / ICLabel 0.60 + strict ASR + PSD prune (±3SD) ---\n');

    save_step(EEG, phase2_out, subj_id, 'step12_reref_source');
    qc_save(EEG, fullfile(phase2_out,'Logs'), subj_id, 'step12_reref_source');

    % Re-ICA + ICLabel
    EEG = pop_runica(EEG, 'icatype','picard', 'maxiter',1000);
    save_step(EEG, phase2_out, subj_id, 'step10_ica');
    qc_save(EEG, fullfile(phase2_out,'Logs'), subj_id, 'step10_ica');

    EEG = pop_iclabel(EEG, 'default');
    save_step(EEG, phase2_out, subj_id, 'step11_iclabel');
    qc_save(EEG, fullfile(phase2_out,'Logs'), subj_id, 'step11_iclabel');

    % ICLabel selection
    classes   = EEG.etc.ic_classification.ICLabel.classes;
    cls_probs = EEG.etc.ic_classification.ICLabel.classifications;
    cls_map = struct('Brain',[],'Muscle',[],'Eye',[],'Heart',[],'ChannelNoise',[]);
    for k = 1:numel(classes)
        nm = lower(strrep(classes{k},' ','')); %#ok<*LOWER>
        switch nm
            case 'muscle',       cls_map.Muscle = k;
            case 'eye',          cls_map.Eye    = k;
            case 'heart',        cls_map.Heart  = k;
            case 'channelnoise', cls_map.ChannelNoise = k;
            case 'brain',        cls_map.Brain  = k;
        end
    end
    comps.Eye          = find(cls_probs(:,cls_map.Eye)          >= iclabel_prob_thr);
    comps.Muscle       = find(cls_probs(:,cls_map.Muscle)       >= iclabel_prob_thr);
    comps.Heart        = find(cls_probs(:,cls_map.Heart)        >= iclabel_prob_thr);
    comps.ChannelNoise = find(cls_probs(:,cls_map.ChannelNoise) >= iclabel_prob_thr);

    % Channel×time masks from ICs
    mask.Eye          = make_ic_mask_channelwise(EEG, comps.Eye,          z_thr, blink_pad_s, spatial_thr);
    mask.Muscle       = make_ic_mask_channelwise(EEG, comps.Muscle,       z_thr, blink_pad_s, spatial_thr);
    mask.Heart        = make_ic_mask_channelwise(EEG, comps.Heart,        z_thr, blink_pad_s, spatial_thr);
    mask.ChannelNoise = make_ic_mask_channelwise(EEG, comps.ChannelNoise, z_thr, blink_pad_s, spatial_thr);

    % ASR strict: whole bad channels + all channels at burst samples
    try
        EEG_tmp = pop_clean_rawdata(EEG, ...
            'FlatlineCriterion',  asr_flatline_sec, ...
            'ChannelCriterion',   asr_channel_corr, ...
            'LineNoiseCriterion', asr_line_noise_sd, ...
            'Highpass',           'off', ...
            'BurstCriterion',     asr_burst_crit, ...
            'WindowCriterion',    asr_window_crit, ...
            'BurstRejection',     'on', ...
            'Distance',           'Euclidean');
        nCh = size(EEG.data,1); nS = size(EEG.data,2);
        mask.ASR = false(nCh, nS);
        has_samples = isfield(EEG_tmp.etc,'clean_sample_mask')  && ~isempty(EEG_tmp.etc.clean_sample_mask);
        has_chans   = isfield(EEG_tmp.etc,'clean_channel_mask') && ~isempty(EEG_tmp.etc.clean_channel_mask);
        if has_chans
            bad_ch = ~logical(EEG_tmp.etc.clean_channel_mask(:));
            if any(bad_ch), mask.ASR(bad_ch,:) = true; end
        end
        if has_samples
            bad_t = ~logical(EEG_tmp.etc.clean_sample_mask(:))';
            if any(bad_t), mask.ASR(:,bad_t) = true; end
        end
    catch ME
        warning('ASR detection failed for %s: %s', subj_id, ME.message);
        mask.ASR = false(size(EEG.data,1), size(EEG.data,2));
    end

    % Apply masks (Eye, Heart, ChannelNoise, ASR, Muscle)
    steps2 = {'Eye','Heart','ChannelNoise','ASR','Muscle'};
    for si = 1:numel(steps2)
        step = steps2{si};
        this_mask = mask.(step);
        if any(this_mask,'all')
            EEG_before = EEG;
            for ch = 1:size(EEG.data,1)
                idx = this_mask(ch,:);
                if any(idx), EEG.data(ch,idx) = NaN; end
            end
            phase2_log = append_log(phase2_log, sprintf('Mask_%s', step), EEG_before, EEG, EEG.srate);
            save_step(EEG, phase2_out, subj_id, sprintf('step13_mask_%s', lower(step)));
            qc_save(EEG, fullfile(phase2_out,'Logs'), subj_id, sprintf('step13_mask_%s', lower(step)));
        end
    end

    % PSD-based bad-channel removal (±3 SD of mean dB 0.1–100 Hz)
    data_tmp = double(EEG.data);
    for ch = 1:size(data_tmp,1)
        x = data_tmp(ch,:); if any(isnan(x)), x = fillmissing(x,'linear',2,'EndValues','nearest'); end
        data_tmp(ch,:) = x - mean(x,'omitnan');
    end
    window_length = 4 * EEG.srate; noverlap = window_length/2; nfft = [];
    [spectra, freqs] = pwelch(data_tmp', window_length, noverlap, nfft, EEG.srate, 'power');
    spectra_dB = 10*log10(spectra + eps);
    idx_band = freqs >= psd_mean_band(1) & freqs <= psd_mean_band(2);
    mean_power = mean(spectra_dB(idx_band,:), 1);
    mu = mean(mean_power); sd = std(mean_power);
    bad_idx = find(mean_power < (mu-psd_sd_thresh*sd) | mean_power > (mu+psd_sd_thresh*sd));
    if ~isempty(bad_idx)
        dur_sec = size(EEG.data,2)/EEG.srate;
        for k = 1:numel(bad_idx)
            ch_lbl = EEG.chanlocs(bad_idx(k)).labels;
            phase2_log(end+1,:) = {'Remove_BadChannel', ch_lbl, size(EEG.data,2), dur_sec}; %#ok<AGROW>
        end
        bad_labels = {EEG.chanlocs(bad_idx).labels};
        EEG = pop_select(EEG, 'nochannel', bad_labels);
    end
    save_step(EEG, phase2_out, subj_id, 'step14_remove_badch');
    qc_save(EEG, fullfile(phase2_out,'Logs'), subj_id, 'step14_remove_badch');

    % Phase 2 save
    preproc_name = sprintf('%s_preprocessed.set', subj_id);
    EEG = pop_saveset(EEG, 'filename', preproc_name, 'filepath', phase2_out);
    qc_save(EEG, fullfile(phase2_out,'Logs'), subj_id, 'final');

    if isempty(phase2_log)
        T2 = cell2table(cell(0,4), 'VariableNames', {'Step','Channel','Samples_Removed','Seconds_Removed'});
    else
        T2 = cell2table(phase2_log, 'VariableNames', {'Step','Channel','Samples_Removed','Seconds_Removed'});
    end
    writetable(T2, fullfile(phase2_out,'Logs', sprintf('%s_perstep_channel_log.csv', subj_id)));

    %% ===== Phase 3: ASR per-channel masking =====
    fprintf('--- Phase 3: ASR per-channel masking ---\n');

    fs  = EEG.srate; [nCh, nS] = size(EEG.data);
    M = false(nCh, nS);

    % Flatline segments
    M_flat = detect_flatlines_per_channel(EEG.data, fs, asrseg_flatline_sec);
    M = M | M_flat;

    % Sliding windows
    [win_idx, win_map] = sliding_windows(nS, fs, win_sec, step_sec);

    % Filled copy for metrics
    Xf = double(EEG.data);
    for ch = 1:nCh
        x = Xf(ch,:); if any(isnan(x)), x = fillmissing(x,'linear',2,'EndValues','nearest'); end
        Xf(ch,:) = x - mean(x, 'omitnan');
    end

    % Burstiness (RMS z per channel across windows)
    RMS = window_rms(Xf, win_idx);
    zR  = robust_z(RMS);                % [nCh x nWin]
    bad_burst = zR > asrseg_burst_zthr;

    % Map to samples and close small gaps
    M_seg = windows_to_mask(bad_burst, win_map, nS);
    M_seg = close_small_gaps(M_seg, fs, min_gap_s);

    % Combine and apply with logging
    M = M | M_seg;
    EEG_before = EEG;
    for ch = 1:nCh
        idx = M(ch,:);
        if any(idx)
            EEG.data(ch, idx) = NaN;
            before_nan = isnan(EEG_before.data(ch,:));
            delta_mask = idx & ~before_nan;
            smp = sum(delta_mask);
            if smp > 0
                phase3_log(end+1,:) = {'Mask_ASRseg', EEG.chanlocs(ch).labels, smp, smp/fs}; %#ok<AGROW>
            end
        end
    end

    % Save + QC
    save_step(EEG, phase3_out, subj_id, 'asrseg_masked');
    qc_save(EEG, fullfile(phase3_out,'Logs'), subj_id, 'asrseg_masked');

    asrseg_name = sprintf('%s_asrseg_final.set', subj_id);
    EEG = pop_saveset(EEG, 'filename', asrseg_name, 'filepath', phase3_out);
    qc_save(EEG, fullfile(phase3_out,'Logs'), subj_id, 'final');

    if isempty(phase3_log)
        T3 = cell2table(cell(0,4), 'VariableNames', {'Step','Channel','Samples_Removed','Seconds_Removed'});
    else
        T3 = cell2table(phase3_log, 'VariableNames', {'Step','Channel','Samples_Removed','Seconds_Removed'});
    end
    writetable(T3, fullfile(phase3_out,'Logs', sprintf('%s_asrseg_perstep_log.csv', subj_id)));

    %% ===== Phase 4: PSD band z pruning (|z|>=5 any band) =====
    fprintf('--- Phase 4: PSD band robust-z pruning (|z|>=%g) ---\n', z_band_thresh);

    X   = double(EEG.data);
    [nCh_beforePrune, ~] = size(X);

    % Fill NaNs for PSD only
    Xf = X;
    for ch = 1:nCh_beforePrune
        xx = Xf(ch,:); if any(isnan(xx)), xx = fillmissing(xx,'linear',2,'EndValues','nearest'); end
        Xf(ch,:) = xx - mean(xx, 'omitnan');
    end
    allnan_ch = all(isnan(X),2);
    Xp = Xf; Xp(allnan_ch,:) = 0;

    winlen = max(256, round(welch_win_sec*fs));
    nover  = round(winlen*welch_overlap);
    nfft   = [];
    [P, f] = pwelch(Xp', winlen, nover, nfft, fs, 'power');
    if any(allnan_ch), P(:,allnan_ch) = NaN; end
    Pdb = 10*log10(P + eps);

    % Band powers (dB)
    nBands = size(band_defs,1);
    band_pow_db = nan(nCh_beforePrune, nBands);
    for b = 1:nBands
        idx = f >= band_defs(b,1) & f <= band_defs(b,2);
        if any(idx)
            band_pow_db(:,b) = mean(Pdb(idx,:), 1, 'omitnan')';
        end
    end

    % Robust z across channels per band
    Z = robust_z(band_pow_db);
    bad_by_band = abs(Z) >= z_band_thresh;
    bad_any = any(bad_by_band, 2);
    bad_idx = find(bad_any);
    bad_labels = {EEG.chanlocs(bad_idx).labels}';

    % Log per subject
    trig = cell(numel(bad_idx),1); zmax = nan(numel(bad_idx),1);
    for k = 1:numel(bad_idx)
        ch = bad_idx(k);
        bands_k = find(bad_by_band(ch,:));
        trig{k} = strjoin(band_labels(bands_k), ', ');
        zmax(k) = max(abs(Z(ch,bands_k)));
    end
    T4 = table(string(bad_labels), string(trig), zmax, repmat("PSD_outlier_any_band", numel(bad_idx),1), ...
        'VariableNames', {'Channel','BandsTriggered','Zmax','Reason'});
    writetable(T4, fullfile(phase4_out,'Logs', sprintf('%s_psdprune_log.csv', subj_id)));

    % Remove channels
    if ~isempty(bad_idx), EEG = pop_select(EEG, 'nochannel', bad_labels); end

    % Save final pruned dataset + rolling master summary
    out_name = sprintf('%s_psdpruned.set', subj_id);
    EEG = pop_saveset(EEG, 'filename', out_name, 'filepath', phase4_out);
    fprintf('✅ Saved final: %s\n', fullfile(phase4_out, out_name));

    master_rows(end+1,:) = {subj_id, nCh_beforePrune, numel(bad_idx), nCh_beforePrune - numel(bad_idx)}; %#ok<SAGROW>
    Master = cell2table(master_rows, 'VariableNames', {'Subject','Channels_Before','Channels_Removed','Channels_After'});
    writetable(Master, fullfile(phase4_out,'Logs','PSDprune_master_summary.csv'));
end

fprintf('\n🎉 One-pass unified pipeline finished. Final datasets: *_psdpruned.set in %s\n', phase4_out);

%% =======================
%% Local helper functions
%% =======================

function log_entries = append_log(log_entries, step_name, EEG_before, EEG_after, srate)
    nCh  = size(EEG_after.data,1);
    nSmp = size(EEG_after.data,2);
    for ch = 1:nCh
        ch_lbl = EEG_after.chanlocs(ch).labels;
        before_nan = false(1, nSmp);
        after_nan  = isnan(EEG_after.data(ch,:));
        if ch <= size(EEG_before.data,1)
            before_nan = isnan(EEG_before.data(ch,:));
        end
        delta_mask = after_nan & ~before_nan;
        samples_removed = sum(delta_mask);
        if samples_removed > 0
            seconds_removed = samples_removed / srate;
            log_entries(end+1,:) = {step_name, ch_lbl, samples_removed, seconds_removed}; %#ok<AGROW>
        end
    end
end

function M = make_ic_mask_channelwise(EEG, comp_idx, z_thr, pad_s, spatial_thr)
    nCh = size(EEG.data,1);
    nS  = size(EEG.data,2);
    M   = false(nCh, nS);
    if isempty(comp_idx), return; end

    if ~isfield(EEG, 'icaact') || isempty(EEG.icaact)
        EEG.icaact = (EEG.icaweights * EEG.icasphere) * EEG.data(EEG.icachansind, :);
    end
    A  = EEG.icaact(comp_idx, :);
    mu = mean(A, 2);
    sd = std(A, 0, 2);
    zA = (A - mu) ./ max(sd, eps);
    supra = abs(zA) > z_thr;
    pad = max(1, round(pad_s * EEG.srate));
    if pad > 0
        k = ones(1, 1 + 2*pad);
        for c = 1:size(supra,1)
            supra(c,:) = conv(double(supra(c,:)), k, 'same') > 0;
        end
    end
    if ~isfield(EEG, 'icawinv') || isempty(EEG.icawinv)
        EEG.icawinv = pinv(EEG.icaweights * EEG.icasphere);
    end
    W = abs(EEG.icawinv(:, comp_idx));
    mx = max(W, [], 1); mx(mx==0) = eps;
    ChanOK = bsxfun(@ge, W, spatial_thr * mx);
    for j = 1:numel(comp_idx)
        if any(supra(j,:)) && any(ChanOK(:,j))
            M(ChanOK(:,j), supra(j,:)) = true;
        end
    end
end

function qc_save(EEG, log_path, subj_id, step_tag)
    [qc_table, summary_table] = compute_qc_metrics(EEG);
    writetable(qc_table,     fullfile(log_path, sprintf('%s_%s_qc.csv', subj_id, step_tag)));
    writetable(summary_table,fullfile(log_path, sprintf('%s_%s_qc_summary.csv', subj_id, step_tag)));
    fprintf('🔎 QC saved: %s (and summary)\n', fullfile(log_path, sprintf('%s_%s_qc.csv', subj_id, step_tag)));
end

function [qc_table, summary_table] = compute_qc_metrics(EEG)
    X = double(EEG.data);
    nCh = size(X,1); nS = size(X,2); fs = EEG.srate;
    nan_pct = sum(isnan(X),2) / nS * 100;

    Xf = X;
    for ch = 1:nCh
        x = Xf(ch,:); if any(isnan(x)), x = fillmissing(x,'linear',2,'EndValues','nearest'); end
        Xf(ch,:) = x - mean(x, 'omitnan');
    end

    % Safe PSD for all-NaN channels
    allnan_ch = all(isnan(X),2);
    Xp = Xf; Xp(allnan_ch,:) = 0;

    winlen = max(256, round(4*fs));
    nover  = round(winlen/2);
    nfft   = [];
    [P, f] = pwelch(Xp', winlen, nover, nfft, fs, 'power');
    if any(allnan_ch), P(:,allnan_ch) = NaN; end
    Pdb = 10*log10(P + eps);

    function pw = bandpow(ff, PP, f1, f2)
        idx = ff >= f1 & ff <= f2;
        if ~any(idx), pw = nan(1, size(PP,2)); return; end
        pw = mean(PP(idx,:), 1, 'omitnan');
    end

    alpha_pk   = max(Pdb(f>=8 & f<=13,:), [], 1, 'omitnan');
    side_pw    = (bandpow(f,Pdb,6,8) + bandpow(f,Pdb,13,15))/2;
    alpha_snr  = alpha_pk - side_pw;
    mus_pw     = bandpow(f,P,30,80);
    low_pw     = bandpow(f,P,1,30);
    muscle_ratio = mus_pw ./ (low_pw + eps);

    idx_slope = f >= 2 & f <= 40;
    fx = f(idx_slope);
    Xlog = log10(fx(:));
    slope = nan(nCh,1);
    for ch = 1:nCh
        Ylog = Pdb(idx_slope,ch);
        if any(~isfinite(Ylog)), slope(ch) = nan; continue; end
        p = polyfit(Xlog, Ylog, 1);
        slope(ch) = p(1);
    end

    C = corrcoef(Xf','Rows','pairwise');
    med_icorr = nan(nCh,1);
    for ch = 1:nCh
        v = C(ch,:); v(ch) = nan;
        med_icorr(ch) = median(v,'omitnan');
    end
    meanpw = mean(Pdb(f>=0.1 & f<=100,:),1,'omitnan');
    mu = mean(meanpw,'omitnan'); sd = std(meanpw,'omitnan');
    outlier_psd = (meanpw < mu-3*sd) | (meanpw > mu+3*sd);

    ch_labels = string({EEG.chanlocs.labels})';
    qc_table = table( ...
        ch_labels, nan_pct, alpha_snr', muscle_ratio', slope, med_icorr, outlier_psd', ...
        'VariableNames', {'Channel','NaN_pct','AlphaSNR_dB','MuscleRatio_30to80_over_1to30', ...
                          'SpectralSlope_dBperDecade','MedianInterChanCorr','PSD_Outlier_01to100'} );

    summary_table = table( ...
        mean(nan_pct,'omitnan'), median(nan_pct,'omitnan'), ...
        median(alpha_snr,'omitnan'), median(muscle_ratio,'omitnan'), ...
        median(slope,'omitnan'), median(med_icorr,'omitnan'), ...
        mean(outlier_psd,'omitnan')*100, ...
        'VariableNames', {'NaN_pct_mean','NaN_pct_median','AlphaSNR_dB_median', ...
                          'MuscleRatio_median','SpectralSlope_median', ...
                          'MedianInterChanCorr_median','PSD_Outlier_pct'} );
end

function M = detect_flatlines_per_channel(X, fs, flat_sec)
    [nCh, nS] = size(X);
    M = false(nCh, nS);
    min_len = max(1, round(flat_sec*fs));
    for ch = 1:nCh
        x = X(ch,:); dx = diff(x);
        is_const = [false, dx==0];
        if ~any(is_const), continue; end
        d = diff([0, is_const, 0]);
        run_st = find(d==1); run_en = find(d==-1)-1;
        for k = 1:numel(run_st)
            L = run_en(k)-run_st(k)+1;
            if L >= min_len, M(ch, run_st(k):run_en(k)) = true; end
        end
    end
end

function [win_idx, win_map] = sliding_windows(nS, fs, win_s, step_s)
    w = max(1, round(win_s*fs));
    s = max(1, round(step_s*fs));
    starts = 1:s:(nS-w+1);
    nW = numel(starts);
    win_idx = zeros(2, nW);
    for i = 1:nW
        win_idx(:,i) = [starts(i); starts(i)+w-1];
    end
    win_map.starts = starts; win_map.w = w; win_map.s = s; win_map.nW = nW;
end

function RMS = window_rms(X, win_idx)
    [nCh, ~] = size(X);
    nW = size(win_idx,2);
    RMS = zeros(nCh, nW);
    for w = 1:nW
        a = win_idx(1,w); b = win_idx(2,w);
        seg = X(:,a:b);
        RMS(:,w) = sqrt(mean(seg.^2,2));
    end
end

function Z = robust_z(A)
    % Robust z per column of A (channels x windows or channels x bands)
    medA = median(A,1,'omitnan');
    madA = mad(A,1,1);
    madA(madA==0) = eps;
    Z = (A - medA) ./ (1.4826*madA);
end

function M = windows_to_mask(bad_win, win_map, nS)
    [nCh, nW] = size(bad_win);
    M = false(nCh, nS);
    w = win_map.w;
    starts = win_map.starts;
    for widx = 1:nW
        if ~any(bad_win(:,widx)), continue; end
        a = starts(widx); b = a + w - 1;
        M(bad_win(:,widx), a:b) = true;
    end
end

function M2 = close_small_gaps(M, fs, max_gap_s)
    [nCh, nS] = size(M);
    M2 = false(nCh, nS);
    max_gap = max(1, round(max_gap_s*fs));
    for ch = 1:nCh
        v = M(ch,:); if ~any(v), continue; end
        d = diff([0, v, 0]);
        st = find(d==1); en = find(d==-1)-1;
        for k = 1:numel(st)
            M2(ch, st(k):en(k)) = true;
            if k < numel(st)
                gapA = en(k)+1; gapB = st(k+1)-1;
                if (gapB-gapA+1) <= max_gap, M2(ch, gapA:gapB) = true; end
            end
        end
    end
end
