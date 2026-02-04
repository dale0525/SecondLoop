// This module is split into smaller files to keep each file under ~1000 lines.
// The pieces are `include!`'d so everything remains in `crate::sync`.

pub mod localdir;
pub mod managed_vault;
pub mod webdav;

include!("parts/01_prelude.rs");
include!("parts/02_push.rs");
include!("parts/03_pull.rs");
include!("parts/04_apply_core.rs");
include!("parts/05_apply_messages_and_attachments.rs");
