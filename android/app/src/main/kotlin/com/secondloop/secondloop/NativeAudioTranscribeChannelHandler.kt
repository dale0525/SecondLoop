package com.secondloop.secondloop

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.max
import kotlin.math.roundToInt

private const val kTargetSampleRate = 16_000
private const val kTargetChannelCount = 1
private const val kDefaultMaxDecodedWavBytes = 96 * 1024 * 1024

class AudioDecodeException(
  override val message: String,
) : RuntimeException(message)

class NativeAudioTranscribeChannelHandler {
  fun decodeToWavPcm16Mono16k(
    audioFile: File,
    outputFile: File,
    maxDecodedWavBytes: Long? = null,
  ): Int {
    if (!audioFile.exists() || !audioFile.isFile) {
      return 0
    }

    outputFile.parentFile?.mkdirs()
    if (outputFile.exists()) {
      outputFile.delete()
    }

    RandomAccessFile(outputFile, "rw").use { output ->
      output.setLength(0)
      output.write(ByteArray(44))

      val dataLength = decodeAudioToPcm16Mono16k(
        audioFile,
        maxDecodedWavBytes = maxDecodedWavBytes,
        onPcmChunk = { pcmChunk ->
          output.write(pcmChunk)
        },
      )
      if (dataLength <= 0) {
        throw AudioDecodeException("audio_decode_empty")
      }

      writeWavHeader(output, dataLength)
      output.fd.sync()
      return 44 + dataLength
    }
  }

  private fun decodeAudioToPcm16Mono16k(
    audioFile: File,
    maxDecodedWavBytes: Long? = null,
    onPcmChunk: (ByteArray) -> Unit,
  ): Int {
    val extractor = MediaExtractor()

    var codec: MediaCodec? = null
    var sourceSampleRate = kTargetSampleRate
    var sourceChannelCount = kTargetChannelCount
    var sourceEncoding = AudioFormat.ENCODING_PCM_16BIT
    var totalPcmBytes = 0
    val decodeByteLimit = when {
      maxDecodedWavBytes == null -> kDefaultMaxDecodedWavBytes.toLong()
      maxDecodedWavBytes <= 0L -> Long.MAX_VALUE
      else -> maxDecodedWavBytes
    }

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

      sourceSampleRate = format.intOrDefault(
        MediaFormat.KEY_SAMPLE_RATE,
        sourceSampleRate,
      )
      sourceChannelCount = max(
        1,
        format.intOrDefault(
          MediaFormat.KEY_CHANNEL_COUNT,
          sourceChannelCount,
        ),
      )
      sourceEncoding = format.intOrDefault(
        MediaFormat.KEY_PCM_ENCODING,
        sourceEncoding,
      )

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

              val decodedChunk = ByteArray(bufferInfo.size)
              outputBuffer.get(decodedChunk)
              val pcmChunk = decodeChunkToTargetPcm(
                decodedChunk,
                sourceSampleRate = sourceSampleRate,
                sourceChannelCount = sourceChannelCount,
                sourceEncoding = sourceEncoding,
              )
              if (pcmChunk.isNotEmpty()) {
                val nextLength = totalPcmBytes.toLong() + pcmChunk.size.toLong()
                if (nextLength > decodeByteLimit) {
                  throw AudioDecodeException("audio_decode_too_long")
                }
                onPcmChunk(pcmChunk)
                totalPcmBytes = nextLength.toInt()
              }
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
    } catch (error: AudioDecodeException) {
      throw error
    } catch (_: OutOfMemoryError) {
      throw AudioDecodeException("audio_decode_oom")
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
    }

    if (totalPcmBytes <= 0) {
      throw AudioDecodeException("audio_decode_empty")
    }

    return totalPcmBytes
  }

  private fun decodeChunkToTargetPcm(
    chunkBytes: ByteArray,
    sourceSampleRate: Int,
    sourceChannelCount: Int,
    sourceEncoding: Int,
  ): ByteArray {
    if (chunkBytes.isEmpty()) {
      return ByteArray(0)
    }

    val normalizedChannelCount = max(1, sourceChannelCount)

    if (sourceEncoding == AudioFormat.ENCODING_PCM_16BIT &&
      sourceSampleRate == kTargetSampleRate &&
      normalizedChannelCount == kTargetChannelCount
    ) {
      val trimmedLength = chunkBytes.size - (chunkBytes.size % 2)
      if (trimmedLength <= 0) {
        return ByteArray(0)
      }
      if (trimmedLength == chunkBytes.size) {
        return chunkBytes
      }
      return chunkBytes.copyOf(trimmedLength)
    }

    val monoFloat = when (sourceEncoding) {
      AudioFormat.ENCODING_PCM_16BIT -> pcm16ToMonoFloat(
        chunkBytes,
        chunkBytes.size,
        normalizedChannelCount,
      )

      AudioFormat.ENCODING_PCM_FLOAT -> pcmFloatToMonoFloat(
        chunkBytes,
        chunkBytes.size,
        normalizedChannelCount,
      )

      else -> throw AudioDecodeException("audio_decode_pcm_encoding_unsupported")
    }

    if (monoFloat.isEmpty()) {
      return ByteArray(0)
    }

    val normalized = if (sourceSampleRate == kTargetSampleRate) {
      monoFloat
    } else {
      resampleLinear(monoFloat, sourceSampleRate, kTargetSampleRate)
    }

    if (normalized.isEmpty()) {
      return ByteArray(0)
    }

    return monoFloatToPcm16(normalized)
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
    byteLength: Int,
    channelCount: Int,
  ): FloatArray {
    if (byteLength <= 0 || channelCount <= 0) return FloatArray(0)

    val shortCount = byteLength / 2
    if (shortCount == 0) return FloatArray(0)

    val frameCount = shortCount / channelCount
    if (frameCount == 0) return FloatArray(0)

    val mono = FloatArray(frameCount)
    val shortBuffer = ByteBuffer.wrap(pcmBytes, 0, shortCount * 2)
      .order(ByteOrder.LITTLE_ENDIAN)
      .asShortBuffer()
    for (frame in 0 until frameCount) {
      var sum = 0f
      for (channel in 0 until channelCount) {
        sum += shortBuffer.get().toFloat() / Short.MAX_VALUE.toFloat()
      }
      mono[frame] = sum / channelCount.toFloat()
    }

    return mono
  }

  private fun pcmFloatToMonoFloat(
    pcmBytes: ByteArray,
    byteLength: Int,
    channelCount: Int,
  ): FloatArray {
    if (byteLength <= 0 || channelCount <= 0) return FloatArray(0)

    val floatCount = byteLength / 4
    if (floatCount == 0) return FloatArray(0)

    val frameCount = floatCount / channelCount
    if (frameCount == 0) return FloatArray(0)

    val mono = FloatArray(frameCount)
    val floatBuffer = ByteBuffer.wrap(pcmBytes, 0, floatCount * 4)
      .order(ByteOrder.LITTLE_ENDIAN)
      .asFloatBuffer()
    for (frame in 0 until frameCount) {
      var sum = 0f
      for (channel in 0 until channelCount) {
        sum += floatBuffer.get()
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

  private fun writeWavHeader(output: RandomAccessFile, dataLength: Int) {
    val byteRate = kTargetSampleRate * kTargetChannelCount * 2
    val blockAlign = kTargetChannelCount * 2
    val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)

    header.put("RIFF".toByteArray(Charsets.US_ASCII))
    header.putInt(dataLength + 36)
    header.put("WAVE".toByteArray(Charsets.US_ASCII))
    header.put("fmt ".toByteArray(Charsets.US_ASCII))
    header.putInt(16)
    header.putShort(1.toShort())
    header.putShort(kTargetChannelCount.toShort())
    header.putInt(kTargetSampleRate)
    header.putInt(byteRate)
    header.putShort(blockAlign.toShort())
    header.putShort(16.toShort())
    header.put("data".toByteArray(Charsets.US_ASCII))
    header.putInt(dataLength)

    output.seek(0)
    output.write(header.array())
  }

  private fun MediaFormat.intOrDefault(
    key: String,
    defaultValue: Int,
  ): Int {
    if (!containsKey(key)) return defaultValue
    return try {
      getInteger(key)
    } catch (_: Throwable) {
      defaultValue
    }
  }
}
