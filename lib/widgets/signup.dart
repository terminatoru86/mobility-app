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

/// After signing in: which vehicle do you ride? It cannot be skipped.
Future<void> showVehicleStep(BuildContext context, AppState state) => showDialog<void>(
      context: context,
      barrierColor: _barrier,
      barrierDismissible: false,
      builder: (_) => PopScope(canPop: false, child: _VehicleStep(state: state)),
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

/// Which vehicle do you ride? Like a product card: a big picture that changes by itself
/// (and can be swiped), "1/4" with arrows under it, the Choose button, then the model
/// (not for a bike: bikes have no model). No Skip.
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
    _pc.animateToPage((_i + d) % _vehicles.length, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Future<void> _save(Vehicle v) async {
    await widget.state.saveVehicle(v, _hasModel(v) ? _model.text.trim() : '');
    if (mounted) Navigator.pop(context);
  }

  void _choose() {
    final v = _vehicles[_i];
    _touched = true;
    if (!_hasModel(v)) {
      _save(v);
      return;
    }
    setState(() => _chosen = v);
  }

  @override
  Widget build(BuildContext context) {
    final v = _vehicles[_i];
    final chosen = _chosen;
    return _Card(
      badge: const Icon(Icons.check_rounded, color: AppColors.greenDark, size: 30),
      children: [
        const Text('What do you ride?', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        // the product card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: chosen != null ? AppColors.ink : AppColors.line, width: chosen != null ? 2 : 1.2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Container(
              height: 150,
              color: AppColors.paper,
              child: Listener(
                onPointerDown: (_) => _touched = true,
                child: PageView.builder(
                  controller: _pc,
                  physics: chosen != null ? const NeverScrollableScrollPhysics() : null,
                  itemCount: _vehicles.length,
                  onPageChanged: (i) => setState(() => _i = i),
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Image.asset(_vehicles[i].asset, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(_hasModel(v) ? 'Add the model after you choose' : 'No model needed',
                        style: const TextStyle(fontSize: 12, color: AppColors.soft)),
                  ]),
                ),
                if (chosen != null) const Icon(Icons.check_circle, color: AppColors.green),
              ]),
            ),
          ]),
        ),
        // 1/5 with arrows
        if (chosen == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                onPressed: () => _go(-1),
                icon: const Icon(Icons.chevron_left_rounded, size: 30),
                color: AppColors.ink,
              ),
              SizedBox(
                width: 48,
                child: Text('${_i + 1}/${_vehicles.length}',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                onPressed: () => _go(1),
                icon: const Icon(Icons.chevron_right_rounded, size: 30),
                color: AppColors.ink,
              ),
            ]),
          )
        else
          const SizedBox(height: 12),
        if (chosen == null) ...[
          _pill('Choose ${v.label.toLowerCase()}', AppColors.blue, Colors.white, _choose),
          const SizedBox(height: 10),
        ] else ...[
          // the model (scooter, moped, motorcycle, e-bike)
          Row(children: [
            Expanded(child: _input(_model, 'Model, e.g. ${_example(chosen)}', TextInputType.text)),
            if (_model.text.trim().isEmpty) ...[
              const SizedBox(width: 8),
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _why = !_why),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.blue, width: 1.6),
                    color: _why ? AppColors.blue : Colors.white,
                  ),
                  alignment: Alignment.center,
                  child: Text('i',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          fontStyle: FontStyle.italic,
                          color: _why ? Colors.white : AppColors.blue)),
                ),
              ),
            ],
          ]),
          if (_why && _model.text.trim().isEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFEAF1FD), borderRadius: BorderRadius.circular(12)),
              child: const Text(
                'The model helps us show the right charging plugs, GPS settings and service suggestions, '
                'and connect you better with the shops and services in your city.',
                style: TextStyle(fontSize: 12, color: AppColors.primary, height: 1.35),
              ),
            ),
          const SizedBox(height: 10),
          _pill('Done', AppColors.ink, Colors.white, () => _save(chosen)),
          TextButton(
            onPressed: () => setState(() {
              _chosen = null;
              _why = false;
            }),
            child: const Text('Pick another', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.slate)),
          ),
        ],
      ],
    );
  }

  static String _example(Vehicle v) => switch (v) {
        Vehicle.ebike => 'Rad Power RadCity',
        Vehicle.scooter => 'Segway Ninebot Max',
        Vehicle.moped => 'Vespa Primavera',
        Vehicle.moto => 'Honda CB500',
        Vehicle.bike => '',
      };
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
