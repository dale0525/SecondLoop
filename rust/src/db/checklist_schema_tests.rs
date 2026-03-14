use super::*;

#[test]
fn checklist_tables_exist_after_migration() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let mut stmt = conn
        .prepare(
            r#"SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('todo_checklist_items', 'todo_checklist_suggestions') ORDER BY name ASC"#,
        )
        .expect("prepare");
    let names = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query")
        .collect::<std::result::Result<Vec<_>, _>>()
        .expect("collect");

    assert_eq!(
        names,
        vec![
            "todo_checklist_items".to_string(),
            "todo_checklist_suggestions".to_string(),
        ]
    );
}

#[test]
fn checklist_tables_reference_todos_with_cascade_delete() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    for table_name in ["todo_checklist_items", "todo_checklist_suggestions"] {
        let pragma = format!("PRAGMA foreign_key_list({table_name})");
        let mut stmt = conn.prepare(&pragma).expect("prepare pragma");
        let foreign_keys = stmt
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, String>(6)?,
                ))
            })
            .expect("query")
            .collect::<std::result::Result<Vec<_>, _>>()
            .expect("collect");

        assert!(foreign_keys
            .iter()
            .any(|(referenced_table, from_column, on_delete)| {
                referenced_table == "todos"
                    && from_column == "todo_id"
                    && on_delete.eq_ignore_ascii_case("CASCADE")
            }));
    }
}
