use super::*;

fn sqlite_table_exists(conn: &Connection, table_name: &str) -> bool {
    conn.query_row(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
        params![table_name],
        |row| row.get::<_, i64>(0),
    )
    .optional()
    .expect("table lookup")
    .is_some()
}

fn sqlite_index_exists(conn: &Connection, index_name: &str) -> bool {
    conn.query_row(
        "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = ?1",
        params![index_name],
        |row| row.get::<_, i64>(0),
    )
    .optional()
    .expect("index lookup")
    .is_some()
}

#[test]
fn knowledge_schema_migration_creates_versioned_tables_and_indexes() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    for table_name in [
        "knowledge_documents",
        "knowledge_units",
        "knowledge_embeddings",
        "knowledge_index_jobs",
        "knowledge_rebuild_state",
    ] {
        assert!(
            sqlite_table_exists(&conn, table_name),
            "missing {table_name}"
        );
    }

    for index_name in [
        "idx_knowledge_documents_origin_updated",
        "idx_knowledge_units_document_parent_kind",
        "idx_knowledge_units_anchor_lookup",
        "idx_knowledge_embeddings_target",
        "idx_knowledge_index_jobs_status_due",
    ] {
        assert!(
            sqlite_index_exists(&conn, index_name),
            "missing {index_name}"
        );
    }
}

#[test]
fn knowledge_schema_migration_seeds_rebuild_policy_versions() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let row: (i64, i64, i64, i64, i64) = conn
        .query_row(
            r#"SELECT knowledge_schema_version,
                      normalization_version,
                      segmentation_version,
                      embedding_policy_version,
                      retrieval_policy_version
               FROM knowledge_rebuild_state
               WHERE state_key = 1"#,
            [],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                ))
            },
        )
        .expect("rebuild state row");

    assert_eq!(row, (1, 1, 1, 1, 1));
}
