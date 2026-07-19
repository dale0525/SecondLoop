use jni::{
    JNIEnv,
    objects::{JByteArray, JObject, JString},
    sys::{jlong, jstring},
};
use serde_json::json;
use zeroize::Zeroize;

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_agentweave_mobile_runtime_NativeIdentity_nativeInitializeIdentity(
    mut env: JNIEnv,
    _receiver: JObject,
    request_json: JString,
    master_key: JByteArray,
) -> jstring {
    let output = (|| {
        let request = java_string(&mut env, &request_json)?;
        let mut key = env.convert_byte_array(&master_key)?;
        let result = crate::initialize_identity_runtime_json(&request, &key);
        key.zeroize();
        Ok(result)
    })()
    .unwrap_or_else(jni_error_json);
    new_java_string(&mut env, output)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_agentweave_mobile_runtime_NativeIdentity_nativeInvokeIdentity(
    mut env: JNIEnv,
    _receiver: JObject,
    handle: jlong,
    request_json: JString,
) -> jstring {
    let output = java_string(&mut env, &request_json)
        .map(|request| crate::invoke_identity_runtime_json(handle, &request))
        .unwrap_or_else(jni_error_json);
    new_java_string(&mut env, output)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_agentweave_mobile_runtime_NativeIdentity_nativeCloseIdentity(
    mut env: JNIEnv,
    _receiver: JObject,
    handle: jlong,
) -> jstring {
    new_java_string(&mut env, crate::close_identity_runtime(handle))
}

fn java_string(env: &mut JNIEnv, value: &JString) -> anyhow::Result<String> {
    Ok(env.get_string(value)?.into())
}

fn new_java_string(env: &mut JNIEnv, value: String) -> jstring {
    env.new_string(value)
        .map(|value| value.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

fn jni_error_json(error: anyhow::Error) -> String {
    let _ = error;
    json!({
        "ok": false,
        "error": {
            "code": "identity_jni_error",
            "message": "Identity native bridge failed",
        }
    })
    .to_string()
}
