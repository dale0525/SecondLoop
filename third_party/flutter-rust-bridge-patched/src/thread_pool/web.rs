use crate::web_transfer::transfer_closure::TransferClosure;
use std::thread::LocalKey;
use wasm_bindgen::JsValue;
use wasm_bindgen_futures::spawn_local;

#[derive(Debug, Default)]
pub struct SimpleThreadPool;

pub trait BaseThreadPool {
    fn execute(&self, closure: TransferClosure<JsValue>);
}

impl BaseThreadPool for &'static LocalKey<SimpleThreadPool> {
    fn execute(&self, closure: TransferClosure<JsValue>) {
        let TransferClosure {
            data,
            transfer: _transfer,
            closure,
        } = closure;
        spawn_local(async move {
            closure(&data);
        });
    }
}
