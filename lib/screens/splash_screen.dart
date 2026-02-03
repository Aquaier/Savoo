import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SavooSplashScreen extends StatefulWidget {
  const SavooSplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<SavooSplashScreen> createState() => _SavooSplashScreenState();
}

class _SavooSplashScreenState extends State<SavooSplashScreen> {
  late final Timer _timer;
  String _text = 'Savoo';
  double _scale = 1.0;

  static const _stages = <String>[
    'Savoo',
    'Save',
    'Save your',
    'Save your money',
    'Save your money today',
  ];

  static const _scaleStages = <double>[1.0, 1.16, 1.22, 1.28, 1.34];

  @override
  void initState() {
    super.initState();
    _scheduleAnimation();
  }

  void _scheduleAnimation() {
    const stepDelay = Duration(milliseconds: 700);
    for (var i = 1; i < _stages.length; i++) {
      Future.delayed(stepDelay * i, () {
        if (!mounted) return;
        setState(() {
          _text = _stages[i];
          _scale = _scaleStages[i];
        });
      });
    }

    _timer = Timer(
      stepDelay * _stages.length + const Duration(milliseconds: 600),
      () {
        if (!mounted) return;
        widget.onFinished();
      },
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradient = LinearGradient(
      colors: [
        theme.colorScheme.primary.withValues(alpha: 0.85),
        theme.colorScheme.secondary.withValues(alpha: 0.85),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: gradient),
        child: Center(
          child: AnimatedScale(
            scale: _scale,
            duration: const Duration(milliseconds: 480),
            curve: Curves.easeOutBack,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              style: GoogleFonts.poppins(
                textStyle: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: const Color(0xFF1ABC9C),
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      offset: const Offset(2, 2),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              child: Text(_text, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}
