import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'silence.dart';

class SilenceSliderTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  final List<Silence> silences;
  final Duration duration;
  final double silencePercentage;
  const SilenceSliderTrackShape(this.silences, this.duration, this.silencePercentage);

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    @required RenderBox parentBox,
    @required SliderThemeData sliderTheme,
    @required Animation<double> enableAnimation,
    @required TextDirection textDirection,
    @required Offset thumbCenter,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final Paint activePaint = Paint()..color = sliderTheme.activeTrackColor;
    final Paint inactivePaint = Paint()..color = sliderTheme.inactiveTrackColor;
    final Paint silencePaint = Paint()..color = Colors.grey[200];
    final Paint skippedPaint = Paint()..color = Colors.white;

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    context.canvas.drawRect(Rect.fromLTWH(thumbCenter.dx, trackRect.top, trackRect.width - thumbCenter.dx + trackRect.left, trackRect.height), inactivePaint);
    for (var silence in silences) {
      double fullSilenceDurationMs = (silence.end - silence.start).toDouble();
      double silenceStart = trackRect.left + trackRect.width * silence.start / duration.inMilliseconds;
      double fullSilenceWidth = (trackRect.width * fullSilenceDurationMs / duration.inMilliseconds);
      double silenceWidth = fullSilenceWidth * silencePercentage /2;
      double skippedStart = silenceStart + silenceWidth;
      double skippedWidth = fullSilenceWidth * (1.0 - silencePercentage);

      context.canvas.drawRect(Rect.fromLTWH(silenceStart, trackRect.top, silenceWidth, trackRect.height), silencePaint);
      context.canvas.drawRect(Rect.fromLTWH(skippedStart, trackRect.top, skippedWidth, trackRect.height), skippedPaint);
      context.canvas.drawRect(Rect.fromLTWH(skippedStart + skippedWidth, trackRect.top, silenceWidth, trackRect.height), silencePaint);
    }

    context.canvas.drawRect(Rect.fromLTWH(trackRect.left, trackRect.top, thumbCenter.dx - trackRect.left, trackRect.height), activePaint);
  }
}

class RectSliderThumbShape extends SliderComponentShape {
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromWidth(3);
  }

  @override
  void paint(PaintingContext context, Offset center,
      {Animation<double> activationAnimation,
      @required Animation<double> enableAnimation,
      bool isDiscrete,
      TextPainter labelPainter,
      RenderBox parentBox,
      @required SliderThemeData sliderTheme,
      TextDirection textDirection,
      double value}) {
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 3, height: 50),
        Radius.circular(7),
      ),
      Paint()..color = sliderTheme.thumbColor,
    );
  }
}
