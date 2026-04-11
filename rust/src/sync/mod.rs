// This module is split into smaller files to keep each file under ~1000 lines.
// The pieces are `include!`'d so everything remains in `crate::sync`.

pub mod blob_repair;
pub mod localdir;
pub mod managed_vault;
pub mod recovery_key;
pub mod webdav;
pub mod webdav_manifest;

include!("parts/01_prelude.rs");
include!("parts/02_push.rs");
include!("parts/02_media_blobs.rs");
include!("parts/03_pull.rs");
include!("parts/04_apply_core.rs");
include!("parts/05_apply_messages_and_attachments.rs");
include!("parts/06_apply_attachment_metadata.rs");
