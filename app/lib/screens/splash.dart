import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Phase 1 (0–2.2s): ₹ pops, rings ripple out, everything fades.
/// Phase 2 (2.0–2.6s): balance scale, title and CTA fade up.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();
  late final _loop = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  double _seg(double ms0, double ms1, [Curve curve = Curves.linear]) {
    final t = ((_intro.value * 2600 - ms0) / (ms1 - ms0)).clamp(0.0, 1.0);
    return curve.transform(t);
  }

  void _start() {
    final signedIn = context.read<Session>().signedIn;
    Navigator.of(context).pushReplacementNamed(signedIn ? Routes.home : Routes.login);
  }

  // @keyframes rupeeZoom over 1.9s: 0→1.6 (20%) →1.4 (55%) →2.4 (80%) →2.8
  (double, double) _rupee() {
    final p = _seg(0, 1900, const Cubic(.22, 1, .36, 1));
    double lerp(double a, double b, double t) => a + (b - a) * t;
    if (p < .2) return (lerp(0, 1.6, p / .2), p / .2);
    if (p < .55) return (lerp(1.6, 1.4, (p - .2) / .35), 1);
    if (p < .8) return (lerp(1.4, 2.4, (p - .55) / .25), 1 - (p - .55) / .25);
    return (lerp(2.4, 2.8, (p - .8) / .2), 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            // CSS 160deg
            begin: Alignment(-0.34, -1),
            end: Alignment(0.34, 1),
            colors: [T.amberDark, T.amber, T.amberLight],
            stops: [0, .55, 1],
          ),
        ),
        child: AnimatedBuilder(
          animation: Listenable.merge([_intro, _loop]),
          builder: (context, _) {
            final pulse = (math.sin(_loop.value * 2 * math.pi * 2) + 1) / 2; // 2s cycle
            final phase1Opacity = 1 - _seg(1800, 2200);
            final phase2 = _seg(2000, 2600, Curves.ease);
            final (rScale, rOpacity) = _rupee();
            final bob = math.sin(_loop.value * 2 * math.pi * 4 / 3) * -5 - 5; // floatBob 3s
            return Stack(children: [
              // decorative pulsing circles
              Positioned(
                top: -90,
                right: -80,
                child: _circle(260, pulse),
              ),
              Positioned(
                bottom: -60,
                left: -60,
                child: _circle(180, 1 - pulse),
              ),
              // phase 1
              if (phase1Opacity > 0)
                Positioned.fill(
                  child: Opacity(
                    opacity: phase1Opacity,
                    child: Center(
                      child: SizedBox(
                        width: 160,
                        height: 160,
                        child: Stack(alignment: Alignment.center, children: [
                          for (final (delay, alpha) in [(100.0, .7), (300.0, .5), (500.0, .3)])
                            _ring(_seg(delay, delay + 1600, Curves.easeOut), alpha),
                          Opacity(
                            opacity: rOpacity.clamp(0, 1),
                            child: Transform.scale(
                              scale: rScale,
                              child: Text('₹', style: nun(72, w: FontWeight.w900, c: Colors.white, h: 1).copyWith(
                                shadows: [Shadow(color: Colors.white.withValues(alpha: .4), blurRadius: 40)],
                              )),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              // phase 2
              Positioned.fill(
                child: Opacity(
                  opacity: phase2,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - phase2)),
                    child: Stack(children: [
                      Positioned(left: MediaQuery.sizeOf(context).width * .08, top: MediaQuery.sizeOf(context).height * .55 + bob, child: _coin('💰', 32, 17, .15)),
                      Positioned(right: MediaQuery.sizeOf(context).width * .08, top: MediaQuery.sizeOf(context).height * .40 - bob, child: _coin('⚡', 26, 15, .1)),
                      Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Transform.translate(
                            offset: Offset(0, bob),
                            // Brand mark in a white disc, rocking like the prototype's scale.
                            child: Transform.rotate(
                              angle: math.sin(_loop.value * 2 * math.pi * 2) * 0.12,
                              child: Container(
                                width: 132,
                                height: 132,
                                padding: const EdgeInsets.all(14),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 6))],
                                ),
                                child: const BrandMark(size: 104),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text('Tarajuu', style: nun(40, w: FontWeight.w900, c: Colors.white, ls: 2)),
                          const SizedBox(height: 4),
                          Text('COMPARE SMARTER', style: pop(12, c: Colors.white.withValues(alpha: .65), ls: 2)),
                          const SizedBox(height: 6),
                          Text('तराजू — the art of balance', style: pop(11, c: Colors.white.withValues(alpha: .4))),
                          const SizedBox(height: 24),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            _dot(true),
                            const SizedBox(width: 6),
                            _dot(false),
                            const SizedBox(width: 6),
                            _dot(false),
                          ]),
                          const SizedBox(height: 28),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(26),
                              boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 18, offset: Offset(0, 4))],
                            ),
                            child: FilledButton(
                              onPressed: _start,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                disabledBackgroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                              ),
                              child: Text('Get Started →', style: nun(15, w: FontWeight.w700, c: T.amber)),
                            ),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _circle(double size, double pulse) => Transform.scale(
        scale: 1 + .08 * pulse,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .07 + .06 * pulse)),
        ),
      );

  Widget _ring(double t, double alpha) => Transform.scale(
        scale: .3 + 2.5 * t,
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: .6 * alpha / .7 * (1 - t)), width: 3),
          ),
        ),
      );

  Widget _coin(String e, double size, double font, double alpha) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: alpha)),
        child: Text(e, style: TextStyle(fontSize: font)),
      );

  Widget _dot(bool on) => Container(
        width: on ? 20 : 7,
        height: 7,
        decoration: BoxDecoration(
          color: on ? Colors.white : Colors.white.withValues(alpha: .3),
          borderRadius: BorderRadius.circular(4),
        ),
      );
}
