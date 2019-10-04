import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

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

  get _isPlaying => _playerState == AudioPlayerState.PLAYING;
  get _isPaused => _playerState == AudioPlayerState.PAUSED;
  get _durationText => _duration?.toString()?.split('.')?.first ?? '';
  get _positionText => _position?.toString()?.split('.')?.first ?? '';

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
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Slider(
              onChanged: (v) {
                final position = v * _duration.inMilliseconds;
                _audioPlayer.seek(Duration(milliseconds: position.round()));
              },
              value: (_position != null && _duration != null && _position.inMilliseconds > 0 && _position.inMilliseconds < _duration.inMilliseconds)
                  ? _position.inMilliseconds / _duration.inMilliseconds
                  : 0.0,
            ),
            Text(
              _position != null ? '${_positionText ?? ''} / ${_durationText ?? ''}' : _duration != null ? _durationText : '',
              style: TextStyle(fontSize: 24.0),
            ),
          ],
        ),
      ],
    );
  }

  void _initAudioPlayer() {
    _audioPlayer = AudioPlayer(mode: PlayerMode.MEDIA_PLAYER);

    _durationSubscription = _audioPlayer.onDurationChanged.listen((duration) {
      setState(() => _duration = duration);
    });

    _positionSubscription = _audioPlayer.onAudioPositionChanged.listen((p) {
      setState(() => _position = p);
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
  }

  void _play() {
    final url = widget.file.uri.toString();
    final playPosition =
        (_position != null && _duration != null && _position.inMilliseconds > 0 && _position.inMilliseconds < _duration.inMilliseconds) ? _position : null;
    _audioPlayer.play(url, isLocal: true, position: playPosition);
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
