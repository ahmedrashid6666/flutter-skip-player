import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:skip_player/silence.dart';

class AnalysisException implements Exception {
  final String message;
  const AnalysisException(this.message);
  String toString() => message == null ? "AnalysisException" : "AnalysisException\n$message";
}

typedef ProgressCallback = void Function(double progress);

class AnalyzerParams {
  String tempDirPath;
  double silenceThresholdDecibel;
  int silenceThresholdMs;
  SendPort sendResultPort;
  SendPort sendProgressPort;
  double bitrate;
  Uint8List rawAudioBytes;
  AnalyzerParams({
    this.tempDirPath,
    this.silenceThresholdDecibel,
    this.silenceThresholdMs,
    this.sendResultPort,
    this.sendProgressPort,
    this.bitrate,
    this.rawAudioBytes,
  });
}

Future<Uint8List> readPipe(pipeName) async {
  var pipe = File(pipeName);
  var result = await pipe.readAsBytes();
  return result;
}

/// Analyzes the given audio file and returns the list of silence ranges found in it.
/// [audioFilePath] the audio file to analyze
/// [tempDirPath] is a directory in which the decoded raw version of the audio file will be written.
/// [silenceThresholdDecibel] the negative decibel level below which silence is detected
/// [silenceThresholdMs] the minimum duration to register as silence in milliseconds
/// [progressCallback] a function that will be called with a progress percentage in the [0-100] interval
Future<List<Silence>> analyzeSilences(
    {@required String audioFilePath,
    @required String tempDirPath,
    double silenceThresholdDecibel = -30,
    int silenceThresholdMs = 1000,
    ProgressCallback progressCallback}) async {
  assert(silenceThresholdDecibel < 0);
  assert(silenceThresholdMs > 0);

  final ffmpeg = FlutterFFmpeg();
  final FlutterFFmpegConfig ffmpegConfig = new FlutterFFmpegConfig();
  final RegExp _durationRegex = RegExp(r"Duration:\s*(\d+):(\d+):(\d+)\.(\d+)");
  final RegExp _progressRegex = RegExp(r"time=(\d+):(\d+):(\d+)\.(\d+) bitrate=");
  StreamController<String> streamController;
  if (progressCallback != null) {
    streamController = StreamController<String>();
    Duration pos, dur;

    // parse ffmpeg log line by line to determine duration and progress
    streamController.stream.transform(const LineSplitter()).listen((line) {
      // print(line);
      dur ??= _durationFromMatch(_durationRegex.firstMatch(line));
      pos = _durationFromMatch(_progressRegex.firstMatch(line));
      if (dur != null && pos != null) {
        print("ffmpeg pos: $pos / $dur  (${(pos.inMilliseconds / dur.inMilliseconds * 100.0).toStringAsFixed(2)}%)");
        progressCallback?.call((pos.inMilliseconds / dur.inMilliseconds) * 0.4);
      }
    });
    // redirect ffmpeg log to a stream that emits full lines for easy parsing
    ffmpegConfig.enableLogCallback((log) {
      streamController.add("${log.level} ${log.message}");
    });
  }

  // convert the MP3 to mono raw audio samples (s16le = PCM signed 16-bit little-endian)
  // cf https://trac.ffmpeg.org/wiki/audio%20types
  // (on the main thread since native calls only work from the main thread)
  String pipeName = await ffmpegConfig.registerNewFFmpegPipe();
  //String tempFilePath = path.join(tempDirPath, path.basename(audioFilePath) + ".pcm_s16le");
  var arguments = ["-y", "-i", audioFilePath, "-f", "s16le", "-ac", "1", "-c:a", "pcm_s16le", pipeName];

  var futureBytes = compute(readPipe, pipeName);

  int rc = await ffmpeg.executeWithArguments(arguments);
  var output = await ffmpegConfig.getLastCommandOutput();
  var stats = await ffmpegConfig.getLastReceivedStatistics();
  streamController?.close();

  if (rc != 0) {
    throw AnalysisException("ffmpeg exited with error code $rc:\n$output");
  }

  // kbits / sample
  double bitrate = stats.bitrate;

  ReceivePort receiveResultPort = ReceivePort();
  ReceivePort receiveProgressPort = ReceivePort();

  var bytes = await futureBytes;
  print("Got ${bytes.length} raw audio bytes");

  final params = AnalyzerParams(
    tempDirPath: tempDirPath,
    silenceThresholdDecibel: silenceThresholdDecibel,
    silenceThresholdMs: silenceThresholdMs,
    sendResultPort: receiveResultPort.sendPort,
    sendProgressPort: progressCallback != null ? receiveProgressPort.sendPort : null,
    bitrate: bitrate,
    rawAudioBytes: bytes,
  );

  if (progressCallback != null) {
    receiveProgressPort.listen((progress) {
      progressCallback.call(progress);
    });
  }

  final completer = Completer<List<Silence>>();
  receiveResultPort.listen((silences) {
    completer.complete(silences);
  });

  final isolate = await Isolate.spawn(_doAnalyzeSilences, params, debugName: "silence_analyzer");
  final result = await completer.future;
  progressCallback?.call(null);
  receiveResultPort.close();
  receiveProgressPort.close();
  isolate.kill();

  return result;
}

Duration _durationFromMatch(RegExpMatch match) {
  if (match != null) {
    return Duration(
      hours: int.parse(match.group(1)),
      minutes: int.parse(match.group(2)),
      seconds: int.parse(match.group(3)),
      milliseconds: int.parse(match.group(4)),
    );
  }
  return null;
}

void _doAnalyzeSilences(AnalyzerParams analyzerParams) async {
  final progressPort = analyzerParams.sendProgressPort;

  final silences = List<Silence>();

  // min and max values for a signed 16 bits int
  const minValue = -32768;
  const maxValue = 32767;
  const maxAmplitude = maxValue - minValue;

  // cf https://en.wikipedia.org/wiki/Decibel
  int silenceAmplitudeThreshold = (maxAmplitude * math.sqrt(math.pow(10, analyzerParams.silenceThresholdDecibel / 10))).toInt();

  // number of samples (16 bits each) per second
  int samplesPerSecond = analyzerParams.bitrate * 1000.0 ~/ 16;

  //var bytes = await new File(analyzerParams.rawAudioTempFilePath).readAsBytes();
  //File(analyzerParams.rawAudioTempFilePath).delete();

  //int durationMs = bytes.length * 8 ~/ analyzerParams.bitrate;
  //var dur = Duration(milliseconds: durationMs);
  //print(dur);

  // int time = stats["time"];
  // var dur2 = Duration(milliseconds: time);
  // print(dur2);

  int window = samplesPerSecond ~/ 100;

  var bytes = analyzerParams.rawAudioBytes;

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
        if (progressPort != null) {
          double progress = 0.4 + (i / bytes.length) * 0.6;
          progressPort.send(progress);
        }
        // var pos = Duration(milliseconds: nSample * 1000 ~/ samplesPerSecond);
        // print("[$pos] $amplitude");
      }
      if (amplitude < silenceAmplitudeThreshold && silenceStartMs == -1) {
        silenceStartMs = nSample * 1000 ~/ samplesPerSecond;
        // print("start: $silenceStartMs");
      }

      if (amplitude >= silenceAmplitudeThreshold && silenceStartMs != -1) {
        int silenceEndMs = nSample * 1000 ~/ samplesPerSecond;
        //print("end:   $silenceEndMs");

        if (silenceEndMs - silenceStartMs > analyzerParams.silenceThresholdMs) {
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

  print('silence analysis done.');
  analyzerParams.sendResultPort.send(silences);
}
