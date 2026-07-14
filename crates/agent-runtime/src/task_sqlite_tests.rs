use super::*;
use crate::storage::Storage;
use crate::tasks::TaskPriority;
use chrono::Duration;

fn scope(user: &str) -> TaskScope {
    TaskScope::new("com.example.tasks", "local", user).unwrap()
}

fn content(title: &str, due_at: Option<DateTime<Utc>>) -> TaskContent {
    TaskContent {
        title: title.into(),
        notes: Some(format!("Notes for {title}")),
        due_at,
        timezone: due_at.map(|_| "Asia/Shanghai".into()),
        recurrence: None,
        priority: TaskPriority::Normal,
        tags: vec!["work".into()],
    }
}

fn query(limit: usize) -> TaskQuery {
    TaskQuery {
        status: None,
        due_after: None,
        due_before: None,
        tag: None,
        text: None,
        cursor: None,
        limit,
    }
}

#[tokio::test]
async fn sqlite_tasks_survive_restart_and_enforce_idempotency_content() {
    let directory = tempfile::tempdir().unwrap();
    let database = directory.path().join("tasks.db");
    let url = format!("sqlite://{}?mode=rwc", database.display());
    let storage = Storage::connect(&url).await.unwrap();
    let provider = storage.local_task_provider();
    provider.initialize().await.unwrap();
    let first = provider
        .create(&scope("user"), content("Prepare brief", None), "create-1")
        .await
        .unwrap();
    let repeated = provider
        .create(&scope("user"), content("Prepare brief", None), "create-1")
        .await
        .unwrap();
    assert_eq!(first.id, repeated.id);
    assert_eq!(
        provider
            .create(&scope("user"), content("Different", None), "create-1")
            .await
            .unwrap_err(),
        TaskError::IdempotencyConflict,
    );
    storage.close().await;

    let reopened = Storage::connect(&url).await.unwrap();
    let provider = reopened.local_task_provider();
    provider.initialize().await.unwrap();
    assert_eq!(
        provider
            .get(&scope("user"), &first.id)
            .await
            .unwrap()
            .unwrap()
            .content
            .title,
        "Prepare brief",
    );
    assert!(
        provider
            .get(&scope("other"), &first.id)
            .await
            .unwrap()
            .is_none()
    );
}

#[tokio::test]
async fn sqlite_tasks_page_due_ranges_and_preserve_versions() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let provider = storage.local_task_provider();
    provider.initialize().await.unwrap();
    let now = Utc::now();
    for (index, hours) in [1, 2, 3].into_iter().enumerate() {
        provider
            .create(
                &scope("user"),
                content(&format!("Task {index}"), Some(now + Duration::hours(hours))),
                &format!("create-{index}"),
            )
            .await
            .unwrap();
    }

    let mut first_query = query(2);
    first_query.due_after = Some(now);
    first_query.due_before = Some(now + Duration::hours(4));
    let first = provider.list(&scope("user"), first_query).await.unwrap();
    assert_eq!(first.tasks.len(), 2);
    assert!(first.next_cursor.is_some());
    let mut second_query = query(2);
    second_query.cursor = first.next_cursor;
    let second = provider.list(&scope("user"), second_query).await.unwrap();
    assert_eq!(second.tasks.len(), 1);
    assert!(second.next_cursor.is_none());

    let task = &first.tasks[0];
    let completed = provider
        .set_status(&scope("user"), &task.id, 1, TaskStatus::Completed)
        .await
        .unwrap();
    assert_eq!(completed.version, 2);
    assert!(completed.completed_at.is_some());
    assert_eq!(
        provider
            .update(&scope("user"), &task.id, 1, content("Stale update", None),)
            .await
            .unwrap_err(),
        TaskError::VersionConflict,
    );
    assert!(provider.delete(&scope("user"), &task.id, 2).await.unwrap());
    assert!(
        provider
            .get(&scope("user"), &task.id)
            .await
            .unwrap()
            .is_none()
    );
    let recreated = provider
        .create(
            &scope("user"),
            content("Recreated", Some(now + Duration::hours(1))),
            "create-0",
        )
        .await
        .unwrap();
    assert_ne!(recreated.id, task.id);
}
