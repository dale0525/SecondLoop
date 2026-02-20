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
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterFragmentActivity() {
  private val pendingShares = mutableListOf<Map<String, String>>()
  private var shareChannel: MethodChannel? = null
  private var exifChannel: MethodChannel? = null
  private var locationChannel: MethodChannel? = null
  private var permissionsChannel: MethodChannel? = null
  private var audioTranscodeChannel: MethodChannel? = null
  private var ocrChannel: MethodChannel? = null
  private val ocrAndPdfChannelHandler by lazy {
    OcrAndPdfChannelHandler(cacheDir = cacheDir)
  }
  private val nativeAudioTranscribeChannelHandler by lazy {
    NativeAudioTranscribeChannelHandler()
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

    ocrChannel =
      MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "secondloop/ocr").apply {
        setMethodCallHandler { call, result ->
          ocrAndPdfChannelHandler.handle(call, result)
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
    intent.removeExtra(ShareReceiverActivity.EXTRA_SHARE_TYPE)
    intent.removeExtra(ShareReceiverActivity.EXTRA_SHARE_CONTENT)
    intent.removeExtra(ShareReceiverActivity.EXTRA_SHARE_MIME_TYPE)
    intent.removeExtra(ShareReceiverActivity.EXTRA_SHARE_FILENAME)
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
    if (inputPath.isEmpty() || outputPath.isEmpty()) {
      result.success(false)
      return
    }

    Thread {
      val ok = try {
        val inputFile = File(inputPath)
        if (!inputFile.exists() || !inputFile.isFile) {
          false
        } else {
          val wavBytes = nativeAudioTranscribeChannelHandler.decodeToWavPcm16Mono16k(inputFile)
          if (wavBytes.isEmpty()) {
            false
          } else {
            val outputFile = File(outputPath)
            outputFile.parentFile?.mkdirs()
            if (outputFile.exists()) {
              outputFile.delete()
            }
            outputFile.writeBytes(wavBytes)
            outputFile.exists() && outputFile.length() > 0
          }
        }
      } catch (_: Throwable) {
        false
      }

      runOnUiThread {
        result.success(ok)
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

  private fun transcodeToM4a(
    inputPath: String,
    outputPath: String,
    sampleRateHz: Int,
    bitrateKbps: Int,
    mono: Boolean
  ): Boolean {
    val outputFile = File(outputPath)
    outputFile.parentFile?.mkdirs()
    if (outputFile.exists()) {
      outputFile.delete()
    }

    var extractor: MediaExtractor? = null
    var decoder: MediaCodec? = null
    var encoder: MediaCodec? = null
    var muxer: MediaMuxer? = null
    var muxerStarted = false

    try {
      extractor = MediaExtractor()
      extractor.setDataSource(inputPath)

      var audioTrackIndex = -1
      for (i in 0 until extractor.trackCount) {
        val format = extractor.getTrackFormat(i)
        val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
        if (mime.startsWith("audio/")) {
          audioTrackIndex = i
          break
        }
      }
      if (audioTrackIndex < 0) return false
      extractor.selectTrack(audioTrackIndex)

      val inputFormat = extractor.getTrackFormat(audioTrackIndex)
      val inputMime = inputFormat.getString(MediaFormat.KEY_MIME) ?: return false
      val inputSampleRate = inputFormat.getIntegerOrDefault(
        MediaFormat.KEY_SAMPLE_RATE,
        sampleRateHz
      )
      val inputChannelCount = inputFormat.getIntegerOrDefault(MediaFormat.KEY_CHANNEL_COUNT, 2)

      val targetSampleRate = maxOf(8000, if (sampleRateHz > 0) sampleRateHz else inputSampleRate)
      val targetChannelCount = if (mono) 1 else maxOf(1, inputChannelCount)

      decoder = MediaCodec.createDecoderByType(inputMime)
      decoder.configure(inputFormat, null, null, 0)
      decoder.start()

      val encoderFormat = MediaFormat.createAudioFormat(
        "audio/mp4a-latm",
        targetSampleRate,
        targetChannelCount
      ).apply {
        setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
        setInteger(MediaFormat.KEY_BIT_RATE, maxOf(16, bitrateKbps) * 1000)
        setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 256 * 1024)
      }
      encoder = MediaCodec.createEncoderByType("audio/mp4a-latm")
      encoder.configure(encoderFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
      encoder.start()

      muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
      val bufferInfo = MediaCodec.BufferInfo()

      var muxerTrackIndex = -1
      var extractorDone = false
      var decoderDone = false
      var encoderDone = false

      while (!encoderDone) {
        if (!extractorDone) {
          val decoderInputIndex = decoder.dequeueInputBuffer(10_000)
          if (decoderInputIndex >= 0) {
            val decoderInputBuffer = decoder.getInputBuffer(decoderInputIndex)
            if (decoderInputBuffer != null) {
              val sampleSize = extractor.readSampleData(decoderInputBuffer, 0)
              if (sampleSize < 0) {
                decoder.queueInputBuffer(
                  decoderInputIndex,
                  0,
                  0,
                  0,
                  MediaCodec.BUFFER_FLAG_END_OF_STREAM
                )
                extractorDone = true
              } else {
                val sampleTimeUs = extractor.sampleTime
                decoder.queueInputBuffer(decoderInputIndex, 0, sampleSize, sampleTimeUs, 0)
                extractor.advance()
              }
            }
          }
        }

        var decoderOutputAvailable = !decoderDone
        while (decoderOutputAvailable) {
          val decoderOutputIndex = decoder.dequeueOutputBuffer(bufferInfo, 10_000)
          when {
            decoderOutputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
              decoderOutputAvailable = false
            }
            decoderOutputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
              // ignore
            }
            decoderOutputIndex >= 0 -> {
              val endOfStream = (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
              val decoderOutputBuffer = decoder.getOutputBuffer(decoderOutputIndex)

              if (decoderOutputBuffer != null && bufferInfo.size > 0) {
                decoderOutputBuffer.position(bufferInfo.offset)
                decoderOutputBuffer.limit(bufferInfo.offset + bufferInfo.size)

                var queued = false
                while (!queued) {
                  val encoderInputIndex = encoder.dequeueInputBuffer(10_000)
                  if (encoderInputIndex >= 0) {
                    val encoderInputBuffer = encoder.getInputBuffer(encoderInputIndex)
                    if (encoderInputBuffer != null) {
                      encoderInputBuffer.clear()
                      encoderInputBuffer.put(decoderOutputBuffer)
                      encoder.queueInputBuffer(
                        encoderInputIndex,
                        0,
                        bufferInfo.size,
                        bufferInfo.presentationTimeUs,
                        if (endOfStream) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0
                      )
                    }
                    queued = true
                  }
                }
              } else if (endOfStream) {
                val encoderInputIndex = encoder.dequeueInputBuffer(10_000)
                if (encoderInputIndex >= 0) {
                  encoder.queueInputBuffer(
                    encoderInputIndex,
                    0,
                    0,
                    bufferInfo.presentationTimeUs,
                    MediaCodec.BUFFER_FLAG_END_OF_STREAM
                  )
                }
              }

              decoder.releaseOutputBuffer(decoderOutputIndex, false)
              if (endOfStream) {
                decoderDone = true
                decoderOutputAvailable = false
              }
            }
          }
        }

        var encoderOutputAvailable = true
        while (encoderOutputAvailable) {
          val encoderOutputIndex = encoder.dequeueOutputBuffer(bufferInfo, 10_000)
          when {
            encoderOutputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
              encoderOutputAvailable = false
            }
            encoderOutputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
              if (muxerStarted) return false
              muxerTrackIndex = muxer.addTrack(encoder.outputFormat)
              muxer.start()
              muxerStarted = true
            }
            encoderOutputIndex >= 0 -> {
              val endOfStream = (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
              val encodedBuffer = encoder.getOutputBuffer(encoderOutputIndex)

              if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                bufferInfo.size = 0
              }
              if (encodedBuffer != null && bufferInfo.size > 0 && muxerStarted && muxerTrackIndex >= 0) {
                encodedBuffer.position(bufferInfo.offset)
                encodedBuffer.limit(bufferInfo.offset + bufferInfo.size)
                muxer.writeSampleData(muxerTrackIndex, encodedBuffer, bufferInfo)
              }

              encoder.releaseOutputBuffer(encoderOutputIndex, false)
              if (endOfStream) {
                encoderDone = true
                encoderOutputAvailable = false
              }
            }
          }
        }
      }

      return outputFile.exists() && outputFile.length() > 0
    } catch (_: Throwable) {
      return false
    } finally {
      try {
        extractor?.release()
      } catch (_: Throwable) {}
      try {
        decoder?.stop()
      } catch (_: Throwable) {}
      try {
        decoder?.release()
      } catch (_: Throwable) {}
      try {
        encoder?.stop()
      } catch (_: Throwable) {}
      try {
        encoder?.release()
      } catch (_: Throwable) {}
      if (muxerStarted) {
        try {
          muxer?.stop()
        } catch (_: Throwable) {}
      }
      try {
        muxer?.release()
      } catch (_: Throwable) {}
    }
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

private fun MediaFormat.getIntegerOrDefault(key: String, fallback: Int): Int {
  return try {
    if (containsKey(key)) getInteger(key) else fallback
  } catch (_: Throwable) {
    fallback
  }
}
