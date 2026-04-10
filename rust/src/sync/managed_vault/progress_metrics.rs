use std::collections::BTreeMap;

pub(super) fn pull_progress_counts(
    progress_start_since: &BTreeMap<String, i64>,
    current_since: &BTreeMap<String, i64>,
    remote_max: &BTreeMap<String, i64>,
) -> (u64, u64) {
    let mut done = 0u64;
    for (device_id, current_seq) in current_since {
        let start_seq = progress_start_since.get(device_id).copied().unwrap_or(0);
        if *current_seq > start_seq {
            done += (*current_seq - start_seq) as u64;
        }
    }

    let mut total = done;
    for (device_id, max_seq) in remote_max {
        let start_seq = progress_start_since.get(device_id).copied().unwrap_or(0);
        let current_seq = current_since.get(device_id).copied().unwrap_or(0);
        let remaining_from = current_seq.max(start_seq);
        if *max_seq > remaining_from {
            total += (*max_seq - remaining_from) as u64;
        }
    }

    (done, total)
}

pub(super) fn report_pull_progress(
    progress: &mut dyn FnMut(u64, u64),
    reported_done: &mut u64,
    done: u64,
    total: u64,
) -> u64 {
    let clamped_done = done.max(*reported_done).min(total);
    *reported_done = clamped_done;
    progress(clamped_done, total);
    clamped_done
}
