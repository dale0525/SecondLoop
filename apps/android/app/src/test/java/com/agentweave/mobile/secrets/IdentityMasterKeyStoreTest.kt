package com.agentweave.mobile.secrets

import java.io.File
import java.nio.file.Files
import java.security.SecureRandom
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class IdentityMasterKeyStoreTest {
  @Test
  fun wrappedMasterKeyPersistsAndCallerBufferIsZeroed() {
    val root = Files.createTempDirectory("identity-key-store").toFile()
    val wrappingKey = SecretKeySpec(ByteArray(32) { 5 }, "AES")
    var firstSnapshot = ByteArray(0)
    lateinit var exposed: ByteArray
    val first = store(root, wrappingKey)

    first.withMasterKey { key ->
      exposed = key
      firstSnapshot = key.copyOf()
      assertTrue(key.any { it.toInt() != 0 })
    }
    assertTrue(exposed.all { it.toInt() == 0 })

    val second = store(root, wrappingKey)
    second.withMasterKey { key ->
      assertArrayEquals(firstSnapshot, key)
    }
    val envelope = File(root, "master-key.bin").readBytes()
    assertFalse(envelope.asList().windowed(firstSnapshot.size).any { window ->
      window.toByteArray().contentEquals(firstSnapshot)
    })
    root.deleteRecursively()
  }

  @Test
  fun tamperedEnvelopeFailsClosedWithoutReplacingIt() {
    val root = Files.createTempDirectory("identity-key-tamper").toFile()
    val wrappingKey = SecretKeySpec(ByteArray(32) { 9 }, "AES")
    store(root, wrappingKey).withMasterKey { }
    val file = File(root, "master-key.bin")
    val tampered = file.readBytes().also { bytes ->
      bytes[bytes.lastIndex] = (bytes.last().toInt() xor 0x01).toByte()
    }
    file.writeBytes(tampered)

    assertThrows(IdentityMasterKeyStoreException::class.java) {
      store(root, wrappingKey).withMasterKey { }
    }
    assertArrayEquals(tampered, file.readBytes())
    root.deleteRecursively()
  }

  private fun store(root: File, key: SecretKeySpec) =
    AndroidKeystoreIdentityMasterKeyStore(
      directory = root,
      wrappingKeyProvider = { key },
      random = SecureRandom(),
      directorySync = {},
    )
}
