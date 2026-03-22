import 'package:flutter/material.dart';
import 'dart:math' as math;

class WaveformVisualizer extends StatefulWidget {
  final bool isListening;

  const WaveformVisualizer({
    Key? key,
    this.isListening = false,
  }) : super(key: key);

  @override
  State<WaveformVisualizer> createState() => _WaveformVisualizerState();
}

class _WaveformVisualizerState extends State<WaveformVisualizer>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  final List<double> _waveformData = List.generate(50, (_) => 0.5);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    if (widget.isListening) {
      _animationController.repeat();
    }
  }

  @override
  void didUpdateWidget(WaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !_animationController.isAnimating) {
      _animationController.repeat();
    } else if (!widget.isListening && _animationController.isAnimating) {
      _animationController.stop();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        // Generate random waveform data
        final random = math.Random(_animationController.value.toStringAsFixed(3).hashCode);
        for (int i = 0; i < _waveformData.length; i++) {
          _waveformData[i] = random.nextDouble() * 0.8 + 0.1;
        }

        return CustomPaint(
          painter: WaveformPainter(
            waveformData: _waveformData,
            isListening: widget.isListening,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final bool isListening;

  WaveformPainter({
    required this.waveformData,
    required this.isListening,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isListening ? Colors.green : Colors.grey
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    final centerY = size.height / 2;
    final stepX = size.width / (waveformData.length - 1);

    path.moveTo(0, centerY);

    for (int i = 0; i < waveformData.length; i++) {
      final x = i * stepX;
      final y = centerY - (waveformData[i] - 0.5) * size.height;
      path.lineTo(x, y);
    }

    canvas.drawPath(path, paint);

    // Draw frequency bars instead
    final barPaint = Paint()
      ..strokeWidth = size.width / waveformData.length * 0.7
      ..strokeCap = StrokeCap.round
      ..color = isListening ? Colors.green[400]! : Colors.grey[400]!;

    for (int i = 0; i < waveformData.length; i++) {
      final x = i * stepX + stepX / 2;
      final barHeight = waveformData[i] * size.height;
      canvas.drawLine(
        Offset(x, centerY),
        Offset(x, centerY - barHeight),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) => true;
}
