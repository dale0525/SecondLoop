package com.secondloop.secondloop

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import kotlin.math.abs

private const val kAudioTranscodeDurationDriftToleranceRatio = 0.08

@Suppress("UNUSED_PARAMETER")
internal fun transcodeToM4a(
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

  if (remuxAudioTrackToM4a(inputPath, outputPath)) {
    return true
  }

  var extractor: MediaExtractor? = null
  var decoder: MediaCodec? = null
  var encoder: MediaCodec? = null
  var muxer: MediaMuxer? = null
  var muxerStarted = false

  try {
    extractor = MediaExtractor()
    extractor.setDataSource(inputPath)

    val audioTrackIndex = selectFirstAudioTrack(extractor)
    if (audioTrackIndex < 0) return false
    extractor.selectTrack(audioTrackIndex)

    val inputFormat = extractor.getTrackFormat(audioTrackIndex)
    val inputMime = inputFormat.getString(MediaFormat.KEY_MIME) ?: return false
    val inputSampleRate = inputFormat.getIntegerOrDefault(
      MediaFormat.KEY_SAMPLE_RATE,
      sampleRateHz
    )
    val inputChannelCount = inputFormat.getIntegerOrDefault(MediaFormat.KEY_CHANNEL_COUNT, 2)

    // Keep encoder PCM shape aligned with decoder output.
    // This pipeline does not perform PCM resample/remix before encoding, so forcing
    // sample rate/channel changes here will stretch audio duration and corrupt transcript quality.
    val targetSampleRate = inputSampleRate
    val targetChannelCount = maxOf(1, inputChannelCount)

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

    if (!outputFile.exists() || outputFile.length() <= 0) {
      return false
    }
    if (!isAudioDurationDriftAcceptable(inputPath, outputPath)) {
      return false
    }
    return true
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

private fun remuxAudioTrackToM4a(
  inputPath: String,
  outputPath: String,
): Boolean {
  val outputFile = File(outputPath)
  var extractor: MediaExtractor? = null
  var muxer: MediaMuxer? = null
  var muxerStarted = false

  try {
    extractor = MediaExtractor()
    extractor.setDataSource(inputPath)

    val audioTrackIndex = selectFirstAudioTrack(extractor)
    if (audioTrackIndex < 0) {
      return false
    }
    extractor.selectTrack(audioTrackIndex)

    val inputFormat = extractor.getTrackFormat(audioTrackIndex)
    val inputMime = inputFormat.getString(MediaFormat.KEY_MIME) ?: return false
    if (!inputMime.startsWith("audio/")) {
      return false
    }

    muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    val muxerTrackIndex = muxer.addTrack(inputFormat)
    muxer.start()
    muxerStarted = true

    val maxInputSize = inputFormat
      .getIntegerOrDefault(MediaFormat.KEY_MAX_INPUT_SIZE, 256 * 1024)
      .coerceAtLeast(8 * 1024)
    val sampleBuffer = java.nio.ByteBuffer.allocate(maxInputSize)
    val bufferInfo = MediaCodec.BufferInfo()
    var wroteAnySample = false

    while (true) {
      sampleBuffer.clear()
      val sampleSize = extractor.readSampleData(sampleBuffer, 0)
      if (sampleSize < 0) {
        break
      }

      val sampleTimeUs = extractor.sampleTime
      if (sampleTimeUs < 0L) {
        break
      }

      bufferInfo.offset = 0
      bufferInfo.size = sampleSize
      bufferInfo.presentationTimeUs = sampleTimeUs
      bufferInfo.flags = extractor.sampleFlags

      muxer.writeSampleData(muxerTrackIndex, sampleBuffer, bufferInfo)
      wroteAnySample = true

      if (!extractor.advance()) {
        break
      }
    }

    if (!wroteAnySample) {
      return false
    }
    return outputFile.exists() && outputFile.length() > 0
  } catch (_: Throwable) {
    return false
  } finally {
    try {
      extractor?.release()
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

private fun isAudioDurationDriftAcceptable(
  inputPath: String,
  outputPath: String,
): Boolean {
  val inputDurationUs = readAudioDurationUs(inputPath) ?: return true
  val outputDurationUs = readAudioDurationUs(outputPath) ?: return true
  if (inputDurationUs <= 0L || outputDurationUs <= 0L) {
    return true
  }

  val driftRatio = abs(outputDurationUs - inputDurationUs).toDouble() /
    inputDurationUs.toDouble()
  return driftRatio <= kAudioTranscodeDurationDriftToleranceRatio
}

private fun readAudioDurationUs(path: String): Long? {
  val extractor = MediaExtractor()
  try {
    extractor.setDataSource(path)
    val audioTrackIndex = selectFirstAudioTrack(extractor)
    if (audioTrackIndex < 0) {
      return null
    }

    val format = extractor.getTrackFormat(audioTrackIndex)
    val durationFromFormatUs = format.getLongOrDefault(MediaFormat.KEY_DURATION, -1L)
    if (durationFromFormatUs > 0L) {
      return durationFromFormatUs
    }

    extractor.selectTrack(audioTrackIndex)
    var lastSampleTimeUs = -1L
    while (true) {
      val sampleTimeUs = extractor.sampleTime
      if (sampleTimeUs < 0L) {
        break
      }
      lastSampleTimeUs = sampleTimeUs
      if (!extractor.advance()) {
        break
      }
    }

    return if (lastSampleTimeUs > 0L) lastSampleTimeUs else null
  } catch (_: Throwable) {
    return null
  } finally {
    try {
      extractor.release()
    } catch (_: Throwable) {}
  }
}

private fun selectFirstAudioTrack(extractor: MediaExtractor): Int {
  for (index in 0 until extractor.trackCount) {
    val format = extractor.getTrackFormat(index)
    val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
    if (mime.startsWith("audio/")) {
      return index
    }
  }
  return -1
}

private fun MediaFormat.getIntegerOrDefault(key: String, fallback: Int): Int {
  return try {
    if (containsKey(key)) getInteger(key) else fallback
  } catch (_: Throwable) {
    fallback
  }
}

private fun MediaFormat.getLongOrDefault(key: String, fallback: Long): Long {
  return try {
    if (containsKey(key)) getLong(key) else fallback
  } catch (_: Throwable) {
    fallback
  }
}
