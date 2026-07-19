package com.agentweave.mobile.secrets

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

interface ModelSecretStore {
  fun saveSecret(secretId: String, value: String)

  fun loadSecret(secretId: String): String?

  fun deleteSecret(secretId: String)
}

class ModelSecretStoreException(
  message: String,
  cause: Throwable? = null,
) : IllegalStateException(message, cause)

class InMemoryModelSecretStore : ModelSecretStore {
  private val values = linkedMapOf<String, String>()

  @Synchronized
  override fun saveSecret(secretId: String, value: String) {
    requireValidSecretId(secretId)
    require(value.isNotEmpty()) { "model secret value is required" }
    values[secretId] = value
  }

  @Synchronized
  override fun loadSecret(secretId: String): String? {
    requireValidSecretId(secretId)
    return values[secretId]
  }

  @Synchronized
  override fun deleteSecret(secretId: String) {
    requireValidSecretId(secretId)
    values.remove(secretId)
  }
}

class AndroidKeystoreModelSecretStore internal constructor(
  private val directory: File,
  private val keyProvider: () -> SecretKey,
  private val directorySync: (File) -> Unit,
) : ModelSecretStore {
  constructor(context: Context, accountId: String? = null) : this(
    directory = modelSecretDirectory(context, accountId),
    keyProvider = AndroidKeystoreKeyProvider::getOrCreate,
    directorySync = ::syncDirectory,
  )

  @Synchronized
  override fun saveSecret(secretId: String, value: String) {
    requireValidSecretId(secretId)
    require(value.isNotEmpty()) { "model secret value is required" }
    val plaintext = value.toByteArray(StandardCharsets.UTF_8)
    require(plaintext.size <= MAX_SECRET_BYTES) { "model secret value is too large" }

    try {
      ensureDirectory()
      val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
      cipher.init(Cipher.ENCRYPT_MODE, keyProvider())
      cipher.updateAAD(secretId.toByteArray(StandardCharsets.UTF_8))
      val ciphertext = cipher.doFinal(plaintext)
      val envelope = encodeEnvelope(cipher.iv, ciphertext)
      writeAtomically(secretFile(secretId), envelope)
    } catch (error: ModelSecretStoreException) {
      throw error
    } catch (error: Exception) {
      throw ModelSecretStoreException("failed to save model secret", error)
    } finally {
      plaintext.fill(0)
    }
  }

  @Synchronized
  override fun loadSecret(secretId: String): String? {
    requireValidSecretId(secretId)
    val file = secretFile(secretId)
    if (!file.exists()) return null

    try {
      if (file.length() !in MIN_ENVELOPE_BYTES..MAX_ENVELOPE_BYTES.toLong()) {
        throw ModelSecretStoreException("model secret payload is invalid")
      }
      val (iv, ciphertext) = decodeEnvelope(file.readBytes())
      val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
      cipher.init(Cipher.DECRYPT_MODE, keyProvider(), GCMParameterSpec(GCM_TAG_BITS, iv))
      cipher.updateAAD(secretId.toByteArray(StandardCharsets.UTF_8))
      val plaintext = cipher.doFinal(ciphertext)
      return try {
        plaintext.toString(StandardCharsets.UTF_8)
      } finally {
        plaintext.fill(0)
      }
    } catch (error: ModelSecretStoreException) {
      throw error
    } catch (error: Exception) {
      throw ModelSecretStoreException("failed to load model secret", error)
    }
  }

  @Synchronized
  override fun deleteSecret(secretId: String) {
    requireValidSecretId(secretId)
    try {
      if (Files.deleteIfExists(secretFile(secretId).toPath())) {
        directorySync(directory)
      }
    } catch (error: Exception) {
      throw ModelSecretStoreException("failed to delete model secret", error)
    }
  }

  private fun ensureDirectory() {
    if (directory.isDirectory) return
    if (directory.exists()) {
      throw ModelSecretStoreException("model secret directory is unavailable")
    }
    val created = directory.mkdirs()
    if (!created && !directory.isDirectory) {
      throw ModelSecretStoreException("model secret directory is unavailable")
    }
    if (created) {
      directory.parentFile?.let(directorySync)
    }
  }

  private fun secretFile(secretId: String): File {
    val digest = MessageDigest.getInstance("SHA-256")
      .digest(secretId.toByteArray(StandardCharsets.UTF_8))
      .joinToString(separator = "") { byte -> "%02x".format(byte.toInt() and 0xff) }
    return File(directory, "$digest.secret")
  }

  private fun writeAtomically(target: File, bytes: ByteArray) {
    val temporary = File.createTempFile("${target.name}.", ".tmp", directory)
    try {
      FileOutputStream(temporary).use { output ->
        output.write(bytes)
        output.fd.sync()
      }
      try {
        Files.move(
          temporary.toPath(),
          target.toPath(),
          StandardCopyOption.ATOMIC_MOVE,
          StandardCopyOption.REPLACE_EXISTING,
        )
      } catch (_: AtomicMoveNotSupportedException) {
        Files.move(
          temporary.toPath(),
          target.toPath(),
          StandardCopyOption.REPLACE_EXISTING,
        )
      }
      directorySync(directory)
    } finally {
      temporary.delete()
    }
  }

  private fun encodeEnvelope(iv: ByteArray, ciphertext: ByteArray): ByteArray {
    require(iv.size in MIN_IV_BYTES..MAX_IV_BYTES) { "model secret IV is invalid" }
    return ByteBuffer.allocate(MAGIC.size + 2 + iv.size + ciphertext.size)
      .put(MAGIC)
      .put(FORMAT_VERSION)
      .put(iv.size.toByte())
      .put(iv)
      .put(ciphertext)
      .array()
  }

  private fun decodeEnvelope(envelope: ByteArray): Pair<ByteArray, ByteArray> {
    if (envelope.size < MIN_ENVELOPE_BYTES) {
      throw ModelSecretStoreException("model secret payload is invalid")
    }
    val buffer = ByteBuffer.wrap(envelope)
    val magic = ByteArray(MAGIC.size).also(buffer::get)
    val version = buffer.get()
    val ivSize = buffer.get().toInt() and 0xff
    if (!magic.contentEquals(MAGIC) || version != FORMAT_VERSION) {
      throw ModelSecretStoreException("model secret payload format is unsupported")
    }
    if (ivSize !in MIN_IV_BYTES..MAX_IV_BYTES || buffer.remaining() <= ivSize) {
      throw ModelSecretStoreException("model secret payload is invalid")
    }
    val iv = ByteArray(ivSize).also(buffer::get)
    val ciphertext = ByteArray(buffer.remaining()).also(buffer::get)
    return iv to ciphertext
  }

  private companion object {
    const val CIPHER_TRANSFORMATION = "AES/GCM/NoPadding"
    const val GCM_TAG_BITS = 128
    const val MAX_SECRET_BYTES = 16 * 1024
    const val MAX_ENVELOPE_BYTES = MAX_SECRET_BYTES + 128
    const val MIN_IV_BYTES = 12
    const val MAX_IV_BYTES = 32
    const val MIN_ENVELOPE_BYTES = 4 + 2 + MIN_IV_BYTES + 16
    val MAGIC = byteArrayOf(0x47, 0x41, 0x4d, 0x53)
    const val FORMAT_VERSION: Byte = 1
  }
}

private fun modelSecretDirectory(context: Context, accountId: String?): File {
  if (accountId == null) return File(context.noBackupFilesDir, "model-secrets")
  require(OPAQUE_ACCOUNT_ID.matches(accountId)) { "model secret account scope is invalid" }
  return File(context.noBackupFilesDir, "model-secrets-$accountId")
}

private object AndroidKeystoreKeyProvider {
  private const val PROVIDER = "AndroidKeyStore"
  private const val KEY_ALIAS = "com.agentweave.mobile.model-secrets.v1"

  @Synchronized
  fun getOrCreate(): SecretKey {
    val keyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }
    val existing = keyStore.getKey(KEY_ALIAS, null)
    if (existing != null) {
      return existing as? SecretKey
        ?: throw ModelSecretStoreException("Android Keystore alias is not an AES secret key")
    }

    val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER)
    generator.init(
      KeyGenParameterSpec.Builder(
        KEY_ALIAS,
        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
      )
        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
        .setKeySize(256)
        .build(),
    )
    return generator.generateKey()
  }
}

private fun syncDirectory(directory: File) {
  val descriptor = Os.open(
    directory.absolutePath,
    OsConstants.O_RDONLY,
    0,
  )
  try {
    Os.fsync(descriptor)
  } finally {
    Os.close(descriptor)
  }
}

private fun requireValidSecretId(secretId: String) {
  require(secretId.isNotBlank()) { "model secret id is required" }
  require(secretId.length <= 256) { "model secret id is too long" }
}

private val OPAQUE_ACCOUNT_ID = Regex("^usr_[0-9a-f]{64}$")
