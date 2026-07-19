package com.agentweave.mobile.runtime

import android.content.Context
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.nio.file.FileVisitResult
import java.nio.file.Files
import java.nio.file.SimpleFileVisitor
import java.nio.file.attribute.BasicFileAttributes

fun interface RuntimeAccountDataStore {
  fun clear(accountId: String)
}

class AndroidRuntimeAccountDataStore internal constructor(
  private val runtimeDataRoot: File,
  private val modelSecretRoot: (String) -> File,
  private val directorySync: (File) -> Unit,
) : RuntimeAccountDataStore {
  constructor(context: Context) : this(
    runtimeDataRoot = File(context.filesDir, "identity-data"),
    modelSecretRoot = { accountId ->
      File(context.noBackupFilesDir, "model-secrets-$accountId")
    },
    directorySync = ::syncAccountDataDirectory,
  )

  @Synchronized
  override fun clear(accountId: String) {
    require(OPAQUE_ACCOUNT_ID.matches(accountId)) { "account data scope is invalid" }
    deletePrivateTree(File(runtimeDataRoot, accountId))
    deletePrivateTree(modelSecretRoot(accountId))
  }

  private fun deletePrivateTree(root: File) {
    if (!root.exists() && !Files.isSymbolicLink(root.toPath())) return
    check(!Files.isSymbolicLink(root.toPath())) { "account data root cannot be a symlink" }
    val parent = checkNotNull(root.parentFile)
    Files.walkFileTree(
      root.toPath(),
      object : SimpleFileVisitor<java.nio.file.Path>() {
        override fun visitFile(
          file: java.nio.file.Path,
          attributes: BasicFileAttributes,
        ): FileVisitResult {
          Files.delete(file)
          return FileVisitResult.CONTINUE
        }

        override fun postVisitDirectory(
          directory: java.nio.file.Path,
          error: java.io.IOException?,
        ): FileVisitResult {
          if (error != null) throw error
          Files.delete(directory)
          return FileVisitResult.CONTINUE
        }
      },
    )
    if (parent.isDirectory) directorySync(parent)
  }
}

private fun syncAccountDataDirectory(directory: File) {
  val descriptor = Os.open(directory.absolutePath, OsConstants.O_RDONLY, 0)
  try {
    Os.fsync(descriptor)
  } finally {
    Os.close(descriptor)
  }
}

private val OPAQUE_ACCOUNT_ID = Regex("^usr_[0-9a-f]{64}$")
