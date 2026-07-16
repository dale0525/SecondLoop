use crate::platform::PlatformId;
use crate::skill_bundle::{
    BuildSkillBundleRequest, BundleSkillSource, build_skill_bundle, build_skill_bundle_with_faults,
    gate_bundle_after_current_commit, gate_bundle_after_final_validation,
    gate_bundle_before_publish, gate_bundle_current_after_read, gate_bundle_discovery_after_layout,
};
use crate::skill_source::SkillSource;
use crate::skill_store_faults::{StoreFaultPoint, StoreFaults};
use semver::Version;
use std::io::{Seek, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

const TEST_TIMEOUT: Duration = Duration::from_secs(10);

#[cfg(unix)]
#[tokio::test]
async fn generation_replacement_after_final_validation_returns_error_with_previous_lkg() {
    let fixture = FinalReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let old = selected_package(&fixture.output).await;
    let original_current = read_current(&fixture.output).await;
    fixture.write_runtime("new").await;

    let gate = gate_bundle_after_final_validation(&fixture.output);
    let request = fixture.request();
    let publishing = tokio::spawn(async move { build_skill_bundle(request).await });
    let generation = gate.wait_entered().await;
    let displaced = generation.with_file_name(uuid::Uuid::new_v4().to_string());
    make_directory_replaceable(&generation).await;
    tokio::fs::rename(&generation, &displaced).await.unwrap();
    tokio::fs::create_dir(&generation).await.unwrap();
    tokio::fs::write(generation.join("attacker"), "replacement")
        .await
        .unwrap();
    gate.release().await;
    let error = publishing.await.unwrap().unwrap_err();
    assert!(format!("{error:#}").contains("expected active generation"));

    let current = read_current(&fixture.output).await;
    assert_ne!(current, original_current);
    assert_eq!(current["previous"], original_current["active"]);
    let selected = selected_package(&fixture.output).await;
    assert_eq!(selected, old);
    assert_eq!(
        selected.root,
        committed_package_root(&fixture.output, &current["previous"]).await
    );
}

#[cfg(unix)]
#[tokio::test]
async fn preopened_writer_after_final_validation_returns_error_with_previous_lkg() {
    let fixture = FinalReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let old = selected_package(&fixture.output).await;
    let original_current = read_current(&fixture.output).await;
    fixture.write_runtime("new").await;

    let before = gate_bundle_before_publish(&fixture.output);
    let final_gate = gate_bundle_after_final_validation(&fixture.output);
    let request = fixture.request();
    let publishing = tokio::spawn(async move { build_skill_bundle(request).await });
    let generation = before.wait_entered().await;
    let path = generation.join("com.example.final/index.js");
    let mut writer = std::fs::OpenOptions::new().write(true).open(&path).unwrap();
    before.release().await;
    final_gate.wait_entered().await;
    writer.seek(std::io::SeekFrom::Start(0)).unwrap();
    writer.write_all(b"tampered-after-validation\n").unwrap();
    writer.set_len(26).unwrap();
    writer.sync_all().unwrap();
    final_gate.release().await;
    let error = publishing.await.unwrap().unwrap_err();
    assert!(format!("{error:#}").contains("expected active generation"));

    let current = read_current(&fixture.output).await;
    assert_ne!(current, original_current);
    assert_eq!(current["previous"], original_current["active"]);
    let selected = selected_package(&fixture.output).await;
    assert_eq!(selected, old);
    assert_eq!(
        selected.root,
        committed_package_root(&fixture.output, &current["previous"]).await
    );
}

#[cfg(unix)]
#[tokio::test]
async fn first_publication_generation_replacement_returns_error_without_authoritative_current() {
    let fixture = FinalReviewFixture::new().await;
    let gate = gate_bundle_after_final_validation(&fixture.output);
    let request = fixture.request();
    let publishing = tokio::spawn(async move { build_skill_bundle(request).await });
    let generation = gate.wait_entered().await;
    let displaced = generation.with_file_name(uuid::Uuid::new_v4().to_string());
    make_directory_replaceable(&generation).await;
    tokio::fs::rename(&generation, &displaced).await.unwrap();
    tokio::fs::create_dir(&generation).await.unwrap();
    tokio::fs::write(generation.join("attacker"), "replacement")
        .await
        .unwrap();
    gate.release().await;

    let error = publishing.await.unwrap().unwrap_err();
    assert!(format!("{error:#}").contains("first bundle publication"));
    assert_no_authoritative_current(&fixture.output).await;
}

#[cfg(unix)]
#[tokio::test]
async fn first_publication_preopened_writer_returns_error_without_authoritative_current() {
    let fixture = FinalReviewFixture::new().await;
    let before = gate_bundle_before_publish(&fixture.output);
    let final_gate = gate_bundle_after_final_validation(&fixture.output);
    let request = fixture.request();
    let publishing = tokio::spawn(async move { build_skill_bundle(request).await });
    let generation = before.wait_entered().await;
    let path = generation.join("com.example.final/index.js");
    let mut writer = std::fs::OpenOptions::new().write(true).open(&path).unwrap();
    before.release().await;
    final_gate.wait_entered().await;
    writer.seek(std::io::SeekFrom::Start(0)).unwrap();
    writer.write_all(b"tampered-after-validation\n").unwrap();
    writer.set_len(26).unwrap();
    writer.sync_all().unwrap();
    final_gate.release().await;

    let error = publishing.await.unwrap().unwrap_err();
    assert!(format!("{error:#}").contains("first bundle publication"));
    assert_no_authoritative_current(&fixture.output).await;
}

#[tokio::test]
async fn first_publication_neutralization_preserves_concurrently_replaced_current() {
    let fixture = FinalReviewFixture::new().await;
    let gate = gate_bundle_after_current_commit(&fixture.output);
    let request = fixture.request();
    let publishing = tokio::spawn(async move { build_skill_bundle(request).await });
    gate.wait_entered().await;
    let attacker = b"{\"external\":true}\n";
    let replacement = fixture.output.join("external-current");
    tokio::fs::write(&replacement, attacker).await.unwrap();
    tokio::fs::rename(&replacement, fixture.output.join("current"))
        .await
        .unwrap();
    gate.release().await;

    let error = publishing.await.unwrap().unwrap_err();
    assert!(format!("{error:#}").contains("first bundle publication"));
    assert_eq!(
        tokio::fs::read(fixture.output.join("current"))
            .await
            .unwrap(),
        attacker
    );
}

#[tokio::test]
async fn successful_first_publication_is_immediately_readable_with_expected_bytes() {
    let fixture = FinalReviewFixture::new().await;
    let result = build_skill_bundle(fixture.request()).await.unwrap();
    let current = read_current(&fixture.output).await;
    let selected = selected_package(&fixture.output).await;

    assert_eq!(result.package_count, 1);
    assert_eq!(selected.content, "old\n");
    assert_eq!(
        selected.root,
        committed_package_root(&fixture.output, &current["active"]).await
    );
    assert_eq!(
        selected.hash,
        serde_json::from_slice::<serde_json::Value>(&result.manifest_bytes).unwrap()["packages"][0]
            ["contentHash"]
            .as_str()
            .unwrap()
    );
}

#[tokio::test]
async fn successful_commit_and_later_current_mutation_are_distinct_events() {
    let fixture = FinalReviewFixture::new().await;
    let result = build_skill_bundle(fixture.request()).await.unwrap();
    assert_eq!(result.package_count, 1);

    tokio::fs::write(fixture.output.join("current"), b"{\"external\":true}\n")
        .await
        .unwrap();

    let error = BundleSkillSource::open(&fixture.output).await.unwrap_err();
    assert!(format!("{error:#}").contains("current"));
}

#[tokio::test]
async fn mutation_after_final_marker_read_is_post_commit_and_later_load_fails_closed() {
    let fixture = FinalReviewFixture::new().await;
    let canonical_parent = tokio::fs::canonicalize(fixture.output.parent().unwrap())
        .await
        .unwrap();
    let gate = gate_bundle_current_after_read(&canonical_parent.join("bundle/current"), 1);
    let request = fixture.request();
    let publishing = tokio::spawn(async move { build_skill_bundle(request).await });
    gate.wait_entered().await;
    tokio::fs::write(fixture.output.join("current"), b"{\"external\":true}\n")
        .await
        .unwrap();
    gate.release().await;

    publishing.await.unwrap().unwrap();
    let error = BundleSkillSource::open(&fixture.output).await.unwrap_err();
    assert!(format!("{error:#}").contains("current"));
}

#[tokio::test]
async fn cooperating_builders_serialize_before_output_prepare() {
    let fixture = FinalReviewFixture::new().await;
    let first_faults = StoreFaults::default();
    let first_acquired = first_faults.gate_once(StoreFaultPoint::BundlePublisherLockAcquired);
    let first_request = fixture.request();
    let first =
        tokio::spawn(
            async move { build_skill_bundle_with_faults(first_request, first_faults).await },
        );
    first_acquired.wait_entered().await;

    let second_faults = StoreFaults::default();
    let second_attempt = second_faults.gate_once(StoreFaultPoint::BundlePublisherLockAttempt);
    let second_acquired = second_faults.gate_once(StoreFaultPoint::BundlePublisherLockAcquired);
    let second_request = fixture.request();
    let second =
        tokio::spawn(
            async move { build_skill_bundle_with_faults(second_request, second_faults).await },
        );
    second_attempt.wait_entered().await;
    second_attempt.release().await;
    tokio::time::sleep(Duration::from_millis(100)).await;

    assert!(!second_acquired.has_entered());
    assert!(
        !fixture.output.exists(),
        "second builder prepared output without the lock"
    );

    first_acquired.release().await;
    first.await.unwrap().unwrap();
    second_acquired.wait_entered().await;
    assert_eq!(generation_count(&fixture.output).await, 1);
    second_acquired.release().await;
    second.await.unwrap().unwrap();

    assert_eq!(generation_count(&fixture.output).await, 2);
    let current = read_current(&fixture.output).await;
    assert!(current["previous"].is_object());
}

#[tokio::test]
async fn subprocess_builders_publish_in_lock_order_without_output_collision() {
    let fixture = FinalReviewFixture::new().await;
    let marker = fixture.source.with_file_name("first.locked");
    let release = fixture.source.with_file_name("first.release");
    let first_result = fixture.source.with_file_name("first.result");
    let second_attempt = fixture.source.with_file_name("second.attempt");
    let second_acquired = fixture.source.with_file_name("second.acquired");
    let second_result = fixture.source.with_file_name("second.result");
    let alias = fixture.output.with_file_name("Bundle");
    let case_alias = if filesystem_is_case_insensitive(fixture.output.parent().unwrap()).await {
        alias.as_path()
    } else {
        fixture.output.as_path()
    };
    let mut first = spawn_bundle_builder_helper(
        &fixture.source,
        case_alias,
        &first_result,
        Some((&marker, &release)),
        None,
    );
    wait_for_path(&marker).await;
    let mut second = spawn_bundle_builder_helper(
        &fixture.source,
        &fixture.output,
        &second_result,
        None,
        Some((&second_attempt, &second_acquired)),
    );
    wait_for_path(&second_attempt).await;

    assert!(!second_acquired.exists());
    assert!(!second_result.exists());
    assert!(!fixture.output.exists());

    tokio::fs::write(&release, b"go").await.unwrap();
    wait_for_path(&first_result).await;
    wait_for_path(&second_acquired).await;
    wait_for_path(&second_result).await;
    assert!(first.wait().unwrap().success());
    assert!(second.wait().unwrap().success());
    assert_eq!(tokio::fs::read_to_string(first_result).await.unwrap(), "ok");
    assert_eq!(
        tokio::fs::read_to_string(second_result).await.unwrap(),
        "ok"
    );
    assert_eq!(generation_count(&fixture.output).await, 2);
}

#[tokio::test]
async fn subprocess_lock_is_attempted_before_source_canonicalization() {
    let fixture = FinalReviewFixture::new().await;
    let first_locked = fixture.source.with_file_name("scope-first.locked");
    let first_release = fixture.source.with_file_name("scope-first.release");
    let first_result = fixture.source.with_file_name("scope-first.result");
    let second_attempt = fixture.source.with_file_name("scope-second.attempt");
    let second_acquired = fixture.source.with_file_name("scope-second.acquired");
    let second_result = fixture.source.with_file_name("scope-second.result");
    let missing_source = fixture.source.with_file_name("missing-source");
    let mut first = spawn_bundle_builder_helper(
        &fixture.source,
        &fixture.output,
        &first_result,
        Some((&first_locked, &first_release)),
        None,
    );
    wait_for_path(&first_locked).await;
    let mut second = spawn_bundle_builder_helper(
        &missing_source,
        &fixture.output,
        &second_result,
        None,
        Some((&second_attempt, &second_acquired)),
    );
    wait_for_path(&second_attempt).await;

    assert!(!second_acquired.exists());
    assert!(!second_result.exists());

    tokio::fs::write(&first_release, b"go").await.unwrap();
    wait_for_path(&first_result).await;
    wait_for_path(&second_acquired).await;
    wait_for_path(&second_result).await;
    assert!(first.wait().unwrap().success());
    assert!(second.wait().unwrap().success());
    assert_eq!(tokio::fs::read_to_string(first_result).await.unwrap(), "ok");
    let error = tokio::fs::read_to_string(second_result).await.unwrap();
    assert!(error.starts_with("error:"));
    assert!(error.contains("source root"));
}

#[test]
#[ignore]
fn subprocess_bundle_builder_helper() {
    let source = std::env::var_os("AGENTWEAVE_TEST_BUNDLE_SOURCE").unwrap();
    let output = std::env::var_os("AGENTWEAVE_TEST_BUNDLE_OUTPUT").unwrap();
    let result = std::env::var_os("AGENTWEAVE_TEST_BUNDLE_RESULT").unwrap();
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let build = runtime.block_on(build_skill_bundle(BuildSkillBundleRequest {
        source_roots: vec![PathBuf::from(source)],
        output_root: PathBuf::from(output),
        platform: PlatformId::Desktop,
        runtime_version: Version::new(0, 1, 0),
        generated_at: "2026-07-12T00:00:00Z".into(),
    }));
    let value = build
        .map(|_| "ok".to_string())
        .unwrap_or_else(|error| format!("error:{error:#}"));
    std::fs::write(result, value).unwrap();
}

#[cfg(unix)]
#[tokio::test]
async fn committed_generation_replacement_falls_back_to_explicit_previous_generation() {
    let fixture = FinalReviewFixture::new().await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let old = selected_package(&fixture.output).await;
    fixture.write_runtime("new").await;
    build_skill_bundle(fixture.request()).await.unwrap();
    let current = read_current(&fixture.output).await;
    let active = fixture
        .output
        .join("generations")
        .join(current["active"]["generation"].as_str().unwrap());
    let displaced = active.with_file_name(uuid::Uuid::new_v4().to_string());
    make_directory_replaceable(&active).await;
    tokio::fs::rename(&active, &displaced).await.unwrap();
    tokio::fs::create_dir(&active).await.unwrap();
    tokio::fs::write(active.join("attacker"), "replacement")
        .await
        .unwrap();

    let selected = selected_package(&fixture.output).await;

    assert_eq!(selected, old);
    let expected = tokio::fs::canonicalize(
        fixture
            .output
            .join("generations")
            .join(current["previous"]["generation"].as_str().unwrap())
            .join("com.example.final"),
    )
    .await
    .unwrap();
    assert_eq!(selected.root, expected);
}

#[tokio::test]
async fn first_build_reservation_failure_is_immediately_retryable() {
    assert_first_build_retry(StoreFaultPoint::BundleBeforeGenerationReservation).await;
}

#[tokio::test]
async fn first_build_copy_failure_is_immediately_retryable() {
    assert_first_build_retry(StoreFaultPoint::StagingCopyFile).await;
}

#[tokio::test]
async fn first_build_precommit_failure_is_immediately_retryable() {
    assert_first_build_retry(StoreFaultPoint::BundleBeforePublish).await;
}

#[tokio::test]
async fn generations_cleanup_preserves_foreign_generation_created_after_empty_observation() {
    let fixture = FinalReviewFixture::new().await;
    let faults = StoreFaults::default();
    faults.fail_once(StoreFaultPoint::BundleBeforeGenerationReservation);
    let gate = faults.gate_once(StoreFaultPoint::BundleBeforeGenerationsCleanup);
    let request = fixture.request();
    let publishing =
        tokio::spawn(async move { build_skill_bundle_with_faults(request, faults).await });
    gate.wait_entered().await;
    let foreign_id = uuid::Uuid::new_v4().to_string();
    let foreign = fixture.output.join("generations").join(&foreign_id);
    tokio::fs::create_dir(&foreign).await.unwrap();
    tokio::fs::write(foreign.join("foreign"), b"preserve me")
        .await
        .unwrap();
    gate.release().await;

    let error = publishing.await.unwrap().unwrap_err();
    let message = format!("{error:#}");
    assert!(message.contains("BundleBeforeGenerationReservation"));
    assert!(message.contains("empty generations bootstrap cleanup failed safely"));
    let quarantine = find_cleanup_quarantine(&fixture.output).await;
    assert!(message.contains(&quarantine.display().to_string()));
    assert_eq!(
        tokio::fs::read(quarantine.join(&foreign_id).join("foreign"))
            .await
            .unwrap(),
        b"preserve me"
    );
}

#[cfg(unix)]
#[tokio::test]
async fn generations_cleanup_preserves_empty_replacement_directory() {
    let fixture = FinalReviewFixture::new().await;
    let faults = StoreFaults::default();
    faults.fail_once(StoreFaultPoint::BundleBeforeGenerationReservation);
    let gate = faults.gate_once(StoreFaultPoint::BundleBeforeGenerationsCleanupMove);
    let request = fixture.request();
    let publishing =
        tokio::spawn(async move { build_skill_bundle_with_faults(request, faults).await });
    gate.wait_entered().await;
    let generations = fixture.output.join("generations");
    let displaced = fixture.output.join("owned-generations");
    tokio::fs::rename(&generations, &displaced).await.unwrap();
    tokio::fs::create_dir(&generations).await.unwrap();
    gate.release().await;

    let error = publishing.await.unwrap().unwrap_err();
    assert!(format!("{error:#}").contains("cleanup failed safely"));
    let quarantine = find_cleanup_quarantine(&fixture.output).await;
    assert!(
        quarantine.is_dir(),
        "foreign empty replacement evidence was removed"
    );
    assert!(format!("{error:#}").contains(&quarantine.display().to_string()));
    assert!(displaced.is_dir(), "owned bootstrap evidence was lost");
}

#[tokio::test]
async fn output_cleanup_preserves_foreign_file_created_after_empty_observation() {
    let fixture = FinalReviewFixture::new().await;
    let faults = StoreFaults::default();
    faults.fail_once(StoreFaultPoint::BundleBeforeGenerationReservation);
    let gate = faults.gate_once(StoreFaultPoint::BundleBeforeOutputCleanup);
    let request = fixture.request();
    let publishing =
        tokio::spawn(async move { build_skill_bundle_with_faults(request, faults).await });
    gate.wait_entered().await;
    let foreign = fixture.output.join("foreign");
    tokio::fs::write(&foreign, b"preserve me").await.unwrap();
    gate.release().await;

    let error = publishing.await.unwrap().unwrap_err();
    let message = format!("{error:#}");
    assert!(message.contains("BundleBeforeGenerationReservation"));
    assert!(message.contains("empty output bootstrap cleanup failed safely"));
    let quarantine = find_cleanup_quarantine(fixture.output.parent().unwrap()).await;
    assert!(message.contains(&quarantine.display().to_string()));
    assert_eq!(
        tokio::fs::read(quarantine.join("foreign")).await.unwrap(),
        b"preserve me"
    );
}

#[cfg(unix)]
#[tokio::test]
async fn output_cleanup_preserves_empty_replacement_directory() {
    let fixture = FinalReviewFixture::new().await;
    let faults = StoreFaults::default();
    faults.fail_once(StoreFaultPoint::BundleBeforeGenerationReservation);
    let gate = faults.gate_once(StoreFaultPoint::BundleBeforeOutputCleanupMove);
    let request = fixture.request();
    let publishing =
        tokio::spawn(async move { build_skill_bundle_with_faults(request, faults).await });
    gate.wait_entered().await;
    let displaced = fixture.output.with_file_name("owned-output");
    tokio::fs::rename(&fixture.output, &displaced)
        .await
        .unwrap();
    tokio::fs::create_dir(&fixture.output).await.unwrap();
    gate.release().await;

    let error = publishing.await.unwrap().unwrap_err();
    assert!(format!("{error:#}").contains("cleanup failed safely"));
    let quarantine = find_cleanup_quarantine(fixture.output.parent().unwrap()).await;
    assert!(
        quarantine.is_dir(),
        "foreign empty replacement evidence was removed"
    );
    assert!(format!("{error:#}").contains(&quarantine.display().to_string()));
    assert!(displaced.is_dir(), "owned bootstrap evidence was lost");
}

#[cfg(unix)]
#[tokio::test]
async fn generations_cleanup_preserves_foreign_empty_quarantine_replacement_before_delete() {
    let fixture = FinalReviewFixture::new().await;
    let faults = StoreFaults::default();
    faults.fail_once(StoreFaultPoint::BundleBeforeGenerationReservation);
    let gate = faults.gate_once(StoreFaultPoint::BundleBeforeGenerationsCleanupDelete);
    let request = fixture.request();
    let publishing =
        tokio::spawn(async move { build_skill_bundle_with_faults(request, faults).await });
    gate.wait_entered().await;

    let quarantine = find_cleanup_quarantine(&fixture.output).await;
    let owned_evidence = fixture.output.join("owned-generations-quarantine");
    tokio::fs::rename(&quarantine, &owned_evidence)
        .await
        .unwrap();
    tokio::fs::create_dir(&quarantine).await.unwrap();
    gate.release().await;

    let error = publishing.await.unwrap().unwrap_err();
    let message = format!("{error:#}");
    assert!(message.contains("cleanup quarantine identity changed before deletion"));
    assert!(message.contains(&quarantine.display().to_string()));
    assert!(
        quarantine.is_dir(),
        "foreign quarantine replacement was removed"
    );
    assert!(
        owned_evidence.is_dir(),
        "owned generations evidence was lost"
    );
}

#[cfg(unix)]
#[tokio::test]
async fn output_cleanup_preserves_foreign_empty_quarantine_replacement_before_delete() {
    let fixture = FinalReviewFixture::new().await;
    let faults = StoreFaults::default();
    faults.fail_once(StoreFaultPoint::BundleBeforeGenerationReservation);
    let gate = faults.gate_once(StoreFaultPoint::BundleBeforeOutputCleanupDelete);
    let request = fixture.request();
    let publishing =
        tokio::spawn(async move { build_skill_bundle_with_faults(request, faults).await });
    gate.wait_entered().await;

    let parent = fixture.output.parent().unwrap();
    let quarantine = find_cleanup_quarantine(parent).await;
    let owned_evidence = parent.join("owned-output-quarantine");
    tokio::fs::rename(&quarantine, &owned_evidence)
        .await
        .unwrap();
    tokio::fs::create_dir(&quarantine).await.unwrap();
    gate.release().await;

    let error = publishing.await.unwrap().unwrap_err();
    let message = format!("{error:#}");
    assert!(message.contains("cleanup quarantine identity changed before deletion"));
    assert!(message.contains(&quarantine.display().to_string()));
    assert!(
        quarantine.is_dir(),
        "foreign quarantine replacement was removed"
    );
    assert!(owned_evidence.is_dir(), "owned output evidence was lost");
}

#[tokio::test]
async fn current_marker_schema_is_versioned_closed_and_committed() {
    let versioned = FinalReviewFixture::new().await;
    build_skill_bundle(versioned.request()).await.unwrap();
    let current = read_current(&versioned.output).await;
    assert_eq!(current["schemaVersion"], 2);
    assert_eq!(
        current["active"]["manifestSha256"].as_str().unwrap().len(),
        64
    );
    assert_eq!(current["active"]["lockSha256"].as_str().unwrap().len(), 64);
    assert!(current["previous"].is_null());

    let unknown = FinalReviewFixture::new().await;
    build_skill_bundle(unknown.request()).await.unwrap();
    let mut current = read_current(&unknown.output).await;
    current["unexpected"] = serde_json::json!(true);
    write_current(&unknown.output, &current).await;
    let error = BundleSkillSource::open(&unknown.output).await.unwrap_err();
    assert!(format!("{error:#}").contains("unknown field"));

    let unsupported = FinalReviewFixture::new().await;
    build_skill_bundle(unsupported.request()).await.unwrap();
    let mut current = read_current(&unsupported.output).await;
    current["schemaVersion"] = serde_json::json!(1);
    write_current(&unsupported.output, &current).await;
    let error = BundleSkillSource::open(&unsupported.output)
        .await
        .unwrap_err();
    assert!(format!("{error:#}").contains("current schema version"));
}

#[cfg(unix)]
#[tokio::test]
async fn independent_discovery_gates_are_path_keyed_and_bounded() {
    let first = FinalReviewFixture::new().await;
    let second = FinalReviewFixture::new().await;
    build_skill_bundle(first.request()).await.unwrap();
    build_skill_bundle(second.request()).await.unwrap();
    let first_generation = active_generation(&first.output).await;
    let second_generation = active_generation(&second.output).await;
    let first_source = BundleSkillSource::open(&first.output).await.unwrap();
    let second_source = BundleSkillSource::open(&second.output).await.unwrap();
    let first_gate = gate_bundle_discovery_after_layout(&first_generation);
    let second_gate = gate_bundle_discovery_after_layout(&second_generation);
    let first_reload = tokio::spawn(async move { first_source.discover().await });
    let second_reload = tokio::spawn(async move { second_source.discover().await });

    tokio::time::timeout(TEST_TIMEOUT, async {
        tokio::join!(first_gate.wait_entered(), second_gate.wait_entered());
    })
    .await
    .expect("independent discovery gates did not both enter");
    tokio::join!(first_gate.release(), second_gate.release());

    assert_eq!(first_reload.await.unwrap().unwrap().len(), 1);
    assert_eq!(second_reload.await.unwrap().unwrap().len(), 1);
}

async fn assert_first_build_retry(point: StoreFaultPoint) {
    let fixture = FinalReviewFixture::new().await;
    let faults = StoreFaults::default();
    faults.fail_once(point);

    build_skill_bundle_with_faults(fixture.request(), faults)
        .await
        .unwrap_err();

    assert!(
        !fixture.output.exists(),
        "failed bootstrap evidence remained"
    );
    build_skill_bundle(fixture.request()).await.unwrap();
    let package = selected_package(&fixture.output).await;
    assert_eq!(package.content, "old\n");
}

#[derive(Debug, PartialEq, Eq)]
struct SelectedPackage {
    root: PathBuf,
    hash: String,
    content: String,
}

async fn selected_package(output: &Path) -> SelectedPackage {
    let source = BundleSkillSource::open(output).await.unwrap();
    let package = source.packages().await.unwrap().remove(0);
    SelectedPackage {
        content: tokio::fs::read_to_string(package.root.join("index.js"))
            .await
            .unwrap(),
        root: package.root,
        hash: package.content_hash,
    }
}

async fn committed_package_root(output: &Path, commitment: &serde_json::Value) -> PathBuf {
    tokio::fs::canonicalize(
        output
            .join("generations")
            .join(commitment["generation"].as_str().unwrap())
            .join("com.example.final"),
    )
    .await
    .unwrap()
}

async fn assert_no_authoritative_current(output: &Path) {
    match tokio::fs::read(output.join("current")).await {
        Ok(bytes) => {
            assert!(
                bytes.is_empty(),
                "current marker was not precisely neutralized"
            );
            match BundleSkillSource::open(output).await {
                Ok(source) => assert!(source.packages().await.is_err()),
                Err(error) => assert!(format!("{error:#}").contains("current")),
            }
        }
        Err(error) => assert_eq!(error.kind(), std::io::ErrorKind::NotFound),
    }
}

async fn read_current(output: &Path) -> serde_json::Value {
    serde_json::from_slice(&tokio::fs::read(output.join("current")).await.unwrap()).unwrap()
}

async fn write_current(output: &Path, value: &serde_json::Value) {
    let mut bytes = serde_json::to_vec_pretty(value).unwrap();
    bytes.push(b'\n');
    tokio::fs::write(output.join("current"), bytes)
        .await
        .unwrap();
}

async fn active_generation(output: &Path) -> PathBuf {
    let current = read_current(output).await;
    tokio::fs::canonicalize(
        output
            .join("generations")
            .join(current["active"]["generation"].as_str().unwrap()),
    )
    .await
    .unwrap()
}

async fn generation_count(output: &Path) -> usize {
    let mut entries = tokio::fs::read_dir(output.join("generations"))
        .await
        .unwrap();
    let mut count = 0;
    while entries.next_entry().await.unwrap().is_some() {
        count += 1;
    }
    count
}

async fn find_cleanup_quarantine(parent: &Path) -> PathBuf {
    let mut entries = tokio::fs::read_dir(parent).await.unwrap();
    while let Some(entry) = entries.next_entry().await.unwrap() {
        if entry
            .file_name()
            .to_string_lossy()
            .starts_with(".skill-cleanup-quarantine-")
        {
            return entry.path();
        }
    }
    panic!("no cleanup quarantine found under {}", parent.display());
}

fn spawn_bundle_builder_helper(
    source: &Path,
    output: &Path,
    result: &Path,
    lock_gate: Option<(&Path, &Path)>,
    lock_markers: Option<(&Path, &Path)>,
) -> std::process::Child {
    let mut command = Command::new(std::env::current_exe().unwrap());
    command
        .arg("--ignored")
        .arg("--exact")
        .arg("skill_bundle_final_review_tests::subprocess_bundle_builder_helper")
        .arg("--nocapture")
        .env("AGENTWEAVE_TEST_BUNDLE_SOURCE", source)
        .env("AGENTWEAVE_TEST_BUNDLE_OUTPUT", output)
        .env("AGENTWEAVE_TEST_BUNDLE_RESULT", result)
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    if let Some((marker, release)) = lock_gate {
        command
            .env("AGENTWEAVE_TEST_BUNDLE_LOCK_MARKER", marker)
            .env("AGENTWEAVE_TEST_BUNDLE_LOCK_RELEASE", release);
    }
    if let Some((attempt, acquired)) = lock_markers {
        command
            .env("AGENTWEAVE_TEST_BUNDLE_LOCK_ATTEMPT", attempt)
            .env("AGENTWEAVE_TEST_BUNDLE_LOCK_ACQUIRED", acquired);
    }
    command.spawn().unwrap()
}

async fn filesystem_is_case_insensitive(parent: &Path) -> bool {
    let lower = parent.join(format!("case-probe-{}", uuid::Uuid::new_v4()));
    let upper = lower.with_file_name(lower.file_name().unwrap().to_string_lossy().to_uppercase());
    tokio::fs::write(&lower, b"probe").await.unwrap();
    let insensitive = upper.exists();
    tokio::fs::remove_file(lower).await.unwrap();
    insensitive
}

async fn wait_for_path(path: &Path) {
    tokio::time::timeout(TEST_TIMEOUT, async {
        while !path.exists() {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("timed out waiting for {}", path.display()));
}

async fn make_directory_replaceable(path: &Path) {
    for path in [path, path.parent().unwrap()] {
        let mut permissions = tokio::fs::metadata(path).await.unwrap().permissions();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            permissions.set_mode(permissions.mode() | 0o300);
        }
        #[cfg(not(unix))]
        permissions.set_readonly(false);
        tokio::fs::set_permissions(path, permissions).await.unwrap();
    }
}

struct FinalReviewFixture {
    _temp: tempfile::TempDir,
    source: PathBuf,
    output: PathBuf,
}

impl FinalReviewFixture {
    async fn new() -> Self {
        let temp = tempfile::tempdir().unwrap();
        let source = temp.path().join("source");
        let output = temp.path().join("bundle");
        write_package(&source.join("com.example.final")).await;
        Self {
            _temp: temp,
            source,
            output,
        }
    }

    fn request(&self) -> BuildSkillBundleRequest {
        BuildSkillBundleRequest {
            source_roots: vec![self.source.clone()],
            output_root: self.output.clone(),
            platform: PlatformId::Desktop,
            runtime_version: Version::new(0, 1, 0),
            generated_at: "2026-07-12T00:00:00Z".into(),
        }
    }

    async fn write_runtime(&self, content: &str) {
        tokio::fs::write(
            self.source.join("com.example.final/index.js"),
            format!("{content}\n"),
        )
        .await
        .unwrap();
    }
}

async fn write_package(root: &Path) {
    tokio::fs::create_dir_all(root).await.unwrap();
    tokio::fs::write(
        root.join("agentweave.json"),
        serde_json::json!({
            "schemaVersion": 1,
            "id": "com.example.final",
            "version": "0.1.0",
            "displayName": "Final",
            "kind": "native_runtime",
            "package": { "includeInstructions": false, "includeRuntime": true },
            "compatibility": { "platforms": ["desktop"] },
            "requires": {
                "packages": [], "capabilities": ["shell.process"],
                "runtimeTools": [], "connectors": []
            }
        })
        .to_string(),
    )
    .await
    .unwrap();
    tokio::fs::write(
        root.join("skill.json"),
        serde_json::json!({
            "name": "final", "description": "Final fixture.", "version": "0.1.0",
            "entry": { "type": "command", "command": "node", "args": ["index.js"] },
            "tools": [{ "name": "run", "description": "Run.", "input_schema": {"type":"object"} }]
        })
        .to_string(),
    )
    .await
    .unwrap();
    tokio::fs::write(root.join("index.js"), "old\n")
        .await
        .unwrap();
}
