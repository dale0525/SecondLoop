package com.secondloop.secondloop

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.max
import kotlin.math.roundToInt

private const val kTargetSampleRate = 16_000
private const val kTargetChannelCount = 1

private data class DecodedPcmAudio(
  val bytes: ByteArray,
  val durationMs: Int,
)

private class AudioDecodeException(
  override val message: String,
) : RuntimeException(message)

class NativeAudioTranscribeChannelHandler {
  fun decodeToWavPcm16Mono16k(audioFile: File): ByteArray {
    if (!audioFile.exists() || !audioFile.isFile) {
      return ByteArray(0)
    }

    val pcmAudio = decodeAudioToPcm16Mono16k(audioFile)
    if (pcmAudio.bytes.isEmpty()) {
      return ByteArray(0)
    }

    return pcm16Mono16kToWav(pcmAudio.bytes)
  }

  private fun decodeAudioToPcm16Mono16k(audioFile: File): DecodedPcmAudio {
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
        throw AudioDecodeException("audio_decode_no_audio_track")
      }

      extractor.selectTrack(trackIndex)
      val format = extractor.getTrackFormat(trackIndex)
      val mimeType = format.getString(MediaFormat.KEY_MIME)
        ?: throw AudioDecodeException("audio_decode_missing_mime")

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
              ?: throw AudioDecodeException("audio_decode_input_buffer_missing")
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
    } catch (_: AudioDecodeException) {
      throw
    } catch (_: Throwable) {
      throw AudioDecodeException("audio_decode_failed")
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
      throw AudioDecodeException("audio_decode_empty")
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

      else -> throw AudioDecodeException("audio_decode_pcm_encoding_unsupported")
    }

    if (monoFloat.isEmpty()) {
      throw AudioDecodeException("audio_decode_pcm_empty")
    }

    val normalized = if (sourceSampleRate == kTargetSampleRate) {
      monoFloat
    } else {
      resampleLinear(monoFloat, sourceSampleRate, kTargetSampleRate)
    }

    if (normalized.isEmpty()) {
      throw AudioDecodeException("audio_decode_resample_empty")
    }

    val pcmBytes = monoFloatToPcm16(normalized)
    val durationMs = ((normalized.size.toLong() * 1000L) / kTargetSampleRate)
      .toInt()
      .coerceAtLeast(1)

    return DecodedPcmAudio(bytes = pcmBytes, durationMs = durationMs)
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

  private fun pcm16Mono16kToWav(pcmBytes: ByteArray): ByteArray {
    if (pcmBytes.isEmpty()) return ByteArray(0)

    val dataLength = pcmBytes.size
    val byteRate = kTargetSampleRate * kTargetChannelCount * 2
    val blockAlign = kTargetChannelCount * 2
    val buffer = ByteBuffer.allocate(44 + dataLength)
      .order(ByteOrder.LITTLE_ENDIAN)

    buffer.put("RIFF".toByteArray(Charsets.US_ASCII))
    buffer.putInt(dataLength + 36)
    buffer.put("WAVE".toByteArray(Charsets.US_ASCII))
    buffer.put("fmt ".toByteArray(Charsets.US_ASCII))
    buffer.putInt(16)
    buffer.putShort(1.toShort())
    buffer.putShort(kTargetChannelCount.toShort())
    buffer.putInt(kTargetSampleRate)
    buffer.putInt(byteRate)
    buffer.putShort(blockAlign.toShort())
    buffer.putShort(16.toShort())
    buffer.put("data".toByteArray(Charsets.US_ASCII))
    buffer.putInt(dataLength)
    buffer.put(pcmBytes)

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
