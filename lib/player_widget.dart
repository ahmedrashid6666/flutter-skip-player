import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart' hide BuildContext;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart' as pathprovider;
import 'package:skip_player/prefs.dart';
import 'package:skip_player/silence_analyzer.dart';
import 'slider.dart';
import 'silence.dart';

class PlayerWidget extends StatefulWidget {
  final File file;
  PlayerWidget(this.file);

  @override
  State<StatefulWidget> createState() => _PlayerWidgetState();
}

class _PlayerWidgetState extends State<PlayerWidget> {
  AudioPlayer _audioPlayer;
  AudioPlayerState _playerState;
  Duration _duration;
  Duration _position;
  double analysisProgress;

  StreamSubscription _durationSubscription;
  StreamSubscription _positionSubscription;
  StreamSubscription _playerErrorSubscription;
  StreamSubscription _playerStateSubscription;

  bool get _isPlaying => _playerState == AudioPlayerState.PLAYING;
  String get _durationText => formatDuration(_duration);
  String get _positionText => formatDuration(_position);
  String formatDuration(Duration duration) => duration?.toString()?.split('.')?.first ?? '';

  List<Silence> allSilences = [];
  List<Silence> silences = [];
  List<Silence> playedSilences = [];
  int get playedSilenceMs => playedSilences.fold(0, (total, silence) => total + silence.end - silence.start);
  int get silenceMs => silences.fold(0, (total, silence) => total + silence.end - silence.start);
  int get allPlayedSilenceMs => playedSilenceMs + (silenceMs * silencePercentage).round();
  int get skippedSilenceMs => (silenceMs * (1.0 - silencePercentage)).round();
  int get totalSilenceMs => playedSilenceMs + silenceMs;
  double silencePercentage = 1.0;
  String get silenceFilePath => path.withoutExtension(widget.file.path) + ".silence";

  // given the current position, if we must skip return the target position, otherwise return null
  Duration targetPosition(Duration currentPosition) {
    final cur = currentPosition.inMilliseconds;
    for (var silence in silences) {
      int silenceDuration = silence.end - silence.start;
      int skippedDuration = (silenceDuration * (1.0 - silencePercentage)).round();
      int silenceMiddle = (silence.start + silenceDuration / 2).round();
      int skippedStart = (silenceMiddle - skippedDuration / 2).round();
      int skippedEnd = (silenceMiddle + skippedDuration / 2).round();

      if (cur >= skippedStart && cur < skippedEnd) {
        // skip to the end of the silence
        return Duration(milliseconds: skippedEnd);
      }
    }
    // don't skip
    return null;
  }

  @override
  void initState() {
    super.initState();
    _initAudioPlayer();
    _readSilences();
  }

  @override
  void dispose() {
    _audioPlayer.stop();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _playerErrorSubscription?.cancel();
    _playerStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = Provider.of<SharedPreferences>(context);
    final finished = prefs?.getBool(widget.file.path + ".finished") ?? false;
    const buttonPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 6);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (analysisProgress != null)
          LinearProgressIndicator(
            value: analysisProgress,
          ),
        Expanded(flex: 10, child: Container()),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          mainAxisSize: MainAxisSize.max,
          children: [
            IconButton(
              padding: buttonPadding,
              onPressed: _skipBack,
              iconSize: 45.0,
              icon: Icon(Icons.settings_backup_restore),
              color: Colors.blue,
            ),
            IconButton(
              padding: buttonPadding,
              onPressed: _isPlaying ? _audioPlayer.pause : _play,
              iconSize: 64.0,
              icon: Icon(_isPlaying ? Icons.pause_circle_outline : Icons.play_circle_outline),
              color: Colors.blue,
            ),
            IconButton(
              padding: buttonPadding,
              onPressed: _skipForward,
              iconSize: 45.0,
              icon: Transform(
                // flip horizontally
                alignment: AlignmentDirectional.center,
                transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
                child: Icon(Icons.settings_backup_restore),
              ),
              color: Colors.blue,
            ),
          ],
        ),
        SizedBox(
          height: 30,
          child: SliderTheme(
            data: Theme.of(context).sliderTheme.copyWith(
                  trackHeight: 30.0,
                  trackShape: SilenceSliderTrackShape(silences, playedSilences, _duration, silencePercentage, Theme.of(context).scaffoldBackgroundColor),
                  thumbShape: RectSliderThumbShape(),
                  thumbColor: Colors.blueGrey,
                ),
            child: Slider(
              onChanged: (v) {
                final position = v * _duration.inMilliseconds;
                _audioPlayer.seek(Duration(milliseconds: position.round()));
              },
              value: (_position != null && _duration != null && _position.inMilliseconds > 0 && _position.inMilliseconds < _duration.inMilliseconds)
                  ? _position.inMilliseconds / _duration.inMilliseconds
                  : 0.0,
            ),
          ),
        ),
        SizedBox(height: 4),
        Expanded(flex: 1, child: Container()),
        Text(
          _position != null ? '${_positionText ?? ''} / ${_durationText ?? ''}' : _duration != null ? _durationText : '',
          style: TextStyle(fontSize: 24.0),
        ),
        Expanded(flex: 5, child: Container()),
        if (silences != null) ..._buildSilences(),
        Expanded(flex: 1, child: Container()),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            FlatButton(
              child: Text("Recompute Silences"),
              onPressed: () async {
                final silenceFile = File(silenceFilePath);
                setState(() {
                  playedSilences = allSilences = List();
                });
                if (await silenceFile.exists()) {
                  await silenceFile.delete();
                }
                _readSilences();
              },
              color: Theme.of(context).buttonColor,
            ),
            Container(
              decoration: BoxDecoration(shape: BoxShape.circle, color: finished ? Colors.green[100] : Theme.of(context).buttonColor),
              child: IconButton(
                icon: Icon(Icons.done),
                color: finished ? Colors.green[400] : Theme.of(context).disabledColor,
                iconSize: 32,
                onPressed: () {
                  final prefs = Provider.of<SharedPreferences>(context);
                  setState(() {
                    prefs.setBool(widget.file.path + ".finished", !finished);
                  });
                },
              ),
            ),
          ],
        ),
        Expanded(flex: 1, child: Container()),
      ],
    );
  }

  List<Widget> _buildSilences() {
    if (_duration != null && allSilences.isNotEmpty) {
      Duration playDuration = _duration - Duration(milliseconds: skippedSilenceMs);
      Duration silenceDuration = Duration(milliseconds: allPlayedSilenceMs);
      Duration totalSilenceDuration = Duration(milliseconds: totalSilenceMs);

      return [
        Expanded(flex: 1, child: Container()),
        Text("${allSilences.length} silences, ${formatDuration(silenceDuration)}s / ${formatDuration(totalSilenceDuration)}s "),
        Text("total: ${formatDuration(playDuration)} / ${formatDuration(_duration)} "),
        Slider(
          min: 0,
          max: allSilences.length.toDouble(),
          divisions: allSilences.length,
          onChanged: (n) {
            setState(() {
              List<Silence> sorted = List.from(allSilences);
              sorted.sort((s1, s2) => (s1.end - s1.start).compareTo(s2.end - s2.start));
              playedSilences = sorted.sublist(0, n.round());
              silences = sorted.sublist(n.round());
            });
          },
          value: playedSilences.length.toDouble(),
        ),
        Slider(
          onChanged: (v) {
            setState(() {
              silencePercentage = v;
            });
          },
          value: silencePercentage,
        ),
      ];
    } else {
      return [];
    }
  }

  int lastSeekTime = 0;

  void _positionChanged(Duration p) {
    final targetPos = targetPosition(p);
    if (targetPos != null) {
      int now = DateTime.now().millisecondsSinceEpoch;
      if (!_isPlaying || now - lastSeekTime > 1000) {
        _audioPlayer.seek(targetPos);
        lastSeekTime = now;
      } else {
        setState(() => _position = p);
      }
    } else {
      setState(() => _position = p);
    }
  }

  void _initAudioPlayer() {
    _audioPlayer = AudioPlayer(mode: PlayerMode.MEDIA_PLAYER);

    _durationSubscription = _audioPlayer.onDurationChanged.listen((duration) {
      setState(() => _duration = duration);
    });

    _positionSubscription = _audioPlayer.onAudioPositionChanged.listen((p) {
      _positionChanged(p);
    });

    _playerErrorSubscription = _audioPlayer.onPlayerError.listen((msg) {
      print('audioPlayer error : $msg');
      setState(() {
        _playerState = AudioPlayerState.STOPPED;
        _duration = Duration(seconds: 0);
        _position = Duration(seconds: 0);
      });
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playerState = state);
    });

    _audioPlayer.setUrl(widget.file.uri.toString());
  }

  void _readSilences() async {
    List<Silence> result;
    final silenceFile = File(silenceFilePath);
    if (await silenceFile.exists()) {
      List jsonSilenceList = jsonDecode(await silenceFile.readAsString());
      if (jsonSilenceList != null) {
        result = List();
        for (var jsonSilence in jsonSilenceList) {
          result.add(Silence.fromJson(jsonSilence));
        }
      }
    }
    if (result == null) {
      Directory tempDir = await pathprovider.getTemporaryDirectory();
      try {
        result = await analyzeSilences(
            audioFilePath: widget.file.path,
            tempDirPath: tempDir.path,
            silenceThresholdDecibel: -30,
            silenceThresholdMs: 5000,
            progressCallback: (p) {
              setState(() {
                analysisProgress = p;
              });
            });
      } catch (e) {
        _showErrorDialog(e);
      }
      if (Provider.of<CreateSilenceFilesPref>(context, listen: false).value) {
        final json = jsonEncode(result);
        silenceFile.writeAsString(json);
      }
    }
    if (result != null) {
      setState(() {
        playedSilences = allSilences = result;
      });
    }
  }

  void _play() {
    final url = widget.file.uri.toString();
    final playPosition =
        (_position != null && _duration != null && _position.inMilliseconds > 0 && _position.inMilliseconds < _duration.inMilliseconds) ? _position : null;
    _audioPlayer.play(url, isLocal: true, position: playPosition, stayAwake: true);
  }

  void _skipBack() {
    final newPosition = math.max(_position.inMilliseconds - 5000.0, 0.0);
    _audioPlayer.seek(Duration(milliseconds: newPosition.round()));
  }

  void _skipForward() {
    final newPosition = math.min(_position.inMilliseconds + 5000.0, _duration.inMilliseconds);
    _audioPlayer.seek(Duration(milliseconds: newPosition.round()));
  }

  void _showErrorDialog(e) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Error"),
          content: SingleChildScrollView(child: Text(e.toString())),
        );
      },
    );
  }
}
