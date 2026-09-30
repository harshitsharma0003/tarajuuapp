import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../routes.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/svgs.dart';

String _err(Object e) => e.toString().replaceFirst('Exception: ', '');

// ═══════════════════════════ LOGIN ═══════════════════════════

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  bool _bad = false, _busy = false, _gBusy = false;

  Future<void> _sendOtp() async {
    final p = _phone.text.trim();
    if (p.length < 10) {
      setState(() => _bad = true);
      Timer(const Duration(milliseconds: 1800), () => mounted ? setState(() => _bad = false) : null);
      return;
    }
    setState(() => _busy = true);
    try {
      final autoVerified = await context.read<Session>().sendOtp(p);
      if (!mounted) return;
      if (autoVerified) {
        Navigator.of(context).pushNamedAndRemoveUntil(Routes.home, (_) => false);
      } else {
        Navigator.of(context).pushNamed(Routes.otp);
      }
    } catch (e) {
      if (mounted) toast(context, _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    if (!Config.googleSignInEnabled) {
      toast(context, 'Google sign-in is coming soon — please use your mobile number.');
      return;
    }
    setState(() => _gBusy = true);
    try {
      await context.read<Session>().signInWithGoogle();
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil(Routes.home, (_) => false);
    } catch (e) {
      if (mounted) toast(context, _err(e));
    } finally {
      if (mounted) setState(() => _gBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [
            const AuthHeader('COMPARE SMARTER'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Welcome back 👋', style: pop(18, w: FontWeight.w700, c: T.amberDark)),
                const SizedBox(height: 3),
                Text('Sign in with mobile OTP or Google', style: pop(12, c: T.gray)),
                const SizedBox(height: 18),
                const FieldLabel('Mobile Number'),
                Row(children: [
                  const FlagBox(),
                  const SizedBox(width: 7),
                  Expanded(child: _PhoneField(_phone, error: _bad, onSubmit: _sendOtp)),
                ]),
                const SizedBox(height: 18),
                AmberButton('Send OTP →', onPressed: _sendOtp, busy: _busy),
                const _OrDivider(),
                _GoogleButton(onPressed: _gBusy ? null : _google, busy: _gBusy),
                const SizedBox(height: 14),
                Center(
                  child: Text.rich(TextSpan(style: pop(12, c: T.gray), children: [
                    const TextSpan(text: 'New here? '),
                    TextSpan(
                      text: 'Create an account',
                      style: pop(12, w: FontWeight.w600, c: T.amber),
                      recognizer: TapGestureRecognizer()..onTap = () => Navigator.of(context).pushNamed(Routes.signup),
                    ),
                  ])),
                ),
              ]),
            ),
          ]),
        ),
      );
}

class _PhoneField extends StatelessWidget {
  final TextEditingController c;
  final bool error;
  final VoidCallback? onSubmit;
  const _PhoneField(this.c, {this.error = false, this.onSubmit});
  @override
  Widget build(BuildContext context) => TextField(
        controller: c,
        keyboardType: TextInputType.phone,
        maxLength: 10,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: pop(13, c: const Color(0xFF333333)),
        decoration: amberInput('10-digit number', error: error),
        onSubmitted: (_) => onSubmit?.call(),
      );
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          const Expanded(child: Divider(color: T.amberBorder, height: 1)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('or continue with', style: pop(11, c: T.gray))),
          const Expanded(child: Divider(color: T.amberBorder, height: 1)),
        ]),
      );
}

class _GoogleButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool busy;
  const _GoogleButton({this.onPressed, this.busy = false});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 11),
            side: const BorderSide(color: T.amberBorder, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            busy ? const AmberSpinner(size: 18) : SvgPicture.string(googleG, width: 18, height: 18),
            const SizedBox(width: 9),
            Text('Continue with Google', style: pop(13, w: FontWeight.w600, c: T.text)),
          ]),
        ),
      );
}

// ═══════════════════════════ OTP ═══════════════════════════

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  // Firebase SMS codes are 6 digits.
  static const _len = 6;
  final _ctrls = List.generate(_len, (_) => TextEditingController());
  final _nodes = List.generate(_len, (_) => FocusNode());
  bool _busy = false;
  int _resendIn = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _resendIn = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _code => _ctrls.map((c) => c.text).join();

  void _onChanged(int i, String v) {
    if (v.length > 1) {
      // Pasted / autofilled full code.
      final digits = v.replaceAll(RegExp(r'\D'), '');
      for (var k = 0; k < _len; k++) {
        _ctrls[k].text = k < digits.length ? digits[k] : '';
      }
      _nodes[(digits.length).clamp(0, _len - 1)].requestFocus();
    } else if (v.isNotEmpty && i < _len - 1) {
      _nodes[i + 1].requestFocus();
    } else if (v.isEmpty && i > 0) {
      _nodes[i - 1].requestFocus();
    }
    if (_code.length == _len) _verify();
  }

  Future<void> _verify() async {
    if (_code.length != _len || _busy) return;
    setState(() => _busy = true);
    try {
      await context.read<Session>().verifyOtp(_code);
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil(Routes.home, (_) => false);
    } catch (e) {
      if (mounted) toast(context, _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final s = context.read<Session>();
    final phone = s.pendingPhone;
    if (phone == null) return Navigator.of(context).pop();
    try {
      await s.sendOtp(phone.substring(3), resend: true);
      if (mounted) {
        toast(context, 'OTP sent again');
        _startTimer();
      }
    } catch (e) {
      if (mounted) toast(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.read<Session>().pendingPhone ?? '';
    final masked = phone.length == 13 ? '+91 ${phone.substring(3, 8)} XXXXX' : phone;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [
          const AuthHeader('VERIFY NUMBER'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Enter OTP 🔐', style: pop(18, w: FontWeight.w700, c: T.amberDark)),
              const SizedBox(height: 3),
              Text.rich(TextSpan(style: pop(12, c: T.gray), children: [
                const TextSpan(text: 'Sent to '),
                TextSpan(text: masked, style: pop(12, w: FontWeight.w700, c: T.gray)),
              ])),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < _len; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 54),
                      child: SizedBox(
                        height: 56,
                        child: TextField(
                          controller: _ctrls[i],
                          focusNode: _nodes[i],
                          autofocus: i == 0,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          autofillHints: i == 0 ? const [AutofillHints.oneTimeCode] : null,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: nun(22, w: FontWeight.w700, c: T.amberDark),
                          onChanged: (v) => _onChanged(i, v),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: T.amberPale,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: T.amberBorder, width: 2)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: T.amber, width: 2)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 16),
              Center(
                child: Text.rich(TextSpan(style: pop(12, c: T.gray), children: [
                  const TextSpan(text: "Didn't receive? "),
                  _resendIn > 0
                      ? TextSpan(text: 'Resend in ${_resendIn}s', style: pop(12, w: FontWeight.w600, c: T.gray))
                      : TextSpan(
                          text: 'Resend OTP',
                          style: pop(12, w: FontWeight.w600, c: T.amber),
                          recognizer: TapGestureRecognizer()..onTap = _resend,
                        ),
                ])),
              ),
              const SizedBox(height: 10),
              AmberButton('Verify & Sign In', onPressed: _verify, busy: _busy),
              const SizedBox(height: 12),
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Text('← Change number', style: pop(12, c: T.amber)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════ SIGN-UP ═══════════════════════════

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name = TextEditingController(), _phone = TextEditingController(), _email = TextEditingController();
  bool _accepted = false, _busy = false, _badPhone = false;

  Future<void> _go() async {
    if (!_accepted) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text('Please accept Terms & Conditions to continue.', style: pop(13)),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
      return;
    }
    if (_phone.text.trim().length < 10) {
      setState(() => _badPhone = true);
      Timer(const Duration(milliseconds: 1800), () => mounted ? setState(() => _badPhone = false) : null);
      return;
    }
    setState(() => _busy = true);
    try {
      final auto = await context.read<Session>().sendOtp(
            _phone.text.trim(),
            name: _name.text.trim().isEmpty ? null : _name.text.trim(),
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          );
      if (!mounted) return;
      if (auto) {
        Navigator.of(context).pushNamedAndRemoveUntil(Routes.home, (_) => false);
      } else {
        Navigator.of(context).pushNamed(Routes.otp);
      }
    } catch (e) {
      if (mounted) toast(context, _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openTC() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        barrierColor: Colors.black54,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        builder: (c) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .7),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: T.amberBorder, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text('Terms & Conditions', style: pop(14, w: FontWeight.w700, c: T.amberDark)),
              const SizedBox(height: 10),
              for (final (h, b) in const [
                ('1. Acceptance', 'By using Tarajuu, you agree to these terms.'),
                ('2. Price Comparison', 'We aggregate publicly available prices. Accuracy may vary.'),
                ('3. Ride Fares', 'Estimates are indicative; actual fares may vary with surge pricing.'),
                ('4. Privacy', 'We collect minimal data to improve your experience. Never sold.'),
                ('5. Third-Party Links', 'Tarajuu is not responsible for third-party platforms.'),
                ('6. Liability', 'Tarajuu is a comparison tool only.'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text.rich(TextSpan(style: pop(11, c: T.gray, h: 1.8), children: [
                    TextSpan(text: h, style: pop(11, w: FontWeight.w700, c: T.gray, h: 1.8)),
                    TextSpan(text: ' — $b'),
                  ])),
                ),
              const SizedBox(height: 6),
              AmberButton('I Understand — Close', fontSize: 13, radius: 11, vPad: 11, onPressed: () => Navigator.pop(c)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final link = pop(11, w: FontWeight.w600, c: T.amber).copyWith(decoration: TextDecoration.underline, decorationColor: T.amber);
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [
          const AuthHeader('CREATE ACCOUNT'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Join Tarajuu 🎉', style: pop(18, w: FontWeight.w700, c: T.amberDark)),
              const SizedBox(height: 3),
              Text('Start comparing and saving today', style: pop(12, c: T.gray)),
              const SizedBox(height: 18),
              const FieldLabel('Full Name'),
              TextField(controller: _name, textCapitalization: TextCapitalization.words, style: pop(13, c: const Color(0xFF333333)), decoration: amberInput('Rahul Sharma')),
              const SizedBox(height: 12),
              const FieldLabel('Mobile Number'),
              Row(children: [const FlagBox(), const SizedBox(width: 7), Expanded(child: _PhoneField(_phone, error: _badPhone))]),
              const SizedBox(height: 14),
              const FieldLabel('Email (optional)'),
              TextField(controller: _email, keyboardType: TextInputType.emailAddress, style: pop(13, c: const Color(0xFF333333)), decoration: amberInput('you@email.com')),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 17,
                    height: 17,
                    child: Checkbox(
                      value: _accepted,
                      activeColor: T.amber,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) => setState(() => _accepted = v ?? false),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text.rich(TextSpan(style: pop(11, c: T.gray, h: 1.6), children: [
                      const TextSpan(text: 'I agree to the '),
                      TextSpan(text: 'Terms & Conditions', style: link, recognizer: TapGestureRecognizer()..onTap = _openTC),
                      const TextSpan(text: ' and '),
                      TextSpan(text: 'Privacy Policy', style: link, recognizer: TapGestureRecognizer()..onTap = _openTC),
                      const TextSpan(text: ' of Tarajuu.'),
                    ])),
                  ),
                ]),
              ),
              AmberButton('Create Account & Get OTP', onPressed: _go, busy: _busy),
              const SizedBox(height: 14),
              Center(
                child: Text.rich(TextSpan(style: pop(12, c: T.gray), children: [
                  const TextSpan(text: 'Have an account? '),
                  TextSpan(
                    text: 'Sign in',
                    style: pop(12, w: FontWeight.w600, c: T.amber),
                    recognizer: TapGestureRecognizer()..onTap = () => Navigator.of(context).pop(),
                  ),
                ])),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
