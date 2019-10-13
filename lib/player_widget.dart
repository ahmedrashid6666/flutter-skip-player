import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart' as pathprovider;
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

  StreamSubscription _durationSubscription;
  StreamSubscription _positionSubscription;
  StreamSubscription _playerErrorSubscription;
  StreamSubscription _playerStateSubscription;

  bool get _isPlaying => _playerState == AudioPlayerState.PLAYING;
  bool get _isPaused => _playerState == AudioPlayerState.PAUSED;
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        RaisedButton(
          child: Text("Read Silences"),
          onPressed: _readSilences,
          color: Theme.of(context).buttonColor,
        ),
        RaisedButton(
          child: Text("Compute Silences"),
          onPressed: _readSilences2,
          color: Theme.of(context).buttonColor,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: _skipBack,
              iconSize: 45.0,
              icon: Icon(Icons.settings_backup_restore),
              color: Colors.blue,
            ),
            IconButton(
              onPressed: _isPlaying ? null : _play,
              iconSize: 64.0,
              icon: Icon(Icons.play_arrow),
              color: Colors.blue,
            ),
            IconButton(
              onPressed: _isPlaying ? _audioPlayer.pause : null,
              iconSize: 64.0,
              icon: Icon(Icons.pause),
              color: Colors.blue,
            ),
            IconButton(
              onPressed: _isPlaying || _isPaused ? _audioPlayer.stop : null,
              iconSize: 64.0,
              icon: Icon(Icons.stop),
              color: Colors.blue,
            ),
            IconButton(
              onPressed: _skipForward,
              iconSize: 45.0,
              icon: Transform(
                  transform: Matrix4.identity()
                    ..translate(45.0, 0.0, 0.0)
                    ..scale(-1.0, 1.0, 1.0),
                  child: Icon(Icons.settings_backup_restore)),
              color: Colors.blue,
            ),
          ],
        ),
        SliderTheme(
          data: Theme.of(context).sliderTheme.copyWith(
                trackHeight: 30.0,
                trackShape: SilenceSliderTrackShape(silences, playedSilences, _duration, silencePercentage),
                thumbShape: RectSliderThumbShape(),
                thumbColor: Colors.blueGrey,
              ),
          child: SizedBox(
            height: 100,
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
        Text(
          _position != null ? '${_positionText ?? ''} / ${_durationText ?? ''}' : _duration != null ? _durationText : '',
          style: TextStyle(fontSize: 24.0),
        ),
        if (silences != null) ..._buildSilences(),
        SizedBox(
          height: 10,
        ),
        Container(
          decoration: BoxDecoration(shape: BoxShape.circle, color: finished ? Colors.green[100] : Colors.grey[300]),
          child: IconButton(
              icon: Icon(Icons.done),
              color: finished ? Colors.green[400] : Colors.grey[400],
              iconSize: 50,
              onPressed: () {
                final prefs = Provider.of<SharedPreferences>(context);
                setState(() {
                  prefs.setBool(widget.file.path + ".finished", !finished);
                });
              }),
        ),
      ],
    );
  }

  List<Widget> _buildSilences() {
    if (_duration != null && allSilences.isNotEmpty) {
      Duration playDuration = _duration - Duration(milliseconds: skippedSilenceMs);
      Duration silenceDuration = Duration(milliseconds: allPlayedSilenceMs);
      Duration totalSilenceDuration = Duration(milliseconds: totalSilenceMs);

      return [
        SizedBox(
          height: 30.0,
        ),
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
    List<Silence> result = List();
    final silenceFile = File(path.withoutExtension(widget.file.path) + ".silence");
    if (await silenceFile.exists()) {
      List jsonSilenceList = jsonDecode(await silenceFile.readAsString());
      for (var jsonSilence in jsonSilenceList) {
        result.add(Silence.fromJson(jsonSilence));
      }
    }
    setState(() => playedSilences = allSilences = result);
  }

  void _readSilences2() async {
    Directory tempDir = await pathprovider.getTemporaryDirectory();
    List<Silence> silences = await analyzeSilences(audioFilePath: widget.file.path, tempDirPath: tempDir.path, silenceThresholdDecibel: -20, silenceThresholdMs: 5000);
    setState(() => playedSilences = allSilences = silences);
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
}
