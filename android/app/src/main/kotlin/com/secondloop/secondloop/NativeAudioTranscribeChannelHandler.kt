package com.secondloop.secondloop

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.math.max
import kotlin.math.roundToInt

private const val kNativeSttTimeoutMs = 90_000L
private const val kTargetSampleRate = 16_000
private const val kTargetChannelCount = 1

private const val kExtraAudioSource = "android.speech.extra.AUDIO_SOURCE"
private const val kExtraAudioSourceChannelCount =
  "android.speech.extra.AUDIO_SOURCE_CHANNEL_COUNT"
private const val kExtraAudioSourceEncoding =
  "android.speech.extra.AUDIO_SOURCE_ENCODING"
private const val kExtraAudioSourceSamplingRate =
  "android.speech.extra.AUDIO_SOURCE_SAMPLING_RATE"
private const val kExtraSegmentedSession =
  "android.speech.extra.SEGMENTED_SESSION"

private data class PcmAudio(
  val bytes: ByteArray,
  val durationMs: Int,
)

private class NativeSttException(
  val code: String,
  override val message: String,
) : RuntimeException(message)

class NativeAudioTranscribeChannelHandler(
  private val context: Context,
) {
  fun handle(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "nativeSttTranscribe" -> handleNativeSttTranscribe(call, result)
      else -> result.notImplemented()
    }
  }

  private fun handleNativeSttTranscribe(
    call: MethodCall,
    result: MethodChannel.Result,
  ) {
    val args = call.arguments as? Map<*, *>
    val filePath = (args?.get("file_path") as? String)?.trim().orEmpty()
    if (filePath.isEmpty()) {
      result.error("native_stt_invalid_args", "Missing file_path", null)
      return
    }

    val file = File(filePath)
    if (!file.exists() || !file.isFile) {
      result.error("native_stt_file_missing", "Audio file does not exist", null)
      return
    }

    val preferredLang = (args?.get("lang") as? String)?.trim().orEmpty()

    Thread {
      try {
        val payload = runNativeSttTranscribe(file, preferredLang)
        Handler(Looper.getMainLooper()).post {
          result.success(payload)
        }
      } catch (error: NativeSttException) {
        Handler(Looper.getMainLooper()).post {
          result.error(error.code, error.message, null)
        }
      } catch (error: Throwable) {
        val detail = error.message?.trim().orEmpty()
        Handler(Looper.getMainLooper()).post {
          result.error(
            "native_stt_failed",
            if (detail.isEmpty()) "speech_runtime_unavailable" else detail,
            null,
          )
        }
      }
    }.start()
  }

  private fun runNativeSttTranscribe(
    audioFile: File,
    preferredLang: String,
  ): Map<String, Any> {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
      throw NativeSttException(
        "native_stt_unavailable",
        "speech_runtime_unavailable",
      )
    }

    if (ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.RECORD_AUDIO,
      ) != PackageManager.PERMISSION_GRANTED
    ) {
      throw NativeSttException(
        "native_stt_failed",
        "speech_permission_denied",
      )
    }

    if (!SpeechRecognizer.isRecognitionAvailable(context)) {
      throw NativeSttException(
        "native_stt_failed",
        "speech_runtime_unavailable",
      )
    }

    if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
      throw NativeSttException(
        "native_stt_failed",
        "speech_offline_unavailable",
      )
    }

    val pcmAudio = decodeAudioToPcm16Mono16k(audioFile)
    if (pcmAudio.bytes.isEmpty()) {
      throw NativeSttException(
        "native_stt_failed",
        "speech_transcript_empty",
      )
    }

    return transcribePcmAudio(
      pcmBytes = pcmAudio.bytes,
      durationMs = pcmAudio.durationMs,
      preferredLang = preferredLang,
    )
  }

  private fun transcribePcmAudio(
    pcmBytes: ByteArray,
    durationMs: Int,
    preferredLang: String,
  ): Map<String, Any> {
    val pipe = ParcelFileDescriptor.createPipe()
    val readFd = pipe[0]
    val writeFd = pipe[1]

    var transcript: String? = null
    var errorReason: String? = null
    val done = CountDownLatch(1)
    val mainHandler = Handler(Looper.getMainLooper())

    val listener = object : RecognitionListener {
      override fun onReadyForSpeech(params: Bundle?) {}

      override fun onBeginningOfSpeech() {}

      override fun onRmsChanged(rmsdB: Float) {}

      override fun onBufferReceived(buffer: ByteArray?) {}

      override fun onEndOfSpeech() {}

      override fun onError(error: Int) {
        errorReason = normalizeRecognizerError(error)
        done.countDown()
      }

      override fun onResults(results: Bundle?) {
        val candidates =
          results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?: arrayListOf()
        transcript = candidates.firstOrNull { it.trim().isNotEmpty() }?.trim()
        if (transcript.isNullOrEmpty()) {
          errorReason = "speech_transcript_empty"
        }
        done.countDown()
      }

      override fun onPartialResults(partialResults: Bundle?) {}

      override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    val recognizerHolder = arrayOfNulls<SpeechRecognizer>(1)
    mainHandler.post {
      try {
        val recognizer = createSpeechRecognizer()
        recognizerHolder[0] = recognizer
        recognizer.setRecognitionListener(listener)
        recognizer.startListening(
          buildSpeechRecognizerIntent(
            preferredLang = preferredLang,
            readFd = readFd,
          ),
        )
      } catch (error: NativeSttException) {
        errorReason = error.message
        done.countDown()
      } catch (_: Throwable) {
        errorReason = "speech_runtime_unavailable"
        done.countDown()
      }
    }

    thread(name = "secondloop-native-stt-audio-writer") {
      try {
        FileOutputStream(writeFd.fileDescriptor).use { output ->
          output.write(pcmBytes)
          output.flush()
        }
      } catch (_: Throwable) {
        if (errorReason == null) {
          errorReason = "speech_runtime_unavailable"
        }
        done.countDown()
      } finally {
        try {
          writeFd.close()
        } catch (_: Throwable) {}
      }
    }

    val completed = done.await(kNativeSttTimeoutMs, TimeUnit.MILLISECONDS)
    mainHandler.post {
      try {
        recognizerHolder[0]?.cancel()
      } catch (_: Throwable) {}
      try {
        recognizerHolder[0]?.destroy()
      } catch (_: Throwable) {}
      try {
        readFd.close()
      } catch (_: Throwable) {}
    }

    if (!completed) {
      throw NativeSttException("native_stt_failed", "speech_runtime_unavailable")
    }

    val reason = errorReason
    if (!reason.isNullOrEmpty()) {
      throw NativeSttException("native_stt_failed", reason)
    }

    val text = transcript?.trim().orEmpty()
    if (text.isEmpty()) {
      throw NativeSttException("native_stt_failed", "speech_transcript_empty")
    }

    return mapOf(
      "text" to text,
      "duration_ms" to durationMs,
    )
  }

  private fun buildSpeechRecognizerIntent(
    preferredLang: String,
    readFd: ParcelFileDescriptor,
  ): Intent {
    val normalizedLang = normalizePreferredLang(preferredLang)

    return Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
      putExtra(
        RecognizerIntent.EXTRA_LANGUAGE_MODEL,
        RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
      )
      putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
      putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
      if (normalizedLang.isNotEmpty()) {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, normalizedLang)
      }

      putExtra(kExtraAudioSource, readFd)
      putExtra(kExtraAudioSourceChannelCount, kTargetChannelCount)
      putExtra(kExtraAudioSourceEncoding, AudioFormat.ENCODING_PCM_16BIT)
      putExtra(kExtraAudioSourceSamplingRate, kTargetSampleRate)
      putExtra(kExtraSegmentedSession, true)
    }
  }

  private fun createSpeechRecognizer(): SpeechRecognizer {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
      throw NativeSttException(
        "native_stt_failed",
        "speech_offline_unavailable",
      )
    }

    if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
      throw NativeSttException(
        "native_stt_failed",
        "speech_offline_unavailable",
      )
    }

    return try {
      SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
    } catch (_: Throwable) {
      throw NativeSttException(
        "native_stt_failed",
        "speech_offline_unavailable",
      )
    }
  }

  private fun normalizePreferredLang(lang: String): String {
    val normalized = lang.trim().replace('_', '-')
    if (normalized.isEmpty()) return ""

    val lower = normalized.lowercase(Locale.US)
    if (lower == "auto" || lower == "und" || lower == "unknown") {
      return ""
    }
    return normalized
  }

  private fun normalizeRecognizerError(error: Int): String {
    return when (error) {
      SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "speech_permission_denied"
      SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE,
      SpeechRecognizer.ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS,
      -> "speech_offline_unavailable"

      SpeechRecognizer.ERROR_AUDIO,
      SpeechRecognizer.ERROR_CLIENT,
      SpeechRecognizer.ERROR_NETWORK,
      SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
      SpeechRecognizer.ERROR_NO_MATCH,
      SpeechRecognizer.ERROR_RECOGNIZER_BUSY,
      SpeechRecognizer.ERROR_SERVER,
      SpeechRecognizer.ERROR_SERVER_DISCONNECTED,
      SpeechRecognizer.ERROR_TOO_MANY_REQUESTS,
      SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT,
      SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
      SpeechRecognizer.ERROR_SPEECH_TIMEOUT,
      -> "speech_runtime_unavailable"

      else -> "speech_runtime_unavailable"
    }
  }

  private fun decodeAudioToPcm16Mono16k(audioFile: File): PcmAudio {
    val extractor = MediaExtractor()
    val output = ByteArrayOutputStream()

    var codec: MediaCodec? = null
    var sourceSampleRate = kTargetSampleRate
    var sourceChannelCount = kTargetChannelCount
    var sourceEncoding = AudioFormat.ENCODING_PCM_16BIT

    try {
      extractor.setDataSource(audioFile.absolutePath)
      val trackIndex = selectAudioTrack(extractor)
      if (trackIndex < 0) {
        throw NativeSttException("native_stt_failed", "speech_runtime_unavailable")
      }

      extractor.selectTrack(trackIndex)
      val format = extractor.getTrackFormat(trackIndex)
      val mimeType = format.getString(MediaFormat.KEY_MIME)
        ?: throw NativeSttException("native_stt_failed", "speech_runtime_unavailable")

      codec = MediaCodec.createDecoderByType(mimeType)
      codec.configure(format, null, null, 0)
      codec.start()

      val bufferInfo = MediaCodec.BufferInfo()
      var inputEnded = false
      var outputEnded = false

      while (!outputEnded) {
        if (!inputEnded) {
          val inputBufferIndex = codec.dequeueInputBuffer(10_000)
          if (inputBufferIndex >= 0) {
            val inputBuffer = codec.getInputBuffer(inputBufferIndex)
              ?: throw NativeSttException("native_stt_failed", "speech_runtime_unavailable")
            val sampleSize = extractor.readSampleData(inputBuffer, 0)
            if (sampleSize < 0) {
              codec.queueInputBuffer(
                inputBufferIndex,
                0,
                0,
                0,
                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
              )
              inputEnded = true
            } else {
              codec.queueInputBuffer(
                inputBufferIndex,
                0,
                sampleSize,
                extractor.sampleTime,
                0,
              )
              extractor.advance()
            }
          }
        }

        val outputBufferIndex = codec.dequeueOutputBuffer(bufferInfo, 10_000)
        when {
          outputBufferIndex >= 0 -> {
            val outputBuffer = codec.getOutputBuffer(outputBufferIndex)
            if (outputBuffer != null && bufferInfo.size > 0) {
              outputBuffer.position(bufferInfo.offset)
              outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
              val chunk = ByteArray(bufferInfo.size)
              outputBuffer.get(chunk)
              output.write(chunk)
            }
            codec.releaseOutputBuffer(outputBufferIndex, false)
            if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
              outputEnded = true
            }
          }

          outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
            val outputFormat = codec.outputFormat
            sourceSampleRate = outputFormat.intOrDefault(
              MediaFormat.KEY_SAMPLE_RATE,
              sourceSampleRate,
            )
            sourceChannelCount = max(
              1,
              outputFormat.intOrDefault(
                MediaFormat.KEY_CHANNEL_COUNT,
                sourceChannelCount,
              ),
            )
            sourceEncoding = outputFormat.intOrDefault(
              MediaFormat.KEY_PCM_ENCODING,
              sourceEncoding,
            )
          }
        }
      }
    } catch (error: NativeSttException) {
      throw error
    } catch (_: Throwable) {
      throw NativeSttException("native_stt_failed", "speech_runtime_unavailable")
    } finally {
      try {
        codec?.stop()
      } catch (_: Throwable) {}
      try {
        codec?.release()
      } catch (_: Throwable) {}
      try {
        extractor.release()
      } catch (_: Throwable) {}
      try {
        output.close()
      } catch (_: Throwable) {}
    }

    val decoded = output.toByteArray()
    if (decoded.isEmpty()) {
      throw NativeSttException("native_stt_failed", "speech_runtime_unavailable")
    }

    val monoFloat = when (sourceEncoding) {
      AudioFormat.ENCODING_PCM_16BIT -> pcm16ToMonoFloat(
        decoded,
        sourceChannelCount,
      )

      AudioFormat.ENCODING_PCM_FLOAT -> pcmFloatToMonoFloat(
        decoded,
        sourceChannelCount,
      )

      else -> throw NativeSttException(
        "native_stt_failed",
        "speech_runtime_unavailable",
      )
    }

    if (monoFloat.isEmpty()) {
      throw NativeSttException("native_stt_failed", "speech_runtime_unavailable")
    }

    val normalized = if (sourceSampleRate == kTargetSampleRate) {
      monoFloat
    } else {
      resampleLinear(monoFloat, sourceSampleRate, kTargetSampleRate)
    }

    if (normalized.isEmpty()) {
      throw NativeSttException("native_stt_failed", "speech_runtime_unavailable")
    }

    val pcmBytes = monoFloatToPcm16(normalized)
    val durationMs = ((normalized.size.toLong() * 1000L) / kTargetSampleRate)
      .toInt()
      .coerceAtLeast(1)

    return PcmAudio(bytes = pcmBytes, durationMs = durationMs)
  }

  private fun selectAudioTrack(extractor: MediaExtractor): Int {
    for (index in 0 until extractor.trackCount) {
      val format = extractor.getTrackFormat(index)
      val mimeType = format.getString(MediaFormat.KEY_MIME) ?: continue
      if (mimeType.startsWith("audio/")) {
        return index
      }
    }
    return -1
  }

  private fun pcm16ToMonoFloat(
    pcmBytes: ByteArray,
    channelCount: Int,
  ): FloatArray {
    if (pcmBytes.isEmpty() || channelCount <= 0) return FloatArray(0)

    val shortCount = pcmBytes.size / 2
    if (shortCount == 0) return FloatArray(0)

    val samples = ShortArray(shortCount)
    ByteBuffer.wrap(pcmBytes)
      .order(ByteOrder.LITTLE_ENDIAN)
      .asShortBuffer()
      .get(samples)

    val frameCount = shortCount / channelCount
    if (frameCount == 0) return FloatArray(0)

    val mono = FloatArray(frameCount)
    var sampleIndex = 0
    for (frame in 0 until frameCount) {
      var sum = 0f
      for (channel in 0 until channelCount) {
        sum += samples[sampleIndex].toFloat() / Short.MAX_VALUE.toFloat()
        sampleIndex += 1
      }
      mono[frame] = sum / channelCount.toFloat()
    }

    return mono
  }

  private fun pcmFloatToMonoFloat(
    pcmBytes: ByteArray,
    channelCount: Int,
  ): FloatArray {
    if (pcmBytes.isEmpty() || channelCount <= 0) return FloatArray(0)

    val floatCount = pcmBytes.size / 4
    if (floatCount == 0) return FloatArray(0)

    val samples = FloatArray(floatCount)
    ByteBuffer.wrap(pcmBytes)
      .order(ByteOrder.LITTLE_ENDIAN)
      .asFloatBuffer()
      .get(samples)

    val frameCount = floatCount / channelCount
    if (frameCount == 0) return FloatArray(0)

    val mono = FloatArray(frameCount)
    var sampleIndex = 0
    for (frame in 0 until frameCount) {
      var sum = 0f
      for (channel in 0 until channelCount) {
        sum += samples[sampleIndex]
        sampleIndex += 1
      }
      mono[frame] = sum / channelCount.toFloat()
    }

    return mono
  }

  private fun resampleLinear(
    monoSamples: FloatArray,
    sourceRate: Int,
    targetRate: Int,
  ): FloatArray {
    if (monoSamples.isEmpty()) return FloatArray(0)
    if (sourceRate <= 0 || targetRate <= 0) return monoSamples
    if (sourceRate == targetRate) return monoSamples

    val outputCount = max(
      1,
      ((monoSamples.size.toLong() * targetRate) / sourceRate).toInt(),
    )
    val output = FloatArray(outputCount)

    for (index in 0 until outputCount) {
      val sourcePosition = index.toDouble() * sourceRate.toDouble() / targetRate.toDouble()
      val base = sourcePosition.toInt().coerceIn(0, monoSamples.size - 1)
      val next = (base + 1).coerceAtMost(monoSamples.size - 1)
      val fraction = (sourcePosition - base.toDouble()).toFloat()
      val value = monoSamples[base] + (monoSamples[next] - monoSamples[base]) * fraction
      output[index] = value
    }

    return output
  }

  private fun monoFloatToPcm16(samples: FloatArray): ByteArray {
    val buffer = ByteBuffer.allocate(samples.size * 2)
      .order(ByteOrder.LITTLE_ENDIAN)

    for (sample in samples) {
      val clamped = sample.coerceIn(-1.0f, 1.0f)
      val pcm = (clamped * Short.MAX_VALUE.toFloat()).roundToInt()
        .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
      buffer.putShort(pcm.toShort())
    }

    return buffer.array()
  }

  private fun MediaFormat.intOrDefault(
    key: String,
    fallback: Int,
  ): Int {
    return if (containsKey(key)) {
      getInteger(key)
    } else {
      fallback
    }
  }
}
