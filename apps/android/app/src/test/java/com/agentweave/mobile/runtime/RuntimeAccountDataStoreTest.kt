package com.agentweave.mobile.runtime

import java.nio.file.Files
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class RuntimeAccountDataStoreTest {
  @Test
  fun clearingOneAccountPreservesOtherAccountsAndExternalSymlinkTargets() {
    val root = Files.createTempDirectory("account-data-store")
    val runtimeRoot = root.resolve("runtime").toFile()
    val secretRoot = root.resolve("secrets").toFile()
    val accountA = "usr_${"a".repeat(64)}"
    val accountB = "usr_${"b".repeat(64)}"
    runtimeRoot.resolve("$accountA/agentweave.db").apply {
      checkNotNull(parentFile).mkdirs()
      writeText("account-a")
    }
    runtimeRoot.resolve("$accountB/agentweave.db").apply {
      checkNotNull(parentFile).mkdirs()
      writeText("account-b")
    }
    secretRoot.resolve(accountA).resolve("model.secret").apply {
      checkNotNull(parentFile).mkdirs()
      writeText("ciphertext-a")
    }
    secretRoot.resolve(accountB).resolve("model.secret").apply {
      checkNotNull(parentFile).mkdirs()
      writeText("ciphertext-b")
    }
    val outside = root.resolve("outside.txt").apply { Files.writeString(this, "keep") }
    val link = runtimeRoot.resolve(accountA).toPath().resolve("outside-link")
    runCatching { Files.createSymbolicLink(link, outside) }

    AndroidRuntimeAccountDataStore(
      runtimeDataRoot = runtimeRoot,
      modelSecretRoot = { accountId -> secretRoot.resolve(accountId) },
      directorySync = {},
    ).clear(accountA)

    assertFalse(runtimeRoot.resolve(accountA).exists())
    assertFalse(secretRoot.resolve(accountA).exists())
    assertTrue(runtimeRoot.resolve("$accountB/agentweave.db").isFile)
    assertTrue(secretRoot.resolve(accountB).resolve("model.secret").isFile)
    assertTrue(Files.exists(outside))
    root.toFile().deleteRecursively()
  }

  @Test
  fun accountScopeAndRootSymlinksFailClosed() {
    val root = Files.createTempDirectory("account-data-symlink")
    val runtimeRoot = root.resolve("runtime").toFile().also { it.mkdirs() }
    val secrets = root.resolve("secrets").toFile().also { it.mkdirs() }
    val account = "usr_${"a".repeat(64)}"
    val outside = root.resolve("outside").toFile().also { it.mkdirs() }
    val accountRoot = runtimeRoot.resolve(account).toPath()
    Files.createSymbolicLink(accountRoot, outside.toPath())
    val store = AndroidRuntimeAccountDataStore(
      runtimeDataRoot = runtimeRoot,
      modelSecretRoot = { accountId -> secrets.resolve(accountId) },
      directorySync = {},
    )

    assertThrows(IllegalStateException::class.java) { store.clear(account) }
    assertThrows(IllegalArgumentException::class.java) { store.clear("../../outside") }
    assertTrue(outside.isDirectory)
    Files.delete(accountRoot)
    root.toFile().deleteRecursively()
  }
}
