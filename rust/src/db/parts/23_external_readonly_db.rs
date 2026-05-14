fn external_readonly_root_dir(app_dir: &Path) -> PathBuf {
    app_dir.join("external_readonly")
}

fn external_readonly_db_path(app_dir: &Path) -> PathBuf {
    external_readonly_root_dir(app_dir).join("external_readonly.sqlite3")
}

fn external_readonly_storage_dir(app_dir: &Path) -> PathBuf {
    external_readonly_root_dir(app_dir).join("storage")
}

fn external_readonly_dir_has_entries(path: &Path) -> Result<bool> {
    match fs::read_dir(path) {
        Ok(mut entries) => Ok(entries.next().is_some()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(e) => Err(e.into()),
    }
}

fn external_readonly_table_has_rows(conn: &Connection, table: &str) -> Result<bool> {
    if !sqlite_table_exists(conn, table)? {
        return Ok(false);
    }
    let sql = format!("SELECT 1 FROM {table} LIMIT 1");
    Ok(conn
        .query_row(&sql, [], |_row| Ok(()))
        .optional()?
        .is_some())
}

pub(crate) fn external_readonly_has_user_data(app_dir: &Path) -> Result<bool> {
    if external_readonly_dir_has_entries(&external_readonly_storage_dir(app_dir))? {
        return Ok(true);
    }

    let db_path = external_readonly_db_path(app_dir);
    if !db_path.exists() {
        return Ok(false);
    }
    let conn = Connection::open(db_path)?;
    for table in [
        "external_import_batches",
        "external_documents",
        "external_document_chunks",
        "external_attachments",
    ] {
        if external_readonly_table_has_rows(&conn, table)? {
            return Ok(true);
        }
    }
    Ok(false)
}

pub(crate) fn remove_external_readonly_data(app_dir: &Path) -> Result<()> {
    best_effort_remove_dir_all(&external_readonly_root_dir(app_dir))
}
