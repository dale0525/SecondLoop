package com.secondloop.secondloop

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.CancellationSignal
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.net.Uri
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

class MainActivity : FlutterFragmentActivity() {
  private val pendingShares = mutableListOf<Map<String, String>>()
  private var shareChannel: MethodChannel? = null
  private var exifChannel: MethodChannel? = null
  private var locationChannel: MethodChannel? = null
  private var permissionsChannel: MethodChannel? = null

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
    super.configureFlutterEngine(flutterEngine)
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
    val payload = mutableMapOf("type" to type, "content" to content)
    if (!mimeType.isNullOrBlank()) {
      payload["mimeType"] = mimeType
    }
    pendingShares.add(payload)
    intent.removeExtra(ShareReceiverActivity.EXTRA_SHARE_TYPE)
    intent.removeExtra(ShareReceiverActivity.EXTRA_SHARE_CONTENT)
    intent.removeExtra(ShareReceiverActivity.EXTRA_SHARE_MIME_TYPE)
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
