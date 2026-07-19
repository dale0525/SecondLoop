package com.agentweave.mobile.secrets

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

interface IdentityMasterKeyStore {
  fun <T> withMasterKey(block: (ByteArray) -> T): T
}

class IdentityMasterKeyStoreException(
  message: String,
  cause: Throwable? = null,
) : IllegalStateException(message, cause)

class AndroidKeystoreIdentityMasterKeyStore internal constructor(
  private val directory: File,
  private val wrappingKeyProvider: () -> SecretKey,
  private val random: SecureRandom,
  private val directorySync: (File) -> Unit,
) : IdentityMasterKeyStore {
  constructor(context: Context) : this(
    directory = File(context.noBackupFilesDir, "identity-key-vault"),
    wrappingKeyProvider = AndroidIdentityWrappingKeyProvider::getOrCreate,
    random = SecureRandom(),
    directorySync = ::syncIdentityDirectory,
  )

  override fun <T> withMasterKey(block: (ByteArray) -> T): T = synchronized(MutationLock) {
    val key = loadOrCreate()
    try {
      block(key)
    } finally {
      key.fill(0)
    }
  }

  private fun loadOrCreate(): ByteArray {
    try {
      ensureDirectory()
      val file = File(directory, MASTER_KEY_FILE)
      rejectSymlink(file)
      if (file.isFile) return decrypt(file)
      val masterKey = ByteArray(MASTER_KEY_BYTES).also(random::nextBytes)
      try {
        writeAtomically(file, encrypt(masterKey))
        return masterKey
      } catch (error: Exception) {
        masterKey.fill(0)
        throw error
      }
    } catch (error: IdentityMasterKeyStoreException) {
      throw error
    } catch (error: Exception) {
      throw IdentityMasterKeyStoreException("identity key vault is unavailable", error)
    }
  }

  private fun encrypt(plaintext: ByteArray): ByteArray {
    val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
    cipher.init(Cipher.ENCRYPT_MODE, wrappingKeyProvider())
    cipher.updateAAD(ASSOCIATED_DATA)
    val ciphertext = cipher.doFinal(plaintext)
    return ByteBuffer.allocate(MAGIC.size + 2 + cipher.iv.size + ciphertext.size)
      .put(MAGIC)
      .put(FORMAT_VERSION)
      .put(cipher.iv.size.toByte())
      .put(cipher.iv)
      .put(ciphertext)
      .array()
  }

  private fun decrypt(file: File): ByteArray {
    if (file.length() !in MIN_ENVELOPE_BYTES..MAX_ENVELOPE_BYTES.toLong()) {
      throw IdentityMasterKeyStoreException("identity key envelope is invalid")
    }
    val envelope = file.readBytes()
    val buffer = ByteBuffer.wrap(envelope)
    val magic = ByteArray(MAGIC.size).also(buffer::get)
    val version = buffer.get()
    val ivSize = buffer.get().toInt() and 0xff
    if (
      !magic.contentEquals(MAGIC) ||
      version != FORMAT_VERSION ||
      ivSize !in MIN_IV_BYTES..MAX_IV_BYTES ||
      buffer.remaining() <= ivSize
    ) {
      throw IdentityMasterKeyStoreException("identity key envelope is invalid")
    }
    val iv = ByteArray(ivSize).also(buffer::get)
    val ciphertext = ByteArray(buffer.remaining()).also(buffer::get)
    val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
    cipher.init(
      Cipher.DECRYPT_MODE,
      wrappingKeyProvider(),
      GCMParameterSpec(GCM_TAG_BITS, iv),
    )
    cipher.updateAAD(ASSOCIATED_DATA)
    val plaintext = cipher.doFinal(ciphertext)
    if (plaintext.size != MASTER_KEY_BYTES) {
      plaintext.fill(0)
      throw IdentityMasterKeyStoreException("identity key envelope is invalid")
    }
    return plaintext
  }

  private fun ensureDirectory() {
    if (directory.exists()) {
      if (!directory.isDirectory || Files.isSymbolicLink(directory.toPath())) {
        throw IdentityMasterKeyStoreException("identity key vault directory is invalid")
      }
      return
    }
    if (!directory.mkdirs() && !directory.isDirectory) {
      throw IdentityMasterKeyStoreException("identity key vault directory is unavailable")
    }
    directory.parentFile?.let(directorySync)
  }

  private fun rejectSymlink(file: File) {
    if (Files.isSymbolicLink(file.toPath())) {
      throw IdentityMasterKeyStoreException("identity key envelope cannot be a symlink")
    }
  }

  private fun writeAtomically(target: File, bytes: ByteArray) {
    val temporary = File.createTempFile("identity-key-", ".tmp", directory)
    try {
      FileOutputStream(temporary).use { output ->
        output.write(bytes)
        output.fd.sync()
      }
      try {
        Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE)
      } catch (_: AtomicMoveNotSupportedException) {
        Files.move(temporary.toPath(), target.toPath())
      }
      directorySync(directory)
    } finally {
      temporary.delete()
    }
  }

  private companion object {
    val MutationLock = Any()
    const val MASTER_KEY_FILE = "master-key.bin"
    const val MASTER_KEY_BYTES = 32
    const val CIPHER_TRANSFORMATION = "AES/GCM/NoPadding"
    const val GCM_TAG_BITS = 128
    const val MIN_IV_BYTES = 12
    const val MAX_IV_BYTES = 32
    const val MIN_ENVELOPE_BYTES = 4 + 2 + MIN_IV_BYTES + 16
    const val MAX_ENVELOPE_BYTES = 256
    val MAGIC = byteArrayOf(0x47, 0x41, 0x49, 0x4b)
    const val FORMAT_VERSION: Byte = 1
    val ASSOCIATED_DATA = "agentweave.identity.master-key.v1".toByteArray(Charsets.UTF_8)
  }
}

private object AndroidIdentityWrappingKeyProvider {
  private const val PROVIDER = "AndroidKeyStore"
  private const val KEY_ALIAS = "com.agentweave.mobile.identity-wrapping.v1"

  @Synchronized
  fun getOrCreate(): SecretKey {
    val keyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }
    val existing = keyStore.getKey(KEY_ALIAS, null)
    if (existing != null) {
      return existing as? SecretKey
        ?: throw IdentityMasterKeyStoreException("identity wrapping key has an invalid type")
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

private fun syncIdentityDirectory(directory: File) {
  val descriptor = Os.open(directory.absolutePath, OsConstants.O_RDONLY, 0)
  try {
    Os.fsync(descriptor)
  } finally {
    Os.close(descriptor)
  }
}
