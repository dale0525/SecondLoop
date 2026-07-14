use super::*;

fn scope(user: &str) -> TaskScope {
    TaskScope {
        app_id: "com.example.app".into(),
        tenant_id: "local".into(),
        user_id: user.into(),
    }
}
fn content(title: &str) -> TaskContent {
    TaskContent {
        title: title.into(),
        notes: None,
        due_at: None,
        timezone: None,
        recurrence: None,
        priority: TaskPriority::Normal,
        tags: vec!["work".into()],
    }
}

#[tokio::test]
async fn task_provider_is_scoped_idempotent_and_versioned() {
    let provider = FakeTaskProvider::default();
    let first = provider
        .create(&scope("user"), content("Prepare brief"), "task-1")
        .await
        .unwrap();
    let repeated = provider
        .create(&scope("user"), content("Prepare brief"), "task-1")
        .await
        .unwrap();
    assert_eq!(first.id, repeated.id);
    assert!(
        provider
            .list(
                &scope("other"),
                TaskQuery {
                    status: None,
                    due_after: None,
                    due_before: None,
                    tag: None,
                    text: None,
                    cursor: None,
                    limit: 10
                }
            )
            .await
            .unwrap()
            .tasks
            .is_empty()
    );
    let completed = provider
        .set_status(&scope("user"), &first.id, 1, TaskStatus::Completed)
        .await
        .unwrap();
    assert_eq!(completed.version, 2);
    assert!(completed.completed_at.is_some());
    assert!(
        provider
            .update(&scope("user"), &first.id, 1, content("Stale"))
            .await
            .unwrap_err()
            .to_string()
            .contains("version")
    );
}

#[tokio::test]
async fn task_provider_rejects_idempotency_conflicts_and_pages_stably() {
    let provider = FakeTaskProvider::default();
    let first = provider
        .create(&scope("user"), content("First"), "task-1")
        .await
        .unwrap();
    assert_eq!(
        provider
            .create(&scope("user"), content("Different"), "task-1")
            .await
            .unwrap_err(),
        TaskError::IdempotencyConflict
    );
    provider
        .create(&scope("user"), content("Second"), "task-2")
        .await
        .unwrap();

    let first_page = provider
        .list(
            &scope("user"),
            TaskQuery {
                status: None,
                due_after: None,
                due_before: None,
                tag: None,
                text: None,
                cursor: None,
                limit: 1,
            },
        )
        .await
        .unwrap();
    assert_eq!(first_page.tasks.len(), 1);
    let second_page = provider
        .list(
            &scope("user"),
            TaskQuery {
                status: None,
                due_after: None,
                due_before: None,
                tag: None,
                text: None,
                cursor: first_page.next_cursor,
                limit: 1,
            },
        )
        .await
        .unwrap();
    assert_eq!(second_page.tasks.len(), 1);
    assert_ne!(first_page.tasks[0].id, second_page.tasks[0].id);
    assert!(second_page.next_cursor.is_none());

    provider.delete(&scope("user"), &first.id, 1).await.unwrap();
    let recreated = provider
        .create(&scope("user"), content("Different"), "task-1")
        .await
        .unwrap();
    assert_ne!(first.id, recreated.id);
}

#[test]
fn recurrence_requires_due_time_and_valid_timezone() {
    let mut value = content("Recurring");
    value.recurrence = Some("FREQ=DAILY".into());
    assert!(value.validate().is_err());
    value.due_at = Some(Utc::now());
    value.timezone = Some("Asia/Shanghai".into());
    value.validate().unwrap();
}
