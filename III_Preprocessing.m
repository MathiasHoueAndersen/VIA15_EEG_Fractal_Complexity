%% VIA15 Rest preprocessing Pipeline — ONE PASS, SAVE+QC AFTER EVERY CHANGE
% No ASR interpolation, no ASR-driven channel removal.
% ASR runs on a NaN-free surrogate to harvest masks; ICA runs on continuous data.
% After both detectors (IC/ASR), all artifact samples are replaced by NaN ONCE.

clear; close all;
cd('/mnt/projects/VIA_MHA/VIA15_Rest/Preprocessing');
addpath('/home/mathiasha/MATLAB_Add-Ons/Collections/EEGLAB/')
savepath
[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab('nogui');

%% ===== Paths =====
data_path    = '/mnt/projects/VIA_MHA/VIA15_Rest/nobackup/Data_Rest2';
out_root     = '/mnt/projects/VIA_MHA/VIA15_Rest/Final/Preprocessed_files_final_redidnotchfilterto4852andmuscleto0.1';
if ~exist(out_root,'dir'), mkdir(out_root); end
if ~exist(fullfile(out_root,'Logs'),'dir'), mkdir(fullfile(out_root,'Logs')); end

%% ===== Helpers =====
save_step = @(EEG, outdir, subj, suffix) pop_saveset(EEG,'filename',sprintf('%s_%s.set',subj,suffix),'filepath',outdir);

%% ===== Parameters =====
% Canonical electrode list — anything not here is dropped immediately.
canonicalNames = { ...
    'A1','A2','A3','A4','A5','A6','A7','A8','A9','A10','A11','A12','A13','A14','A15','A16', ...
    'A17','A18','A19','A20','A21','A22','A23','A24','A25','A26','A27','A28','A29','A30','A31','A32', ...
    'B1','B2','B3','B4','B5','B6','B7','B8','B9','B10','B11','B12','B13','B14','B15','B16','B17','B18','B19','B20','B21','B22','B23','B24','B25','B26','B27','B28','B29','B30','B31','B32', ...
    'C1','C2','C3','C4','C5','C6','C7','C8','C9','C10','C11','C12','C13','C14','C15','C16','C17','C18','C19','C20','C21','C22','C23','C24','C25','C26','C27','C28','C29','C30','C31','C32', ...
    'D1','D2','D3','D4','D5','D6','D7','D8','D9','D10','D11','D12','D13','D14','D15','D16','D17','D18','D19','D20','D21','D22','D23','D24','D25','D26','D27','D28','D29','D30','D31','D32' ...
};

% Filters, reref
lowcut = 0.5; highcut = 100;
line1  = [49 51]; line2 = [99 101];

% ICLabel + masks
iclabel_prob_thr = 0.60;
iclabel_prob_thr_40 = 0.40;
z_thr = 3;
z_thr_2 = 2;
blink_pad_s  = 0.10;
spatial_thr  = 0.25;

% --- ASR detect-only (run on surrogate; we harvest masks, never keep data) ---
% NOTE: We DO NOT call clean_rawdata anymore (it hangs in rasr_* on some installs).
% These parameters still shape the surrogate detector below.
asr_flatline_sec  = 5;     % channels flat >= this are flagged
asr_line_noise_sd = 4;     %#ok<NASGU> kept for compatibility; handled by PSD steps later
asr_burst_crit    = 15;    % used to set global RMS Z threshold (see Step 08)
asr_window_crit   = 0.25;  % if >25% windows bad => global bad time (applied across channels)

% Per-channel RMS burst detector (ASR-like, per-channel)
win_sec   = 1.0;
step_sec  = 0.25;
min_gap_s = 0.05;
asrseg_flatline_sec = 3;
asrseg_burst_zthr   = 10;

% PSD outlier (±3 SD) — optional bad-channel pruning (kept for logging ONLY)
psd_mean_band = [0.5 100];
psd_sd_thresh = 3;

% Final PSD-band z pruning (kept for logging ONLY)
band_defs     = [ 1 4; 4 8; 8 13; 13 30; 30 100 ];
band_labels   = {'delta (1-4)','theta (4-8)','alpha (8-13)','beta (13-30)','gamma (30-100)'};
z_band_thresh = 3;
welch_win_sec = 4; welch_overlap = 0.5;

%% ===== Master loop =====
bdf_files = dir(fullfile(data_path, '*_Rest.bdf'));
if isempty(bdf_files), error('No .bdf files found in %s.', data_path); end

master_rows = {};

for i = 1:numel(bdf_files)
    filename = bdf_files(i).name;
    subj_id  = erase(filename, '_Rest.bdf');
    fprintf('\n=========== %s (%d/%d) ===========\n', subj_id, i, numel(bdf_files));

    % unified per-step log (Channel-wise modifications)
    step_log = cell(0,4); % {'Step','Channel','Samples_Removed','Seconds_Removed'}

    %% Step 01 — Load
    EEG = pop_biosig(fullfile(data_path, filename));
    EEG.setname = subj_id;
    save_step(EEG, out_root, subj_id, 'step01_loaded');               qc_save(EEG, fullfile(out_root,'Logs'), subj_id, 'step01_loaded');

    %% Step 02 — Keep only canonical channels part of the 128 channel EEG setup
    assert(has_labels(EEG), 'EEG.chanlocs.labels missing before canonical filtering.');
    [EEG, dropped, missing] = keep_canonical(EEG, canonicalNames);
    if ~isempty(dropped), fprintf('Dropped non-canonical: %s\n', strjoin(dropped, ',')); end
    if ~isempty(missing), fprintf(2,'MISSING expected: %s\n', strjoin(missing, ',')); end
    save_step(EEG, out_root, subj_id, 'step02_keep_canonical');       qc_save(EEG, fullfile(out_root,'Logs'), subj_id, 'step02_keep_canonical');

    %% Step 03 — Chanlocs lookup
    EEG = pop_chanedit(EEG, 'lookup', '/mnt/projects/VIA_MHA/VIA15_Rest/Final/Helper_files/biosemi128.sfp');
    save_step(EEG, out_root, subj_id, 'step03_chanlocs');             qc_save(EEG, fullfile(out_root,'Logs'), subj_id, 'step03_chanlocs');

    %% Step 04 — Resample
    EEG = pop_resample(EEG, 256);
    save_step(EEG, out_root, subj_id, 'step04_resample256');          qc_save(EEG, fullfile(out_root,'Logs'), subj_id, 'step04_resample256');

    %% Step 05 — Bandpass 0.5–100 Hz
    EEG = pop_eegfiltnew(EEG, lowcut, highcut);
    save_step(EEG, out_root, subj_id, 'step05_bandpass_0p5_100');     qc_save(EEG, fullfile(out_root,'Logs'), subj_id, 'step05_bandpass_0p5_100');


    %% Step 06 — Notch 50 & 100 Hz ±1 Hz
    EEG = pop_eegfiltnew(EEG, line1(1), line1(2), [], 1);
    EEG = pop_eegfiltnew(EEG, line2(1), line2(2), [], 1);
    save_step(EEG, out_root, subj_id, 'step06_notch_50_100');         qc_save(EEG, fullfile(out_root,'Logs'), subj_id, 'step06_notch_50_100');

    %% Step 07 — Average rereference
    EEG = pop_reref(EEG, []);
    save_step(EEG, out_root, subj_id, 'step07_reref_avg');            qc_save(EEG, fullfile(out_root,'Logs'), subj_id, 'step07_reref_avg');

    %% Step 08 — ASR DETECT-ONLY (SURROGATE, NON-BLOCKING — NO clean_rawdata CALL YET)
    % Build NaN-free, demeaned surrogate; compute masks without calling rasr/clean_rawdata.
    ASR = struct('bad_ch', false(EEG.nbchan,1), 'bad_t', false(1,size(EEG.data,2)));
    try
        EEG_asr = EEG; % surrogate
        X = double(EEG_asr.data);
        % Fill + demean
        for ch = 1:size(X,1)
            x = X(ch,:);
            if any(isnan(x)), x = fillmissing(x,'linear',2,'EndValues','nearest'); end
            X(ch,:) = x - mean(x,'omitnan');
        end
        fs = EEG.srate; nS = size(X,2); nCh = size(X,1);

        % --- Channel flatlines ≥ asr_flatline_sec
        M_flat = detect_flatlines_per_channel(X, fs, asr_flatline_sec);
        flatline_ch = any(M_flat,2);

        % --- Sliding RMS windows (global)
        [win_idx, win_map] = sliding_windows(nS, fs, win_sec, step_sec);
        RMSg = sqrt(mean(X.^2,1)); % sample-wise global RMS
        nW = size(win_idx,2);
        wRMS = zeros(1,nW);
        for w = 1:nW
            a = win_idx(1,w); b = win_idx(2,w);
            wRMS(w) = sqrt(mean(RMSg(a:b).^2));
        end
        z_wRMS = robust_z(wRMS);
        z_thr_global = max(6, min(12, asr_burst_crit/2)); % 15->7.5, 25->12 (clamped 6–12)
        bad_win = z_wRMS > z_thr_global;
        M_global = false(1,nS);
        for w = 1:nW
            if bad_win(w)
                a = win_idx(1,w); b = win_idx(2,w);
                M_global(a:b) = true;
            end
        end
        ASR.bad_t = M_global;

        % --- Bad channels union (flatlines OR low corr)
        ASR.bad_ch = flatline_ch;
    catch ME
        warning('ASR surrogate detect-only failed (%s). Continuing with empty ASR masks.');
        ASR = struct('bad_ch', false(EEG.nbchan,1), 'bad_t', false(1,size(EEG.data,2)));
    end
    save_step(EEG, out_root, subj_id, 'step08_asr_detect_only');      qc_save(EEG, fullfile(out_root,'Logs'), subj_id, 'step08_asr_detect_only');

    %% Step 09 — ICA (Picard).
    fprintf('Step 09 — ICA (Picard) on 1.5 Hz HP copy with PCA rank...\n');
    EEG_ica = EEG;
    EEG_ica = pop_eegfiltnew(EEG_ica, 1.5, [], [], 0, [], 0);
    r_est = estimate_data_rank(double(EEG_ica.data));
    r_safe = max(2, min(EEG_ica.nbchan-1, r_est));
    
    EEG_ica = pop_runica(EEG_ica, 'icatype','picard', 'pca', r_safe, 'maxiter', 500);

    EEG.icaweights  = EEG_ica.icaweights;
    EEG.icasphere   = EEG_ica.icasphere;
    EEG.icawinv     = EEG_ica.icawinv;
    EEG.icachansind = EEG_ica.icachansind;
    EEG.icaact      = [];
    EEG = eeg_checkset(EEG);
    save_step(EEG, out_root, subj_id, 'step09_ica');                  qc_save(EEG, fullfile(out_root,'Logs'), subj_id, 'step09_ica');

    %% Step 10 — ICLabel (no changes yet)
    EEG = pop_iclabel(EEG, 'default');
    save_step(EEG, out_root, subj_id, 'step10_iclabel');              qc_save(EEG, fullfile(out_root,'Logs'), subj_id, 'step10_iclabel');

    %% Step 11 — Build IC-derived masks (Eye, Heart, ChannelNoise) — not applied yet
    classes   = EEG.etc.ic_classification.ICLabel.classes;
    cls_probs = EEG.etc.ic_classification.ICLabel.classifications;
    cls_map = struct('Brain',[],'Muscle',[],'Eye',[],'Heart',[],'ChannelNoise',[]);
    for k = 1:numel(classes)
        nm = lower(strrep(classes{k},' ','')); switch nm
            case 'muscle',       cls_map.Muscle = k;
            case 'eye',          cls_map.Eye    = k;
            case 'heart',        cls_map.Heart  = k;
            case 'channelnoise', cls_map.ChannelNoise = k;
            case 'brain',        cls_map.Brain  = k;
        end
    end
    comps.Eye          = find(cls_probs(:,cls_map.Eye)          >= iclabel_prob_thr);
    comps.Muscle       = find(cls_probs(:,cls_map.Muscle)       >= iclabel_prob_thr_40);
    comps.Heart        = find(cls_probs(:,cls_map.Heart)        >= iclabel_prob_thr);
    comps.ChannelNoise = find(cls_probs(:,cls_map.ChannelNoise) >= iclabel_prob_thr);

    maskIC = struct();
    maskIC.Eye          = make_ic_mask_channelwise(EEG, comps.Eye,          z_thr, blink_pad_s, spatial_thr);
    maskIC.Heart        = make_ic_mask_channelwise(EEG, comps.Heart,        z_thr, blink_pad_s, spatial_thr);
    maskIC.ChannelNoise = make_ic_mask_channelwise(EEG, comps.ChannelNoise, z_thr, blink_pad_s, spatial_thr);
    maskIC.Muscle = make_ic_mask_channelwise(EEG, comps.Muscle, z_thr_2, 3*blink_pad_s, spatial_thr);

    % --- ALSO build per-channel segmented (RMS Z) mask now, so we apply everything once
    fs  = EEG.srate; [nCh, nS] = size(EEG.data);
    M_asrseg = false(nCh, nS);
    % Flatlines
    M_flat = detect_flatlines_per_channel(EEG.data, fs, asrseg_flatline_sec);
    M_asrseg = M_asrseg | M_flat;
    % Sliding RMS windows
    [win_idx, win_map] = sliding_windows(nS, fs, win_sec, step_sec);
    Xf = double(EEG.data);
    for ch = 1:nCh
        x = Xf(ch,:); if any(isnan(x)), x = fillmissing(x,'linear',2,'EndValues','nearest'); end
        Xf(ch,:) = x - mean(x, 'omitnan');
    end
    RMS = window_rms(Xf, win_idx);       % nCh x nW
    zR  = robust_z(RMS);                 % z per window (column-wise)
    bad_burst = zR > asrseg_burst_zthr;  % nCh x nW (logical)
    M_seg = windows_to_mask(bad_burst, win_map, nS); % nCh x nS
    M_seg = close_small_gaps(M_seg, fs, min_gap_s);
    M_asrseg = M_asrseg | M_seg;

    save_step(EEG, out_root, subj_id, 'step11_masks_built');          qc_save(EEG, fullfile(out_root,'Logs'), subj_id, 'step11_masks_built');

    %% Step 12 — APPLY MASKS ONCE: IC-derived + ASR bad_t + ASR bad_ch + ASRSEG → NaN
    nCh = size(EEG.data,1); nS = size(EEG.data,2);
    M_apply = false(nCh, nS);

    % IC masks (channel x time)
    for nm = {'Eye','Heart','ChannelNoise','Muscle'}
        if any(maskIC.(nm{1}),'all'), M_apply = M_apply | maskIC.(nm{1}); end
    end

    % ASR global bad time → all channels
    if any(ASR.bad_t), M_apply(:, ASR.bad_t) = true; end

    % ASR bad channels → whole channel timeline (masked, NOT removed)
    if any(ASR.bad_ch), M_apply(ASR.bad_ch, :) = true; end

    % Per-channel RMS burst mask
    if any(M_asrseg,'all'), M_apply = M_apply | M_asrseg; end

    % Apply once
    if any(M_apply, 'all')
        EEG_before = EEG; %#ok<NASGU>
        for ch = 1:nCh
            idx = M_apply(ch,:);
            if any(idx)
                was_nan = isnan(EEG.data(ch,:));
                delta   = idx & ~was_nan;
                smp     = sum(delta);
                EEG.data(ch, idx) = NaN;
                if smp > 0
                    step_log(end+1,:) = {'Mask_COMBINED_ASR_IC', EEG.chanlocs(ch).labels, smp, smp/EEG.srate}; %#ok<AGROW>
                end
            end
        end
    end
    save_step(EEG, out_root, subj_id, 'step12_apply_masks_once');     qc_save(EEG, fullfile(out_root,'Logs'), subj_id, 'step12_apply_masks_once');
end

Master = cell2table(master_rows, 'VariableNames', {'Subject','Channels_Final'});
writetable(Master, fullfile(out_root,'Logs','HARDREM_master_summary.csv'));
fprintf('\n✅ Done %s\n', out_root);

%% =======================
%% Local helper functions
%% =======================

function v = pad_or_trim(v, N, fillval)
    v = v(:);
    if numel(v) < N, v = [v; repmat(fillval, N-numel(v), 1)];
    elseif numel(v) > N, v = v(1:N);
    end
    v = reshape(v, size(v,1), 1);
end

function ok = has_labels(EEG)
    ok = isfield(EEG,'chanlocs') && ~isempty(EEG.chanlocs) && isfield(EEG.chanlocs,'labels');
end

function [EEG2, dropped, missing] = keep_canonical(EEG, canonicalNames)
    canonLower = unique(lower(strtrim(string(canonicalNames(:)))),'stable');
    curLabels  = string({EEG.chanlocs.labels});
    curLower   = lower(strtrim(curLabels(:)));
    keepMask   = ismember(curLower, canonLower);
    dropped    = cellstr(string(curLabels(~keepMask)));
    present    = unique(curLower,'stable');
    missing    = cellstr(string(setdiff(canonLower, present,'stable')));
    keptIdx    = find(keepMask);
    if isempty(keptIdx)
        error('After canonical filtering, zero channels remain. Check labels or canonical set.');
    end
    EEG2 = pop_select(EEG, 'channel', keptIdx);
    EEG2 = eeg_checkset(EEG2);
end

function [bad_idx, bad_labels] = psd_bad_channels(EEG, band, zthr)
    % LOGGING-ONLY helper. Robust to NaNs and all-NaN channels (after masking)
    X = double(EEG.data);
    nCh = size(X,1);

    % Fill NaNs per channel; track channels that are entirely NaN
    allnan_ch = false(nCh,1);
    for ch = 1:nCh
        x = X(ch,:);
        if all(isnan(x))
            allnan_ch(ch) = true;
        else
            if any(isnan(x)), x = fillmissing(x,'linear',2,'EndValues','nearest'); end
            X(ch,:) = x - mean(x,'omitnan');
        end
    end

    % Substitute zeros for all-NaN channels to satisfy pwelch input constraints
    Xp = X;
    if any(allnan_ch), Xp(allnan_ch,:) = 0; end

    % Guard against pathological cases
    if isempty(Xp) || size(Xp,2) < 2
        bad_idx = []; bad_labels = {}; return;
    end

    winlen = max(256, round(4*EEG.srate));
    nover  = round(winlen/2);
    nfft   = [];

    [S,f] = pwelch(Xp', winlen, nover, nfft, EEG.srate, 'power');  % samples x channels
    if any(allnan_ch), S(:,allnan_ch) = NaN; end
    SdB = 10*log10(S + eps);

    % Band average in dB
    idx = f>=band(1) & f<=band(2);
    if ~any(idx), bad_idx = []; bad_labels = {}; return; end
    mp  = mean(SdB(idx,:),1,'omitnan');  % 1 x nCh

    nan_mp = isnan(mp);
    mu = mean(mp(~nan_mp),'omitnan');
    sd = std(mp(~nan_mp),0,'omitnan');

    if ~isfinite(sd) || sd==0
        bad_z = false(1,nCh);
    else
        bad_z = (mp < mu - zthr*sd) | (mp > mu + zthr*sd);
    end

    bad_mask = bad_z | nan_mp;
    bad_idx = find(bad_mask);
    if isempty(bad_idx)
        bad_labels = {};
    else
        bad_labels = {EEG.chanlocs(bad_idx).labels};
    end
end

function [bad_idx, bad_labels, Z, f] = band_z_prune(EEG, band_defs, z_thr, win_s, ovlp)
    % LOGGING-ONLY helper. Does NOT alter EEG.
    X = double(EEG.data);
    fs = EEG.srate;
    for ch = 1:size(X,1)
        xx = X(ch,:); if any(isnan(xx)), xx = fillmissing(xx,'linear',2,'EndValues','nearest'); end
        X(ch,:) = xx - mean(xx, 'omitnan');
    end
    allnan_ch = all(isnan(EEG.data),2);
    Xp = X; Xp(allnan_ch,:) = 0;

    winlen = max(256, round(win_s*fs)); nover = round(winlen*ovlp); nfft = [];
    [P,f] = pwelch(Xp', winlen, nover, nfft, fs, 'power');
    if any(allnan_ch), P(:,allnan_ch) = NaN; end
    Pdb = 10*log10(P + eps);

    nBands = size(band_defs,1);
    band_pow_db = nan(size(Pdb,2), nBands);
    for b = 1:nBands
        idx = f>=band_defs(b,1) & f<=band_defs(b,2);
        if any(idx), band_pow_db(:,b) = mean(Pdb(idx,:), 1, 'omitnan')'; end
    end

    Z = robust_z(band_pow_db); % channels x bands
    bad_any = any(abs(Z) >= z_thr, 2);
    bad_idx = find(bad_any);
    bad_labels = {EEG.chanlocs(bad_idx).labels}';
end

function qc_save(EEG, log_path, subj_id, step_tag)
    [qc_table, summary_table] = compute_qc_metrics(EEG);
    writetable(qc_table,      fullfile(log_path, sprintf('%s_%s_qc.csv', subj_id, step_tag)));
    writetable(summary_table, fullfile(log_path, sprintf('%s_%s_qc_summary.csv', subj_id, step_tag)));
    fprintf('🔎 QC saved: %s (and summary)\n', fullfile(log_path, sprintf('%s_%s_qc.csv', subj_id, step_tag)));
end

function [qc_table, summary_table] = compute_qc_metrics(EEG)
    X = double(EEG.data);
    %%% CHANGED: assert we have time samples; keep this from ever being empty.
    if isempty(X) || size(X,2) < 2
        warning('compute_qc_metrics: empty or too-short data; returning minimal QC rows.');
        qc_table = table(string({EEG.chanlocs.labels})', ...
            zeros(numel(EEG.chanlocs),1), zeros(numel(EEG.chanlocs),1), ...
            zeros(numel(EEG.chanlocs),1), nan(numel(EEG.chanlocs),1), ...
            nan(numel(EEG.chanlocs),1), false(numel(EEG.chanlocs),1), ...
            'VariableNames', {'Channel','NaN_pct','AlphaSNR_dB','MuscleRatio_30to80_over_1to30', ...
                              'SpectralSlope_dBperDecade','MedianInterChanCorr','PSD_Outlier_01to100'});
        summary_table = table(0,0,0,0,NaN,NaN,0, ...
            'VariableNames', {'NaN_pct_mean','NaN_pct_median','AlphaSNR_dB_median', ...
                              'MuscleRatio_median','SpectralSlope_median', ...
                              'MedianInterChanCorr_median','PSD_Outlier_pct'});
        return;
    end

    nCh = size(X,1); nS = size(X,2); fs = EEG.srate;
    nan_pct = sum(isnan(X),2) / nS * 100;

    Xf = X;
    for ch = 1:nCh
        x = Xf(ch,:); if any(isnan(x)), x = fillmissing(x,'linear',2,'EndValues','nearest'); end
        Xf(ch,:) = x - mean(x, 'omitnan');
    end

    allnan_ch = all(isnan(X),2);
    Xp = Xf; Xp(allnan_ch,:) = 0;

    winlen = max(256, round(4*fs));
    nover  = round(winlen/2); nfft = [];
    [P, f] = pwelch(Xp', winlen, nover, nfft, fs, 'power');
    if any(allnan_ch), P(:,allnan_ch) = NaN; end
    Pdb = 10*log10(P + eps);

    band = @(f1,f2) mean(Pdb(f>=f1 & f<=f2,:),1,'omitnan');

    alpha_pk   = max(Pdb(f>=8 & f<=13,:), [], 1, 'omitnan');
    side_pw    = (band(6,8) + band(13,15))/2;
    alpha_snr  = alpha_pk - side_pw;
    mus_pw     = mean(P(f>=30 & f<=80,:),1,'omitnan');
    low_pw     = mean(P(f>=1 & f<=30,:),1,'omitnan');
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

    meanpw = mean(Pdb(f>=0.5 & f<=100,:),1,'omitnan');
    mu = mean(meanpw,'omitnan'); sd = std(meanpw,'omitnan');
    if ~isfinite(sd) || sd==0
        outlier_psd = false(1,nCh);
    else
        outlier_psd = (meanpw < mu-3*sd) | (meanpw > mu+3*sd);
    end

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
    for i = 1:nW, win_idx(:,i) = [starts(i); starts(i)+w-1]; end
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
    medA = median(A,1,'omitnan');
    madA = mad(A,1,1); madA(madA==0) = eps;
    Z = (A - medA) ./ (1.4826*madA);
end

function M = windows_to_mask(bad_win, win_map, nS)
    [nCh, ~] = size(bad_win);
    w = win_map.w; starts = win_map.starts; nWmap = numel(starts);
    nWuse = min(size(bad_win,2), nWmap);
    M = false(nCh, nS);
    for widx = 1:nWuse
        a = starts(widx); b = min(a + w - 1, nS);
        if a>b, continue; end
        idx_ch = logical(bad_win(:,widx));
        if any(idx_ch), M(idx_ch, a:b) = true; end
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

function r = estimate_data_rank(X)
    X = X - mean(X, 2, 'omitnan');
    for ch = 1:size(X,1)
        if any(isnan(X(ch,:)))
            xx = fillmissing(X(ch,:),'linear',2,'EndValues','nearest');
            X(ch,:) = xx - mean(xx,'omitnan');
        end
    end
    C = (X*X.') ./ max(1, size(X,2));
    [~,S,~] = svd(C,'econ');
    s = diag(S);
    tol = max(size(C)) * eps(max(s));
    r = sum(s > tol);
    r = max(1, min(r, size(X,1)));
end

function M = make_ic_mask_channelwise(EEG, ic_idx, z_thr, pad_s, spatial_thr)
    nCh = size(EEG.data,1);
    nS  = size(EEG.data,2);
    M   = false(nCh, nS);
    if isempty(ic_idx), return; end

    req = {'icawinv','icaweights','icasphere'};
    for r = 1:numel(req)
        if ~isfield(EEG, req{r}) || isempty(EEG.(req{r}))
            warning('ICA fields missing (%s). No IC mask applied.', req{r});
            return;
        end
    end

    if isfield(EEG,'icaact') && ~isempty(EEG.icaact)
        AIC = double(EEG.icaact);
    else
        W = double(EEG.icaweights) * double(EEG.icasphere);
        if isfield(EEG,'icachansind') && ~isempty(EEG.icachansind)
            X = double(EEG.data(EEG.icachansind,:));
        else
            X = double(EEG.data);
        end
        AIC = W * X;
    end

    nIC = size(AIC,1);
    if any(ic_idx < 1) || any(ic_idx > nIC)
        warning('IC indices out of range. Skipping IC mask.'); return;
    end

    mu  = mean(AIC, 2, 'omitnan');
    sd  = std(AIC, 0, 2, 'omitnan'); sd(sd==0) = eps;
    Zic = (AIC - mu) ./ sd;
    high = false(nIC, nS);
    high(ic_idx, :) = abs(Zic(ic_idx,:)) >= z_thr;

    pad_samp = max(0, round(pad_s * EEG.srate));
    if pad_samp > 0
        ker = ones(1, 2*pad_samp + 1, 'logical');
        for ii = ic_idx(:)'
            if any(high(ii,:))
                v = conv(double(high(ii,:)), double(ker), 'same') > 0;
                high(ii,:) = v;
            end
        end
    end

    Amap = abs(double(EEG.icawinv)); % nCh x nIC
    if size(Amap,2) ~= nIC
        warning('icawinv size mismatch; skipping IC mask.'); return;
    end

    for ii = ic_idx(:)'
        if ~any(high(ii,:)), continue; end
        w = Amap(:, ii);
        if all(~isfinite(w)), continue; end
        wmax = max(w, [], 'omitnan'); if ~(isfinite(wmax) && wmax>0), continue; end
        ch_keep = (w >= spatial_thr * wmax);
        if ~any(ch_keep), continue; end
        t_keep  = high(ii,:);
        M(ch_keep, t_keep) = true;
    end
end
