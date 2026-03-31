package com.secondloop.secondloop

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import java.io.File
import java.util.Locale

internal class AndroidUpdateChannelHandler(
  private val activity: MainActivity,
) {
  fun handle(call: MethodCall): Any? {
    return when (call.method) {
      "getSupportedAbis" -> getSupportedAbis()
      "installApk" -> {
        val args = call.arguments as? Map<*, *>
        val path = (args?.get("path") as? String)?.trim().orEmpty()
        if (path.isBlank()) {
          AndroidApkInstallLaunchStatus.failed.channelValue
        } else {
          launchApkInstaller(path).channelValue
        }
      }
      else -> null
    }
  }

  private fun getSupportedAbis(): List<String> {
    return try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        Build.SUPPORTED_ABIS?.filter { it.isNotBlank() } ?: emptyList()
      } else {
        listOfNotNull(Build.CPU_ABI, Build.CPU_ABI2).filter { it.isNotBlank() }
      }
    } catch (_: Throwable) {
      emptyList()
    }
  }

  private fun launchApkInstaller(path: String): AndroidApkInstallLaunchStatus {
    return try {
      val apkFile = File(path)
      if (!apkFile.exists() || !apkFile.isFile) {
        return AndroidApkInstallLaunchStatus.failed
      }

      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !activity.packageManager.canRequestPackageInstalls()) {
        val settingsShortcut =
          activity.settingsIntent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
            data = Uri.parse("package:${activity.packageName}")
          }
        if (settingsShortcut.resolveActivity(activity.packageManager) != null) {
          activity.startActivity(settingsShortcut)
          return AndroidApkInstallLaunchStatus.permissionSettingsOpened
        }
        return AndroidApkInstallLaunchStatus.failed
      }

      val apkUri =
        FileProvider.getUriForFile(
          activity,
          "${activity.packageName}.update_file_provider",
          apkFile,
        )
      val mimeType =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(apkFile.extension.lowercase(Locale.US))
          ?: "application/vnd.android.package-archive"
      val installIntent =
        Intent(Intent.ACTION_VIEW).apply {
          setDataAndType(apkUri, mimeType)
          addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
          addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
      if (installIntent.resolveActivity(activity.packageManager) == null) {
        return AndroidApkInstallLaunchStatus.failed
      }

      activity.startActivity(installIntent)
      AndroidApkInstallLaunchStatus.launchedInstaller
    } catch (_: Throwable) {
      AndroidApkInstallLaunchStatus.failed
    }
  }
}

internal enum class AndroidApkInstallLaunchStatus(val channelValue: String) {
  launchedInstaller("launched_installer"),
  permissionSettingsOpened("permission_settings_opened"),
  failed("failed"),
}
