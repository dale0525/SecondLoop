package com.secondloop.secondloop

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.app.AlarmManager
import android.os.CancellationSignal
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.app.NotificationManagerCompat
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

private const val kPendingSharesChangedMethod = "pendingSharesChanged"

class MainActivity : FlutterFragmentActivity() {
  private val pendingShares = mutableListOf<Map<String, String>>()
  private var shareChannel: MethodChannel? = null
  private var exifChannel: MethodChannel? = null
  private var locationChannel: MethodChannel? = null
  private var permissionsChannel: MethodChannel? = null
  private var audioRecordingLifecycleChannel: MethodChannel? = null
  private var audioTranscodeChannel: MethodChannel? = null
  private var videoTranscodeChannel: MethodChannel? = null
  private var ocrChannel: MethodChannel? = null
  private var markdownPdfExportChannel: MethodChannel? = null
  private var androidUpdateChannel: MethodChannel? = null
  private val ocrAndPdfChannelHandler by lazy {
    OcrAndPdfChannelHandler(cacheDir = cacheDir)
  }
  private val nativeAudioTranscribeChannelHandler by lazy {
    NativeAudioTranscribeChannelHandler()
  }
  private val markdownPdfExportChannelHandler by lazy {
    MarkdownPdfExportChannelHandler(
      activity = this,
      cacheDir = cacheDir,
    )
  }
  private val androidUpdateChannelHandler by lazy {
    AndroidUpdateChannelHandler(activity = this)
  }

  private var pendingMediaLocationPermissionResult: MethodChannel.Result? = null
  private val requestMediaLocationPermissionLauncher =
    registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
      pendingMediaLocationPermissionResult?.success(granted)
      pendingMediaLocationPermissionResult = null
    }

  private var pendingLocationPermissionResult: MethodChannel.Result? = null
  private val requestLocationPermissionLauncher =
    registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { grants ->
      val result = pendingLocationPermissionResult
      pendingLocationPermissionResult = null
      if (result == null) return@registerForActivityResult

      val grantedFine = grants[Manifest.permission.ACCESS_FINE_LOCATION] == true
      val grantedCoarse = grants[Manifest.permission.ACCESS_COARSE_LOCATION] == true
      if (!grantedFine && !grantedCoarse) {
        result.success(null)
        return@registerForActivityResult
      }

      fetchAndReturnLocation(result)
    }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    shareChannel =
      MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "secondloop/share_intent").apply {
        setMethodCallHandler { call, result ->
          when (call.method) {
            "consumePendingShares" -> {
              val shares = pendingShares.toList()
              pendingShares.clear()
              result.success(shares)
            }
            else -> result.notImplemented()
          }
        }
      }

    permissionsChannel =
      MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "secondloop/permissions").apply {
        setMethodCallHandler { call, result ->
          when (call.method) {
            "requestMediaLocation" -> {
              if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                result.success(true)
                return@setMethodCallHandler
              }

              val granted =
                ContextCompat.checkSelfPermission(
                  this@MainActivity,
                  Manifest.permission.ACCESS_MEDIA_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
              if (granted) {
                result.success(true)
                return@setMethodCallHandler
              }

              if (pendingMediaLocationPermissionResult != null) {
                result.success(false)
                return@setMethodCallHandler
              }

              pendingMediaLocationPermissionResult = result
              requestMediaLocationPermissionLauncher.launch(Manifest.permission.ACCESS_MEDIA_LOCATION)
            }
            "openPermissionSettings" -> {
              val args = call.arguments as? Map<*, *>
              val item = (args?.get("item") as? String)?.trim().orEmpty()
              result.success(openPermissionSettingsShortcut(item))
            }
            "queryPermissionStatus" -> {
              val args = call.arguments as? Map<*, *>
              val item = (args?.get("item") as? String)?.trim().orEmpty()
              result.success(queryPermissionStatus(item))
            }
            else -> result.notImplemented()
          }
        }
      }

    locationChannel =
      MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "secondloop/location").apply {
        setMethodCallHandler { call, result ->
          when (call.method) {
            "getCurrentLocation" -> {
              val hasFine =
                ContextCompat.checkSelfPermission(
                  this@MainActivity,
                  Manifest.permission.ACCESS_FINE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
              val hasCoarse =
                ContextCompat.checkSelfPermission(
                  this@MainActivity,
                  Manifest.permission.ACCESS_COARSE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
              if (!hasFine && !hasCoarse) {
                if (pendingLocationPermissionResult != null) {
                  result.success(null)
                  return@setMethodCallHandler
                }
                pendingLocationPermissionResult = result
                requestLocationPermissionLauncher.launch(
                  arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                  )
                )
                return@setMethodCallHandler
              }

              fetchAndReturnLocation(result)
            }
            else -> result.notImplemented()
          }
        }
      }

    exifChannel =
      MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "secondloop/exif").apply {
        setMethodCallHandler { call, result ->
          when (call.method) {
            "extractImageMetadata" -> {
              val args = call.arguments as? Map<*, *>
              val path = args?.get("path") as? String
              if (path.isNullOrBlank()) {
                result.success(null)
                return@setMethodCallHandler
              }

              try {
                val meta = extractImageMetadata(path)
                result.success(meta)
              } catch (_: Throwable) {
                result.success(null)
              }
            }
            else -> result.notImplemented()
          }
        }
      }

    audioTranscodeChannel =
      MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "secondloop/audio_transcode").apply {
        setMethodCallHandler { call, result ->
          when (call.method) {
            "transcodeToM4a" -> handleTranscodeToM4a(call, result)
            "decodeToWavPcm16Mono16k" -> handleDecodeToWavPcm16Mono16k(call, result)
            else -> result.notImplemented()
          }
        }
      }

    audioRecordingLifecycleChannel =
      MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "secondloop/audio_recording_lifecycle",
      ).apply {
        setMethodCallHandler { call, result ->
          when (call.method) {
            "startForegroundRecording" -> {
              result.success(startAudioRecordingForegroundService())
            }
            "stopForegroundRecording" -> {
              result.success(stopAudioRecordingForegroundService())
            }
            "startForegroundAskAi" -> {
              result.success(startAskAiForegroundService())
            }
            "stopForegroundAskAi" -> {
              result.success(stopAskAiForegroundService())
            }
            else -> result.notImplemented()
          }
        }
      }

    videoTranscodeChannel =
      MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "secondloop/video_transcode").apply {
        setMethodCallHandler { call, result ->
          when (call.method) {
            "extractPreviewPosterJpeg" -> handleExtractPreviewPosterJpeg(call, result)
            "extractPreviewFramesJpeg" -> handleExtractPreviewFramesJpeg(call, result)
            else -> result.notImplemented()
          }
        }
      }

    ocrChannel =
      MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "secondloop/ocr").apply {
        setMethodCallHandler { call, result ->
          ocrAndPdfChannelHandler.handle(call, result)
        }
      }

    markdownPdfExportChannel =
      MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "secondloop/markdown_pdf_export").apply {
        setMethodCallHandler { call, result ->
          markdownPdfExportChannelHandler.handle(call, result)
        }
      }

    androidUpdateChannel =
      MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "secondloop/android_update").apply {
        setMethodCallHandler { call, result ->
          val handled = androidUpdateChannelHandler.handle(call)
          if (handled != null) {
            result.success(handled)
          } else {
            result.notImplemented()
          }
        }
      }
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    handleShareIntent(intent)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    handleShareIntent(intent)
  }

  private fun handleShareIntent(intent: Intent?) {
    if (intent == null) return

    val type = intent.getStringExtra(ShareReceiverActivity.EXTRA_SHARE_TYPE)
    val content = intent.getStringExtra(ShareReceiverActivity.EXTRA_SHARE_CONTENT)
    if (type.isNullOrBlank() || content.isNullOrBlank()) return

    val mimeType = intent.getStringExtra(ShareReceiverActivity.EXTRA_SHARE_MIME_TYPE)
    val filename = intent.getStringExtra(ShareReceiverActivity.EXTRA_SHARE_FILENAME)
    val payload = mutableMapOf("type" to type, "content" to content)
    if (!mimeType.isNullOrBlank()) {
      payload["mimeType"] = mimeType
    }
    if (!filename.isNullOrBlank()) {
      payload["filename"] = filename
    }
    pendingShares.add(payload)
    notifyPendingSharesChanged()
    intent.removeExtra(ShareReceiverActivity.EXTRA_SHARE_TYPE)
    intent.removeExtra(ShareReceiverActivity.EXTRA_SHARE_CONTENT)
    intent.removeExtra(ShareReceiverActivity.EXTRA_SHARE_MIME_TYPE)
    intent.removeExtra(ShareReceiverActivity.EXTRA_SHARE_FILENAME)
  }

  private fun notifyPendingSharesChanged() {
    try {
      shareChannel?.invokeMethod(kPendingSharesChangedMethod, null)
    } catch (_: Throwable) {
      // ignore
    }
  }

  private fun queryPermissionStatus(item: String): String {
    return when (item) {
      "microphone" -> {
        val granted =
          ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
          ) == PackageManager.PERMISSION_GRANTED
        if (granted) "enabled" else "disabled"
      }
      "notifications" -> if (areNotificationsEnabled()) "enabled" else "disabled"
      "exact_alarm" -> if (canScheduleExactAlarms()) "enabled" else "disabled"
      "location" -> {
        val fineGranted =
          ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
          ) == PackageManager.PERMISSION_GRANTED
        val coarseGranted =
          ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION
          ) == PackageManager.PERMISSION_GRANTED
        if (fineGranted || coarseGranted) "enabled" else "disabled"
      }
      "auto_start" -> "unknown"
      "battery_unrestricted" -> batteryOptimizationPermissionStatus()
      else -> "unknown"
    }
  }

  private fun areNotificationsEnabled(): Boolean {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      val granted =
        ContextCompat.checkSelfPermission(
          this,
          Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
      if (!granted) return false
    }
    return NotificationManagerCompat.from(this).areNotificationsEnabled()
  }

  private fun canScheduleExactAlarms(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
    val alarmManager = getSystemService(ALARM_SERVICE) as? AlarmManager ?: return false
    return alarmManager.canScheduleExactAlarms()
  }

  private fun batteryOptimizationPermissionStatus(): String {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
      return "enabled"
    }
    val powerManager = getSystemService(POWER_SERVICE) as? PowerManager ?: return "unknown"
    return if (powerManager.isIgnoringBatteryOptimizations(packageName)) {
      "enabled"
    } else {
      "disabled"
    }
  }

  private fun openPermissionSettingsShortcut(item: String): Boolean {
    val intents =
      when (item) {
        "microphone" ->
          listOf(
            appDetailsIntent(),
            settingsIntent(Settings.ACTION_PRIVACY_SETTINGS),
            settingsIntent(Settings.ACTION_MANAGE_APPLICATIONS_SETTINGS),
          )
        "notifications" -> notificationPermissionIntents()
        "exact_alarm" -> exactAlarmPermissionIntents()
        "location" ->
          listOf(
            appDetailsIntent(),
            settingsIntent(Settings.ACTION_LOCATION_SOURCE_SETTINGS),
            settingsIntent(Settings.ACTION_PRIVACY_SETTINGS),
          )
        "auto_start" -> autoStartPermissionIntents()
        "battery_unrestricted" -> batteryUnrestrictedPermissionIntents()
        else -> emptyList()
      }

    return launchFirstResolvableIntent(intents)
  }

  private fun notificationPermissionIntents(): List<Intent> {
    val result = mutableListOf<Intent>()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      result.add(
        settingsIntent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
          putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        }
      )
    } else {
      result.add(
        settingsIntent("android.settings.APP_NOTIFICATION_SETTINGS").apply {
          putExtra("app_package", packageName)
          putExtra("app_uid", applicationInfo.uid)
        }
      )
    }
    result.add(appDetailsIntent())
    result.add(settingsIntent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
    return result
  }

  private fun exactAlarmPermissionIntents(): List<Intent> {
    val result = mutableListOf<Intent>()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      result.add(
        settingsIntent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
          data = Uri.parse("package:$packageName")
        }
      )
    }
    result.addAll(notificationPermissionIntents())
    return result
  }

  private fun autoStartPermissionIntents(): List<Intent> {
    val result = mutableListOf<Intent>()
    result.addAll(manufacturerAutoStartIntents())
    result.addAll(batteryUnrestrictedPermissionIntents())
    result.add(appDetailsIntent())
    result.add(settingsIntent(Settings.ACTION_MANAGE_APPLICATIONS_SETTINGS))
    return result
  }

  private fun batteryUnrestrictedPermissionIntents(): List<Intent> {
    val result = mutableListOf<Intent>()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      result.add(
        settingsIntent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
          data = Uri.parse("package:$packageName")
        }
      )
      result.add(settingsIntent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
    }
    result.add(settingsIntent(Settings.ACTION_BATTERY_SAVER_SETTINGS))
    result.add(appDetailsIntent())
    return result
  }

  private fun manufacturerAutoStartIntents(): List<Intent> {
    val manufacturer = Build.MANUFACTURER.lowercase(Locale.US)
    return when {
      manufacturer.contains("xiaomi") ->
        listOf(
          componentIntent(
            "com.miui.securitycenter",
            "com.miui.permcenter.autostart.AutoStartManagementActivity",
          ),
        )
      manufacturer.contains("oppo") ->
        listOf(
          componentIntent(
            "com.coloros.safecenter",
            "com.coloros.safecenter.permission.startup.StartupAppListActivity",
          ),
          componentIntent(
            "com.oplus.safecenter",
            "com.oplus.safecenter.permission.startup.StartupAppListActivity",
          ),
        )
      manufacturer.contains("vivo") ->
        listOf(
          componentIntent(
            "com.iqoo.secure",
            "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
          ),
          componentIntent(
            "com.vivo.permissionmanager",
            "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
          ),
        )
      manufacturer.contains("huawei") ->
        listOf(
          componentIntent(
            "com.huawei.systemmanager",
            "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
          ),
        )
      manufacturer.contains("samsung") ->
        listOf(
          componentIntent(
            "com.samsung.android.lool",
            "com.samsung.android.sm.ui.battery.BatteryActivity",
          ),
        )
      else -> emptyList()
    }
  }

  internal fun settingsIntent(action: String): Intent {
    return Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
  }

  private fun appDetailsIntent(): Intent {
    return settingsIntent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
      data = Uri.fromParts("package", packageName, null)
    }
  }

  private fun componentIntent(packageName: String, className: String): Intent {
    return Intent().apply {
      component = ComponentName(packageName, className)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
  }

  private fun launchFirstResolvableIntent(intents: List<Intent>): Boolean {
    for (candidate in intents) {
      try {
        if (candidate.resolveActivity(packageManager) != null) {
          startActivity(candidate)
          return true
        }
      } catch (_: Throwable) {
        // Try next candidate intent.
      }
    }
    return false
  }

  private fun startAudioRecordingForegroundService(): Boolean {
    return try {
      val intent = AudioRecordingForegroundService.startIntent(this)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        ContextCompat.startForegroundService(this, intent)
      } else {
        startService(intent)
      }
      true
    } catch (_: Throwable) {
      false
    }
  }

  private fun stopAudioRecordingForegroundService(): Boolean {
    return try {
      stopService(AudioRecordingForegroundService.stopIntent(this))
      true
    } catch (_: Throwable) {
      false
    }
  }

  private fun startAskAiForegroundService(): Boolean {
    return try {
      val intent = AskAiForegroundService.startIntent(this)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        ContextCompat.startForegroundService(this, intent)
      } else {
        startService(intent)
      }
      true
    } catch (_: Throwable) {
      false
    }
  }

  private fun stopAskAiForegroundService(): Boolean {
    return try {
      stopService(AskAiForegroundService.stopIntent(this))
      true
    } catch (_: Throwable) {
      false
    }
  }

  private fun fetchAndReturnLocation(result: MethodChannel.Result) {
    val locationManager = getSystemService(LOCATION_SERVICE) as? LocationManager
    if (locationManager == null) {
      result.success(null)
      return
    }

    val hasFine =
      ContextCompat.checkSelfPermission(
        this@MainActivity,
        Manifest.permission.ACCESS_FINE_LOCATION
      ) == PackageManager.PERMISSION_GRANTED
    val hasCoarse =
      ContextCompat.checkSelfPermission(
        this@MainActivity,
        Manifest.permission.ACCESS_COARSE_LOCATION
      ) == PackageManager.PERMISSION_GRANTED

    val providers = mutableListOf<String>()
    if (hasFine) providers.add(LocationManager.GPS_PROVIDER)
    if (hasFine || hasCoarse) providers.add(LocationManager.NETWORK_PROVIDER)
    providers.add(LocationManager.PASSIVE_PROVIDER)

    val enabledProviders = providers.filter { provider ->
      try {
        locationManager.isProviderEnabled(provider)
      } catch (_: Throwable) {
        false
      }
    }

    val last = bestLastKnownLocation(locationManager, enabledProviders)
    val currentProvider = enabledProviders.firstOrNull()
    if (currentProvider == null) {
      if (last == null) {
        result.success(null)
      } else {
        result.success(mapOf("latitude" to last.latitude, "longitude" to last.longitude))
      }
      return
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      val cancellationSignal = CancellationSignal()
      val handler = Handler(Looper.getMainLooper())
      var done = false

      val timeoutRunnable = Runnable {
        if (done) return@Runnable
        done = true
        try {
          cancellationSignal.cancel()
        } catch (_: Throwable) {}

        if (last == null) {
          result.success(null)
        } else {
          result.success(mapOf("latitude" to last.latitude, "longitude" to last.longitude))
        }
      }
      handler.postDelayed(timeoutRunnable, 2500)

      try {
        locationManager.getCurrentLocation(
          currentProvider,
          cancellationSignal,
          ContextCompat.getMainExecutor(this@MainActivity)
        ) { location ->
          if (done) return@getCurrentLocation
          done = true
          handler.removeCallbacks(timeoutRunnable)
          val chosen = location ?: last
          if (chosen == null) {
            result.success(null)
          } else {
            result.success(mapOf("latitude" to chosen.latitude, "longitude" to chosen.longitude))
          }
        }
      } catch (_: Throwable) {
        done = true
        handler.removeCallbacks(timeoutRunnable)
        if (last == null) {
          result.success(null)
        } else {
          result.success(mapOf("latitude" to last.latitude, "longitude" to last.longitude))
        }
      }
      return
    }

    if (last != null) {
      result.success(mapOf("latitude" to last.latitude, "longitude" to last.longitude))
      return
    }

    var done = false
    val listener =
      object : LocationListener {
        override fun onLocationChanged(location: Location) {
          if (done) return
          done = true
          try {
            locationManager.removeUpdates(this)
          } catch (_: Throwable) {}
          result.success(mapOf("latitude" to location.latitude, "longitude" to location.longitude))
        }
      }

    try {
      locationManager.requestSingleUpdate(currentProvider, listener, Looper.getMainLooper())
    } catch (_: Throwable) {
      result.success(null)
      return
    }

    Handler(Looper.getMainLooper()).postDelayed({
      if (done) return@postDelayed
      done = true
      try {
        locationManager.removeUpdates(listener)
      } catch (_: Throwable) {}
      result.success(null)
    }, 2500)
  }

  private fun bestLastKnownLocation(
    locationManager: LocationManager,
    providers: List<String>
  ): Location? {
    var best: Location? = null
    for (provider in providers) {
      val loc =
        try {
          locationManager.getLastKnownLocation(provider)
        } catch (_: Throwable) {
          null
        } ?: continue
      if (best == null || loc.time > best!!.time) {
        best = loc
      }
    }
    return best
  }

  private fun extractImageMetadata(path: String): Map<String, Any?>? {
    val exif = readExif(path) ?: return null

    val capturedAtMsUtc = parseExifDateTimeMsUtc(
      exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)
        ?: exif.getAttribute(ExifInterface.TAG_DATETIME)
        ?: exif.getAttribute(ExifInterface.TAG_DATETIME_DIGITIZED)
    )

    val latLong = FloatArray(2)
    val hasLatLong = try {
      exif.getLatLong(latLong)
    } catch (_: Throwable) {
      false
    }
    val latitude = if (hasLatLong) latLong[0].toDouble() else null
    val longitude = if (hasLatLong) latLong[1].toDouble() else null

    val out = mutableMapOf<String, Any?>()
    if (capturedAtMsUtc != null) {
      out["capturedAtMsUtc"] = capturedAtMsUtc
    }
    if (latitude != null && longitude != null) {
      out["latitude"] = latitude
      out["longitude"] = longitude
    }

    return if (out.isEmpty()) null else out
  }

  private fun handleDecodeToWavPcm16Mono16k(
    call: MethodCall,
    result: MethodChannel.Result,
  ) {
    val args = call.arguments as? Map<*, *>
    val inputPath = (args?.get("input_path") as? String)?.trim().orEmpty()
    val outputPath = (args?.get("output_path") as? String)?.trim().orEmpty()
    val maxDecodedWavBytes = when (val raw = args?.get("max_decoded_wav_bytes")) {
      is Number -> raw.toLong()
      is String -> raw.trim().toLongOrNull()
      else -> null
    }
    if (inputPath.isEmpty() || outputPath.isEmpty()) {
      result.success(false)
      return
    }

    Thread {
      var ok = false
      var errorCode: String? = null
      var errorMessage: String? = null

      try {
        val inputFile = File(inputPath)
        if (!inputFile.exists() || !inputFile.isFile) {
          ok = false
        } else {
          val outputFile = File(outputPath)
          val writtenBytes = nativeAudioTranscribeChannelHandler.decodeToWavPcm16Mono16k(
            inputFile,
            outputFile,
            maxDecodedWavBytes = maxDecodedWavBytes,
          )
          ok = writtenBytes > 44 && outputFile.exists() && outputFile.length() > 44
          if (!ok) {
            errorCode = "audio_decode_write_failed"
            errorMessage = "decoded_wav_write_failed"
          }
        }
      } catch (error: AudioDecodeException) {
        val detail = error.message?.trim().orEmpty()
        errorCode = if (detail.isEmpty()) "audio_decode_failed" else detail
        errorMessage = detail.ifEmpty { "audio_decode_failed" }
      } catch (error: Throwable) {
        errorCode = "audio_decode_failed"
        val detail = error.message?.trim().orEmpty()
        errorMessage = detail.ifEmpty { error::class.java.simpleName }
      }

      runOnUiThread {
        if (ok) {
          result.success(true)
        } else if (errorCode != null) {
          result.error(errorCode, errorMessage ?: errorCode, null)
        } else {
          result.success(false)
        }
      }
    }.start()
  }

  private fun handleTranscodeToM4a(call: MethodCall, result: MethodChannel.Result) {
    val args = call.arguments as? Map<*, *>
    val inputPath = (args?.get("input_path") as? String)?.trim().orEmpty()
    val outputPath = (args?.get("output_path") as? String)?.trim().orEmpty()
    if (inputPath.isEmpty() || outputPath.isEmpty()) {
      result.success(false)
      return
    }

    val sampleRateHz = (args?.get("sample_rate_hz") as? Number)?.toInt() ?: 24000
    val bitrateKbps = (args?.get("bitrate_kbps") as? Number)?.toInt() ?: 48
    val mono = (args?.get("mono") as? Boolean) ?: true

    Thread {
      val ok = try {
        transcodeToM4a(
          inputPath = inputPath,
          outputPath = outputPath,
          sampleRateHz = sampleRateHz,
          bitrateKbps = bitrateKbps,
          mono = mono
        )
      } catch (_: Throwable) {
        false
      }
      runOnUiThread {
        result.success(ok)
      }
    }.start()
  }

  private fun readExif(path: String): ExifInterface? {
    return if (path.startsWith("content://")) {
      val input = contentResolver.openInputStream(Uri.parse(path)) ?: return null
      input.use { stream -> ExifInterface(stream) }
    } else {
      ExifInterface(path)
    }
  }

  private fun parseExifDateTimeMsUtc(raw: String?): Long? {
    val value = raw?.split("\u0000")?.firstOrNull()?.trim()
    if (value.isNullOrEmpty()) return null

    return try {
      val fmt = SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.US)
      fmt.timeZone = TimeZone.getDefault()
      val date = fmt.parse(value) ?: return null
      date.time
    } catch (_: Throwable) {
      null
    }
  }
}
