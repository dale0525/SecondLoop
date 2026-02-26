use std::sync::{Condvar, Mutex, OnceLock};

const REMOTE_LLM_REQUEST_MAX_CONCURRENCY: usize = 5;

#[derive(Default)]
struct RemoteLlmRequestState {
    in_flight: usize,
}

fn remote_llm_request_gate() -> &'static (Mutex<RemoteLlmRequestState>, Condvar) {
    static GATE: OnceLock<(Mutex<RemoteLlmRequestState>, Condvar)> = OnceLock::new();
    GATE.get_or_init(|| (Mutex::new(RemoteLlmRequestState::default()), Condvar::new()))
}

pub(crate) struct RemoteLlmRequestGuard {
    released: bool,
}

impl RemoteLlmRequestGuard {
    fn release(&mut self) {
        if self.released {
            return;
        }
        self.released = true;

        let (lock, condvar) = remote_llm_request_gate();
        let mut state = lock.lock().unwrap_or_else(|poison| poison.into_inner());
        if state.in_flight > 0 {
            state.in_flight -= 1;
            condvar.notify_one();
        }
    }
}

impl Drop for RemoteLlmRequestGuard {
    fn drop(&mut self) {
        self.release();
    }
}

pub(crate) fn acquire_remote_llm_request_slot() -> RemoteLlmRequestGuard {
    let (lock, condvar) = remote_llm_request_gate();
    let mut state = lock.lock().unwrap_or_else(|poison| poison.into_inner());
    while state.in_flight >= REMOTE_LLM_REQUEST_MAX_CONCURRENCY {
        state = condvar
            .wait(state)
            .unwrap_or_else(|poison| poison.into_inner());
    }
    state.in_flight += 1;
    RemoteLlmRequestGuard { released: false }
}

#[cfg(test)]
mod tests {
    use super::{acquire_remote_llm_request_slot, REMOTE_LLM_REQUEST_MAX_CONCURRENCY};
    use std::sync::mpsc;
    use std::time::Duration;

    #[test]
    fn remote_llm_request_max_concurrency_is_five() {
        assert_eq!(REMOTE_LLM_REQUEST_MAX_CONCURRENCY, 5);
    }

    #[test]
    fn remote_llm_request_blocks_when_slots_are_full() {
        let mut guards = Vec::with_capacity(REMOTE_LLM_REQUEST_MAX_CONCURRENCY);
        for _ in 0..REMOTE_LLM_REQUEST_MAX_CONCURRENCY {
            guards.push(acquire_remote_llm_request_slot());
        }

        let (tx, rx) = mpsc::channel::<()>();
        let handle = std::thread::spawn(move || {
            let _guard = acquire_remote_llm_request_slot();
            let _ = tx.send(());
        });

        assert!(
            rx.recv_timeout(Duration::from_millis(80)).is_err(),
            "extra request should block while all slots are occupied"
        );

        drop(guards);

        rx.recv_timeout(Duration::from_secs(2))
            .expect("request should proceed after releasing slots");
        handle.join().expect("thread join");
    }
}
