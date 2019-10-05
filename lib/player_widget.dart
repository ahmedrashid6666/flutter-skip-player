import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:path/path.dart' as path;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
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

  List<Silence> silences = [];
  int get totalSilence => silences.fold(0, (total, silence) => total + silence.end - silence.start + 1);
  double silencePercentage = 1.0;

  // given the current position, if we must skip return the target position, otherwise return null
  Duration targetPosition(Duration currentPosition) {
    final cur = currentPosition.inSeconds;
    for (var silence in silences) {
      int silenceDuration = silence.end - silence.start + 1;
      int playEnd = (silence.start + silenceDuration * silencePercentage).round();
      if (cur >= playEnd && cur <= silence.end - 4) {
        // skip to the end of the silence
        return Duration(seconds: silence.end);
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
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
                trackShape: SilenceSliderTrackShape(),
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
      ],
    );
  }

  List<Widget> _buildSilences() {
    if (_duration != null && silences.isNotEmpty) {
      Duration playDuration = _duration - Duration(seconds: (totalSilence * (1.0 - silencePercentage)).round());
      Duration silenceDuration = Duration(seconds: (totalSilence * silencePercentage).round());
      Duration totalSilenceDuration = Duration(seconds: totalSilence);

      return [
        SizedBox(
          height: 30.0,
        ),
        Text("${silences.length} silences, ${formatDuration(silenceDuration)}s / ${formatDuration(totalSilenceDuration)}s "),
        Text("total: ${formatDuration(playDuration)} / ${formatDuration(_duration)} "),
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
        print("seeking to : $targetPos");
        //Future.delayed(Duration(seconds: 1), () =>
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
    setState(() => silences = result);
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
