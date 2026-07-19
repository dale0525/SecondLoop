package com.agentweave.mobile.runtime

interface NativeIdentityApi {
  fun initialize(requestJson: String, masterKey: ByteArray): String

  fun invoke(handle: Long, requestJson: String): String

  fun close(handle: Long): String
}

object NativeIdentity : NativeIdentityApi {
  init {
    System.loadLibrary("mobile_ffi")
  }

  override fun initialize(requestJson: String, masterKey: ByteArray): String =
    nativeInitializeIdentity(requestJson, masterKey)

  override fun invoke(handle: Long, requestJson: String): String =
    nativeInvokeIdentity(handle, requestJson)

  override fun close(handle: Long): String = nativeCloseIdentity(handle)

  private external fun nativeInitializeIdentity(requestJson: String, masterKey: ByteArray): String

  private external fun nativeInvokeIdentity(handle: Long, requestJson: String): String

  private external fun nativeCloseIdentity(handle: Long): String
}
