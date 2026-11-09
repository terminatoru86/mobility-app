import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/app_state.dart';
import '../data/auth.dart';
import '../data/places.dart';
import '../theme.dart';

const _barrier = Color(0x550F1E24);

/// Our sign-in pop-up (the small card in the middle with the logo on top): Google, a link by
/// email, the phone (when it is switched on), or carry on as a guest.
/// Used at the end of the start screen, from Profile and as the invite after a few opens.
/// Returns true when the user signed in (the account is then marked as created).
Future<bool> showSignIn(BuildContext context, AppState state, {String guestLabel = 'Continue as guest'}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: _barrier,
    barrierDismissible: false,
    builder: (_) => SignInCard(guestLabel: guestLabel),
  );
  if (ok == true) {
    await state.createAccount();
    return true;
  }
  return false;
}

/// The invite (after a few opens, and "Create account" in Profile): sign in, then the vehicle.
Future<void> showSignupInvite(BuildContext context, AppState state) async {
  final ok = await showSignIn(context, state, guestLabel: 'Not now');
  if (ok && context.mounted) await showVehicleStep(context, state);
}

/// After signing in: which vehicle do you ride? A full page; it cannot be skipped.
Future<void> showVehicleStep(BuildContext context, AppState state) => Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PopScope(canPop: false, child: _VehicleStep(state: state)),
      ),
    );

class _Card extends StatelessWidget {
  final Widget badge;
  final List<Widget> children;
  const _Card({required this.badge, required this.children});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        Container(
          margin: const EdgeInsets.only(top: 28),
          padding: const EdgeInsets.fromLTRB(18, 40, 18, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [BoxShadow(color: Color(0x220F1E24), blurRadius: 24, offset: Offset(0, 10))],
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
        Container(
          width: 60,
          height: 60,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x2A0F1E24), blurRadius: 14, offset: Offset(0, 5))],
          ),
          alignment: Alignment.center,
          child: badge,
        ),
      ]),
    );
  }
}

Widget _pill(String t, Color bg, Color fg, VoidCallback? onTap, {bool border = false, Widget? icon}) => SizedBox(
      width: double.infinity,
      height: 46,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledForegroundColor: fg.withValues(alpha: .45),
          shape: StadiumBorder(side: border ? const BorderSide(color: AppColors.line, width: 1.5) : BorderSide.none),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[icon, const SizedBox(width: 9)],
          Text(t),
        ]),
      ),
    );

Widget _input(TextEditingController c, String hint, TextInputType type, {VoidCallback? onDone, int lines = 1}) =>
    TextField(
      controller: c,
      keyboardType: type,
      minLines: 1,
      maxLines: lines,
      onSubmitted: (_) => onDone?.call(),
      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: AppColors.paper,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
    );

enum _Mode { choose, email, emailSent, phone, phoneCode }

/// The sign-in card. Problems show as a short red line inside the card (no pop-ups).
class SignInCard extends StatefulWidget {
  final String guestLabel;
  const SignInCard({super.key, this.guestLabel = 'Continue as guest'});
  @override
  State<SignInCard> createState() => _SignInCardState();
}

class _SignInCardState extends State<SignInCard> {
  _Mode _mode = _Mode.choose;
  bool _busy = false;
  String? _problem;
  final _email = TextEditingController();
  final _link = TextEditingController();
  final _phone = TextEditingController(text: '+1 ');
  final _code = TextEditingController();
  String? _verificationId;

  @override
  void initState() {
    super.initState();
    // tapping the link in the email opens the app and signs in: close with "signed in"
    Auth.i.emailSignIns.addListener(_linked);
  }

  void _linked() {
    if (mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    Auth.i.emailSignIns.removeListener(_linked);
    _email.dispose();
    _link.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _problem = e is AuthProblem ? e.message : 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done() {
    if (mounted) Navigator.pop(context, true);
  }

  void _google() => _run(() async {
        if (await Auth.i.google() != null) _done();
      });

  void _sendEmail() => _run(() async {
        final e = _email.text.trim();
        if (!e.contains('@') || !e.contains('.')) throw const AuthProblem('Type your email address.');
        await Auth.i.sendEmailLink(e);
        if (mounted) setState(() => _mode = _Mode.emailSent);
      });

  void _pasted() => _run(() async {
        if (await Auth.i.signInWithPastedLink(_link.text) != null) _done();
      });

  void _sendSms() => _run(() async {
        final n = _phone.text.replaceAll(RegExp(r'[^0-9+]'), '');
        if (n.length < 10) throw const AuthProblem('Type your phone number.');
        final result = Completer<String?>();
        await Auth.i.phoneStart(n,
            codeSent: (id) {
              _verificationId = id;
              if (mounted) setState(() => _mode = _Mode.phoneCode);
              if (!result.isCompleted) result.complete(null);
            },
            done: (_) => _done(),
            failed: (m) {
              if (!result.isCompleted) result.complete(m);
            });
        final m = await result.future;
        if (m != null) throw AuthProblem(m);
      });

  void _checkCode() => _run(() async {
        final id = _verificationId;
        if (id == null) return;
        try {
          if (await Auth.i.phoneCode(id, _code.text.trim()) != null) _done();
        } catch (_) {
          throw const AuthProblem('That code is not right.');
        }
      });

  Widget _back() => TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                  _mode = _Mode.choose;
                  _problem = null;
                }),
        child: const Text('Back', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.slate)),
      );

  Widget _title(String t, String sub) => Column(children: [
        Text(t, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(sub, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppColors.soft, height: 1.3)),
        const SizedBox(height: 14),
      ]);

  List<Widget> _body() {
    Widget benefit(IconData i, String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 13, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        );
    switch (_mode) {
      case _Mode.choose:
        return [
          const Text('Save your rides', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Your places, routes and vehicle on any phone.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppColors.soft)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, children: [
            benefit(Icons.favorite, 'Places'),
            benefit(Icons.route, 'Routes'),
            benefit(Icons.pedal_bike, 'Vehicle'),
          ]),
          const SizedBox(height: 14),
          _pill('Continue with Google', Colors.white, AppColors.ink, _busy ? null : _google,
              border: true, icon: const GoogleG()),
          const SizedBox(height: 8),
          _pill('Continue with email', AppColors.ink, Colors.white,
              _busy ? null : () => setState(() => _mode = _Mode.email),
              icon: const Icon(Icons.mail_outline, size: 19)),
          if (kPhoneSignIn) ...[
            const SizedBox(height: 8),
            _pill('Continue with phone', Colors.white, AppColors.ink,
                _busy ? null : () => setState(() => _mode = _Mode.phone),
                border: true, icon: const Icon(Icons.phone_iphone, size: 19)),
          ],
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: Text(widget.guestLabel, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.slate)),
          ),
        ];
      case _Mode.email:
        return [
          _title('Sign in with email', "We'll email you a sign-in link. No password."),
          _input(_email, 'you@example.com', TextInputType.emailAddress, onDone: _sendEmail),
          const SizedBox(height: 10),
          _pill('Send', AppColors.ink, Colors.white, _busy ? null : _sendEmail),
          _back(),
        ];
      case _Mode.emailSent:
        return [
          _title('Check your email',
              'We sent a sign-in link to ${_email.text.trim()}.\nTap it on this phone, or copy it and paste it here.\nNot there? Look in Spam / Bulk.'),
          _input(_link, 'Paste the link from the email', TextInputType.url, onDone: _pasted, lines: 3),
          const SizedBox(height: 10),
          _pill('Sign in', AppColors.ink, Colors.white, _busy ? null : _pasted),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton(
              onPressed: _busy ? null : _sendEmail,
              child: const Text('Send again', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.blue)),
            ),
            _back(),
          ]),
        ];
      case _Mode.phone:
        return [
          _title('Sign in with your phone', "We'll text you a 6-digit code."),
          _input(_phone, '+1 312 555 0100', TextInputType.phone, onDone: _sendSms),
          const SizedBox(height: 10),
          _pill('Send the code', AppColors.ink, Colors.white, _busy ? null : _sendSms),
          _back(),
        ];
      case _Mode.phoneCode:
        return [
          _title('Type the code', 'Sent to ${_phone.text.trim()}'),
          _input(_code, '123456', TextInputType.number, onDone: _checkCode),
          const SizedBox(height: 10),
          _pill('Sign in', AppColors.ink, Colors.white, _busy ? null : _checkCode),
          _back(),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      badge: SvgPicture.asset('assets/brand/logo_m.svg', width: 40, height: 40),
      children: [
        ..._body(),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_problem!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: AppColors.red, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}

/// Which vehicle do you ride? A full page in the style of a product card deck:
/// big title, one big card (more cards stacked behind it), the picture filling the top and
/// changing by itself (swipe works too), the name and one line under it, an outlined
/// "Choose" button in the card, "‹ 1/5 ›" under the card, then the model (not for a bike)
/// and a big blue Continue at the bottom. No Skip.
class _VehicleStep extends StatefulWidget {
  final AppState state;
  const _VehicleStep({required this.state});
  @override
  State<_VehicleStep> createState() => _VehicleStepState();
}

class _VehicleStepState extends State<_VehicleStep> {
  static const _vehicles = [Vehicle.bike, Vehicle.ebike, Vehicle.scooter, Vehicle.moped, Vehicle.moto];
  static bool _hasModel(Vehicle v) => v != Vehicle.bike;

  final _pc = PageController();
  final _model = TextEditingController();
  Timer? _t;
  int _i = 0;
  bool _touched = false;
  Vehicle? _chosen;
  bool _why = false;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (!_touched && _chosen == null && _pc.hasClients) {
        _pc.animateToPage((_i + 1) % _vehicles.length,
            duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
      }
    });
    _model.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    _pc.dispose();
    _model.dispose();
    super.dispose();
  }

  void _go(int d) {
    _touched = true;
    final n = _i + d;
    if (n < 0 || n >= _vehicles.length) return;
    _pc.animateToPage(n, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Future<void> _continue() async {
    final v = _chosen;
    if (v == null) return;
    await widget.state.saveVehicle(v, _hasModel(v) ? _model.text.trim() : '');
    if (mounted) Navigator.pop(context);
  }

  static String _line(Vehicle v) => switch (v) {
        Vehicle.bike => 'No model needed',
        Vehicle.ebike => 'Add the model for the right charger',
        Vehicle.scooter => 'Add the model for the right charger',
        Vehicle.moped => 'Add the model for service and parts',
        Vehicle.moto => 'Add the model for service and parts',
      };

  static String _example(Vehicle v) => switch (v) {
        Vehicle.ebike => 'Rad Power RadCity',
        Vehicle.scooter => 'Segway Ninebot Max',
        Vehicle.moped => 'Vespa Primavera',
        Vehicle.moto => 'Honda CB500',
        Vehicle.bike => '',
      };

  @override
  Widget build(BuildContext context) {
    final v = _vehicles[_i];
    final chosen = _chosen;
    final selectedHere = chosen == v;
    final needsModel = chosen != null && _hasModel(chosen);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(22, 18, 22, 12), children: [
              const Text('What do you ride?',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.1)),
              const SizedBox(height: 8),
              const Text('Pick your vehicle. We use it for parking, chargers and routes that fit it.',
                  style: TextStyle(fontSize: 16, color: AppColors.ink, height: 1.3)),
              const SizedBox(height: 22),
              // the deck: two cards peeking out behind on the right, the big card in front
              SizedBox(
                height: 420,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned(
                    right: -6,
                    top: 70,
                    bottom: 70,
                    width: 60,
                    child: Container(
                      decoration: BoxDecoration(color: const Color(0xFFB9C2C7), borderRadius: BorderRadius.circular(26)),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    top: 36,
                    bottom: 36,
                    width: 60,
                    child: Container(
                      decoration: BoxDecoration(color: const Color(0xFFDCE2E5), borderRadius: BorderRadius.circular(28)),
                    ),
                  ),
                  Positioned.fill(
                    right: 30,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                            color: selectedHere ? AppColors.blue : const Color(0xFFE3E8EA),
                            width: selectedHere ? 2 : 1.2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // the picture, filling the top
                        Expanded(
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: RadialGradient(
                                radius: 0.9,
                                colors: [Colors.white, Color(0xFFF0F2F3)],
                              ),
                            ),
                            child: Listener(
                              onPointerDown: (_) => _touched = true,
                              child: PageView.builder(
                                controller: _pc,
                                itemCount: _vehicles.length,
                                onPageChanged: (i) => setState(() {
                                  _i = i;
                                  _why = false;
                                }),
                                itemBuilder: (_, i) => Padding(
                                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
                                  child: Image.asset(_vehicles[i].asset, fit: BoxFit.contain),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(v.label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            Text(_line(v), style: const TextStyle(fontSize: 16, color: AppColors.soft)),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: selectedHere
                                  ? FilledButton.icon(
                                      onPressed: null,
                                      icon: const Icon(Icons.check_rounded),
                                      label: Text('${v.label} chosen'),
                                      style: FilledButton.styleFrom(
                                        disabledBackgroundColor: const Color(0xFFE6EEFB),
                                        disabledForegroundColor: AppColors.blue,
                                        shape: const StadiumBorder(),
                                        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                                      ),
                                    )
                                  : OutlinedButton(
                                      onPressed: () => setState(() {
                                        _touched = true;
                                        _chosen = v;
                                      }),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.blue,
                                        side: const BorderSide(color: AppColors.blue, width: 1.6),
                                        shape: const StadiumBorder(),
                                        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                                      ),
                                      child: const Text('Choose'),
                                    ),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
              // ‹ 1/5 ›
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 30),
                child: Row(children: [
                  IconButton(
                    onPressed: _i == 0 ? null : () => _go(-1),
                    icon: const Icon(Icons.chevron_left_rounded, size: 34),
                    color: AppColors.ink,
                    disabledColor: const Color(0xFFC3CBCF),
                  ),
                  Expanded(
                    child: Text('${_i + 1}/${_vehicles.length}',
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
                  ),
                  IconButton(
                    onPressed: _i == _vehicles.length - 1 ? null : () => _go(1),
                    icon: const Icon(Icons.chevron_right_rounded, size: 34),
                    color: AppColors.ink,
                    disabledColor: const Color(0xFFC3CBCF),
                  ),
                ]),
              ),
              // the model: e-bike, scooter, moped, motorcycle
              if (needsModel) ...[
                const SizedBox(height: 10),
                Text('${chosen.label} model', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _input(_model, 'e.g. ${_example(chosen)}', TextInputType.text)),
                  if (_model.text.trim().isEmpty) ...[
                    const SizedBox(width: 10),
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _why = !_why),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.blue, width: 1.8),
                          color: _why ? AppColors.blue : Colors.white,
                        ),
                        alignment: Alignment.center,
                        child: Text('i',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                fontStyle: FontStyle.italic,
                                color: _why ? Colors.white : AppColors.blue)),
                      ),
                    ),
                  ],
                ]),
                if (_why && _model.text.trim().isEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFEAF1FD), borderRadius: BorderRadius.circular(14)),
                    child: const Text(
                      'The model helps us show the right charging plugs, GPS settings and service suggestions, '
                      'and connect you better with the shops and services in your city.',
                      style: TextStyle(fontSize: 13.5, color: AppColors.primary, height: 1.35),
                    ),
                  ),
              ],
            ]),
          ),
          // the big blue button at the bottom
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
            child: SizedBox(
              width: double.infinity,
              height: 58,
              child: FilledButton(
                onPressed: chosen == null ? null : _continue,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  disabledBackgroundColor: const Color(0xFFBFD0F2),
                  disabledForegroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                child: Text(chosen == null ? 'Choose your vehicle' : 'Continue with ${chosen.label.toLowerCase()}'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The Google "G" in its four colours (drawn, no image file).
class GoogleG extends StatelessWidget {
  const GoogleG({super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(19, 19), painter: _GPainter());
}

class _GPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2, c = size.center(Offset.zero);
    final w = size.width * 0.2;
    final rect = Rect.fromCircle(center: c, radius: r - w / 2);
    Paint p(Color col) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = col;
    const d = 3.141592653589793 / 180;
    canvas.drawArc(rect, -45 * d, -135 * d, false, p(const Color(0xFFEA4335)));
    canvas.drawArc(rect, 180 * d, -60 * d, false, p(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, 120 * d, -75 * d, false, p(const Color(0xFF34A853)));
    canvas.drawArc(rect, 45 * d, -45 * d, false, p(const Color(0xFF4285F4)));
    canvas.drawRect(Rect.fromLTWH(c.dx, c.dy - w / 2, r, w), Paint()..color = const Color(0xFF4285F4));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
