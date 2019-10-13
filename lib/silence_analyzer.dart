import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:path/path.dart' as path;
import 'package:skip_player/silence.dart';

class AnalysisException implements Exception {
  final String message;
  const AnalysisException(this.message);
  String toString() => message == null ? "AnalysisException" : "AnalysisException\n$message";
}

/// Analyzes the given audio file and returns the list of silence ranges found in it.
/// [tempDirPath] is a directory in which the decoded raw version of the audio file will be written.
/// [silenceAmplitudeThreshold] the negative decibel level below which silence is detected,
Future<List<Silence>> analyzeSilences(
    {@required String audioFilePath, @required String tempDirPath, double silenceThresholdDecibel = -30, int silenceThresholdMs = 1000}) async {
  assert(silenceThresholdDecibel < 0);
  assert(silenceThresholdMs > 0);

  final silences = List<Silence>();
  String tempFilePath = path.join(tempDirPath, path.basename(audioFilePath) + ".raw");

  // min and max values for a signed 16 bits int
  const minValue = -32768;
  const maxValue = 32767;
  const maxAmplitude = maxValue - minValue;

  // cf https://en.wikipedia.org/wiki/Decibel
  int silenceAmplitudeThreshold = (maxAmplitude * math.sqrt(math.pow(10, silenceThresholdDecibel / 10))).toInt();

  // convert the MP3 to mono raw audio samples (s16le = PCM signed 16-bit little-endian)
  // cf https://trac.ffmpeg.org/wiki/audio%20types
  final ffmpeg = FlutterFFmpeg();
  // ffmpeg.enableLogCallback((level, string) => print("[$level]$string"));
  var arguments = ["-y", "-i", audioFilePath, "-f", "s16le", "-ac", "1", "-c:a", "pcm_s16le", tempFilePath];
  print("ffmpeg $arguments");
  int rc = await ffmpeg.executeWithArguments(arguments);
  var output = await ffmpeg.getLastCommandOutput();
  var stats = await ffmpeg.getLastReceivedStatistics();

  print("ffmpeg exited with code $rc");
  if (rc != 0) {
    throw AnalysisException("ffmpeg exited with error code $rc:\n$output");
  }

  // kbits / sample
  double bitrate = stats["bitrate"];

  // number of samples (16 bits each) per second
  int samplesPerSecond = bitrate * 1000.0 ~/ 16;

  var bytes = await new File(tempFilePath).readAsBytes();
  int durationMs = bytes.length * 8 ~/ bitrate;

  var dur = Duration(milliseconds: durationMs);
  print(dur);

  int time = stats["time"];
  var dur2 = Duration(milliseconds: time);
  print(dur2);

  int window = samplesPerSecond ~/ 100;

  ByteData byteData = bytes.buffer.asByteData();

  int nSample = 0;
  int min = maxValue;
  int max = minValue;
  int silenceStartMs = -1;

  print('computing silences...');

  for (var i = 0; i < bytes.length; i += 2) {
    int value = byteData.getInt16(i, Endian.little);
    min = math.min(min, value);
    max = math.max(max, value);

    if (nSample % window == 0) {
      int amplitude = max - min;
      if (nSample % samplesPerSecond == 0) {
        var pos = Duration(milliseconds: nSample * 1000 ~/ samplesPerSecond);
        print("[$pos] $amplitude");
      }
      if (amplitude < silenceAmplitudeThreshold && silenceStartMs == -1) {
        silenceStartMs = nSample * 1000 ~/ samplesPerSecond;
        // print("start: $silenceStartMs");
      }

      if (amplitude >= silenceAmplitudeThreshold && silenceStartMs != -1) {
        int silenceEndMs = nSample * 1000 ~/ samplesPerSecond;
        //print("end:   $silenceEndMs");

        if (silenceEndMs - silenceStartMs > silenceThresholdMs) {
          final silence = Silence(silenceStartMs, silenceEndMs);
          print(silence);
          silences.add(silence);
        }
        silenceStartMs = -1;
      }

      min = maxValue;
      max = minValue;
    }

    nSample++;
  }

  print('done.');
  return silences;
}
