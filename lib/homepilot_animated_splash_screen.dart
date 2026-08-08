import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Purely visual, isolated startup splash overlay controller for HomePilot.
///
/// Places the animated splash visually above the already-running application child
/// for a fixed duration, fades out, and removes itself from the widget tree.
class HomePilotSplashOverlay extends StatefulWidget {
  const HomePilotSplashOverlay({
    required this.child,
    this.displayDuration = const Duration(milliseconds: 3200),
    this.fadeOutDuration = const Duration(milliseconds: 250),
    super.key,
  });

  final Widget child;
  final Duration displayDuration;
  final Duration fadeOutDuration;

  @override
  State<HomePilotSplashOverlay> createState() => _HomePilotSplashOverlayState();
}

class _HomePilotSplashOverlayState extends State<HomePilotSplashOverlay> {
  Timer? _displayTimer;
  Timer? _removalTimer;
  bool _showSplash = true;
  bool _isFadingOut = false;

  @override
  void initState() {
    super.initState();
    _displayTimer = Timer(widget.displayDuration, () {
      if (!mounted) return;
      setState(() {
        _isFadingOut = true;
      });
      _removalTimer = Timer(widget.fadeOutDuration, () {
        if (!mounted) return;
        setState(() {
          _showSplash = false;
        });
      });
    });
  }

  @override
  void dispose() {
    _displayTimer?.cancel();
    _removalTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showSplash)
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: _isFadingOut ? 0.0 : 1.0,
              duration: widget.fadeOutDuration,
              child: const HomePilotAnimatedSplashScreen(),
            ),
          ),
      ],
    );
  }
}

/// HomePilot in-app animated splash screen visual component.
///
/// Pure presentation widget for the fixed startup overlay.
class HomePilotAnimatedSplashScreen extends StatefulWidget {
  const HomePilotAnimatedSplashScreen({
    super.key,
    this.assetPath = 'assets/splash/homepilot_splash_icon_3d.png',
    this.duration = const Duration(milliseconds: 3200),
  });

  final String assetPath;
  final Duration duration;

  @override
  State<HomePilotAnimatedSplashScreen> createState() =>
      _HomePilotAnimatedSplashScreenState();
}

class _HomePilotAnimatedSplashScreenState
    extends State<HomePilotAnimatedSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _loop;

  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoLift;
  late final Animation<double> _titleOpacity;
  late final Animation<Offset> _titleOffset;
  late final Animation<double> _progressValue;
  late final Animation<double> _footerOpacity;

  static const Color _background = Color(0xFFF9FCF8);

  @override
  void initState() {
    super.initState();

    _intro = AnimationController(vsync: this, duration: widget.duration);

    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat();

    _logoOpacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.00, 0.22, curve: Curves.easeOut),
    );

    _logoScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.00, 0.42, curve: Curves.easeOutBack),
      ),
    );

    _logoLift = Tween<double>(begin: 24.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.00, 0.46, curve: Curves.easeOutCubic),
      ),
    );

    _titleOpacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.30, 0.58, curve: Curves.easeOut),
    );

    _titleOffset = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _intro,
            curve: const Interval(0.30, 0.60, curve: Curves.easeOutCubic),
          ),
        );

    _progressValue = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.44, 0.92, curve: Curves.easeInOutCubic),
      ),
    );

    _footerOpacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.62, 0.88, curve: Curves.easeOut),
    );

    _intro.forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final shortest = media.size.shortestSide;
    final logoSize = math.min(
      shortest.clamp(140.0, 430.0),
      (media.size.height * 0.38).clamp(140.0, 430.0),
    );
    final horizontalPadding = (media.size.width * 0.075).clamp(16.0, 44.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: _background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: AbsorbPointer(
        absorbing: true,
        child: Semantics(
          container: true,
          label: 'Starting HomePilot',
          value: 'Works online and offline',
          child: Scaffold(
            backgroundColor: _background,
            body: SafeArea(
              child: AnimatedBuilder(
                animation: Listenable.merge([_intro, _loop]),
                builder: (context, _) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: _HomePilotSplashBackgroundPainter(
                          loopValue: _loop.value,
                          introValue: _intro.value,
                        ),
                      ),

                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: Column(
                          children: [
                            const Spacer(flex: 9),

                            Transform.translate(
                              offset: Offset(0, _logoLift.value),
                              child: FadeTransition(
                                opacity: _logoOpacity,
                                child: ScaleTransition(
                                  scale: _logoScale,
                                  child: _AnimatedSplashIcon(
                                    assetPath: widget.assetPath,
                                    size: logoSize,
                                    loopValue: _loop.value,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 18),

                            FadeTransition(
                              opacity: _titleOpacity,
                              child: SlideTransition(
                                position: _titleOffset,
                                child: const _SplashTitle(),
                              ),
                            ),

                            const Spacer(flex: 7),

                            _LoadingSection(
                              value: _progressValue.value,
                              statusText: 'Starting HomePilot',
                              footerText: 'Works online and offline',
                              footerOpacity: _footerOpacity.value,
                            ),

                            const Spacer(flex: 3),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedSplashIcon extends StatelessWidget {
  const _AnimatedSplashIcon({
    required this.assetPath,
    required this.size,
    required this.loopValue,
  });

  final String assetPath;
  final double size;
  final double loopValue;

  static const Color _green = Color(0xFF159A3B);

  @override
  Widget build(BuildContext context) {
    final floatY = math.sin(loopValue * math.pi * 2) * 5.0;
    final tilt = math.sin(loopValue * math.pi * 2) * 0.018;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: loopValue * math.pi * 2,
            child: CustomPaint(
              size: Size(size * 0.82, size * 0.82),
              painter: _RotatingSyncRingPainter(),
            ),
          ),
          Container(
            width: size * 0.72,
            height: size * 0.72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _green.withValues(alpha: 0.20),
                  blurRadius: 54,
                  spreadRadius: 2,
                  offset: const Offset(0, 24),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 30,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: Offset(0, floatY),
            child: Transform.rotate(
              angle: tilt,
              child: Image.asset(
                assetPath,
                width: size * 0.86,
                height: size * 0.86,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          Positioned(
            right: size * 0.15,
            top: size * 0.20,
            child: _Sparkle(size: size * 0.045),
          ),
          Positioned(
            left: size * 0.17,
            bottom: size * 0.24,
            child: _Sparkle(size: size * 0.035),
          ),
        ],
      ),
    );
  }
}

class _SplashTitle extends StatelessWidget {
  const _SplashTitle();

  static const Color _navy = Color(0xFF0B1726);
  static const Color _green = Color(0xFF159A3B);
  static const Color _muted = Color(0xFF5F6B76);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = width < 380 ? 38.0 : 44.0;

    return Column(
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Home',
                style: TextStyle(
                  color: _navy,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: 0.2,
                ),
              ),
              TextSpan(
                text: 'Pilot',
                style: TextStyle(
                  color: _green,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Your tasks, routines, and reminders\nall in sync.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _muted,
            fontSize: 16.5,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _LoadingSection extends StatelessWidget {
  const _LoadingSection({
    required this.value,
    required this.statusText,
    required this.footerText,
    required this.footerOpacity,
  });

  final double value;
  final String statusText;
  final String footerText;
  final double footerOpacity;

  static const Color _green = Color(0xFF159A3B);
  static const Color _muted = Color(0xFF5F6B76);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ExcludeSemantics(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final progressWidth = math.min(310.0, constraints.maxWidth);
              return SizedBox(
                width: progressWidth,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Stack(
                    children: [
                      Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7EFE8),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: value.clamp(0.0, 1.0),
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF64D85F),
                                Color(0xFF159A3B),
                                Color(0xFF0C7A31),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _green.withValues(alpha: 0.32),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: Text(
            statusText,
            key: ValueKey<String>(statusText),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _muted,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Opacity(
          opacity: footerOpacity.clamp(0.0, 1.0),
          child: Text(
            footerText,
            style: const TextStyle(
              color: Color(0xFF7B858F),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _HomePilotSplashBackgroundPainter extends CustomPainter {
  _HomePilotSplashBackgroundPainter({
    required this.loopValue,
    required this.introValue,
  });

  final double loopValue;
  final double introValue;

  static const Color _green = Color(0xFF159A3B);
  static const Color _yellowGreen = Color(0xFFCFEA79);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF9FCF8), Color(0xFFF4FAF5), Color(0xFFFFFFFF)],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    _drawGlow(
      canvas,
      center: Offset(size.width * 0.18, size.height * 0.13),
      radius: size.width * 0.72,
      color: _green.withValues(alpha: 0.12),
    );

    _drawGlow(
      canvas,
      center: Offset(size.width * 0.86, size.height * 0.78),
      radius: size.width * 0.62,
      color: _yellowGreen.withValues(alpha: 0.13),
    );

    final orbitCenter = Offset(size.width * 0.50, size.height * 0.43);
    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..color = _green.withValues(alpha: 0.14 * introValue);

    for (var i = 0; i < 3; i++) {
      final orbitRect = Rect.fromCenter(
        center: orbitCenter,
        width: size.width * (0.82 + i * 0.16),
        height: size.width * (0.26 + i * 0.055),
      );

      canvas.save();
      canvas.translate(orbitCenter.dx, orbitCenter.dy);
      canvas.rotate(-0.20 + i * 0.13);
      canvas.translate(-orbitCenter.dx, -orbitCenter.dy);
      canvas.drawArc(
        orbitRect,
        math.pi * 0.02,
        math.pi * 1.58,
        false,
        orbitPaint,
      );
      canvas.restore();
    }

    final dotPaint = Paint()
      ..color = _green.withValues(alpha: 0.44 * introValue);
    final sparklePaint = Paint()
      ..color = _yellowGreen.withValues(alpha: 0.55 * introValue);

    for (var i = 0; i < 11; i++) {
      final angle = loopValue * math.pi * 2 + i * math.pi * 2 / 11;
      final rx = size.width * (0.36 + (i % 3) * 0.055);
      final ry = size.width * (0.11 + (i % 2) * 0.025);
      final offset = Offset(
        orbitCenter.dx + math.cos(angle) * rx,
        orbitCenter.dy + math.sin(angle) * ry,
      );
      final radius = 1.8 + (i % 3) * 0.8;
      canvas.drawCircle(offset, radius, i.isEven ? dotPaint : sparklePaint);
    }
  }

  void _drawGlow(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
  }) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _HomePilotSplashBackgroundPainter oldDelegate) {
    return oldDelegate.loopValue != loopValue ||
        oldDelegate.introValue != introValue;
  }
}

class _RotatingSyncRingPainter extends CustomPainter {
  static const Color _green = Color(0xFF159A3B);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.44;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final ringPaint = Paint()
      ..color = _green.withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.018
      ..strokeCap = StrokeCap.round;

    final accentPaint = Paint()
      ..color = _green.withValues(alpha: 0.23)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.026
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -2.70, 1.22, false, ringPaint);
    canvas.drawArc(rect, 0.35, 1.28, false, ringPaint);
    canvas.drawArc(
      rect.inflate(size.shortestSide * 0.035),
      -0.08,
      0.62,
      false,
      accentPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _SparklePainter());
  }
}

class _SparklePainter extends CustomPainter {
  static const Color _greenLight = Color(0xFFBDEB4A);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final path = Path()
      ..moveTo(c.dx, 0)
      ..quadraticBezierTo(
        c.dx + size.width * 0.13,
        c.dy - size.height * 0.13,
        size.width,
        c.dy,
      )
      ..quadraticBezierTo(
        c.dx + size.width * 0.13,
        c.dy + size.height * 0.13,
        c.dx,
        size.height,
      )
      ..quadraticBezierTo(
        c.dx - size.width * 0.13,
        c.dy + size.height * 0.13,
        0,
        c.dy,
      )
      ..quadraticBezierTo(
        c.dx - size.width * 0.13,
        c.dy - size.height * 0.13,
        c.dx,
        0,
      )
      ..close();

    canvas.drawPath(path, Paint()..color = _greenLight.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
