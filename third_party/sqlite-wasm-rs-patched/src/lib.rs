#![doc = include_str!("../README.md")]
#![no_std]
#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]
extern crate alloc;
#[rustfmt::skip]
#[allow(clippy::type_complexity)]
mod bindings;

#[cfg(target_family = "wasm")]
mod shim;

/// Raw C-style bindings to the underlying `libsqlite3` library.
pub use bindings::*;

#[cfg(target_family = "wasm")]
pub use self::shim::WasmOsCallback;
