use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[path = "support/managed_vault_v2_test_server.rs"]
mod managed_vault_v2_test_server;

use managed_vault_v2_test_server::start_mock_v2_server;

fn bench_ops_target(default_ops: usize) -> usize {
    std::env::var("SYNC_BENCH_OPS")
        .ok()
        .and_then(|value| value.trim().parse::<usize>().ok())
        .filter(|value| *value > 0)
        .unwrap_or(default_ops)
}

fn request_body_json(request: &str) -> serde_json::Value {
    let (_, body) = request
        .split_once("\r\n\r\n")
        .expect("http request should contain headers");
    serde_json::from_str(body).expect("request body json")
}

#[test]
fn managed_vault_push_ops_only_splits_large_payload_into_v2_batches() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop_a");
    let key = auth::init_master_password(&app_dir, "pw-a", KdfParams::for_test()).expect("init A");
    let conn = db::open(&app_dir).expect("open A db");

    let total_ops = bench_ops_target(1010);
    for i in 0..total_ops {
        let title = format!("Conversation {i}");
        let _ = db::create_conversation(&conn, &key, &title).expect("create conversation");
    }

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push");
    assert_eq!(pushed, total_ops as u64);

    let requests = state.lock().expect("lock").requests.clone();
    let push_requests: Vec<serde_json::Value> = requests
        .iter()
        .filter(|request| request.starts_with("POST /v2/vaults/v1/sync/push "))
        .map(|request| request_body_json(request))
        .collect();

    let expected_push_calls = total_ops.div_ceil(500);
    assert_eq!(
        push_requests.len(),
        expected_push_calls,
        "expected push calls to follow v2 batch size cap"
    );

    let max_ops_per_push = push_requests
        .iter()
        .map(|payload| {
            payload["ops"]
                .as_array()
                .map(Vec::len)
                .expect("ops array in push payload")
        })
        .max()
        .unwrap_or(0);
    assert!(
        max_ops_per_push <= 500,
        "expected each v2 push request to be capped"
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}
