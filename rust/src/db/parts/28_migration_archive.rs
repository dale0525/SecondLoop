fn migration_archive_root_dir(app_dir: &Path) -> PathBuf {
    app_dir.join("migration_archive")
}

fn migration_archive_staging_dir(app_dir: &Path) -> PathBuf {
    migration_archive_root_dir(app_dir).join("staging")
}
