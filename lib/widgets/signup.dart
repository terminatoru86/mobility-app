import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/app_state.dart';
import '../data/auth.dart';
import '../data/places.dart';
import '../theme.dart';

const _barrier = Color(0x380F1E24);

/// Our sign-in sheet: a low sheet that comes up from the bottom, so the map stays in view.
/// Google and Email on one row, "Guest" in the corner; a link by email (and the phone, when it is
/// switched on) are typed in the same sheet.
/// Used after the start screen, from Profile and as the invite after a few opens.
/// Returns true when the user signed in (the account is then marked as created).
Future<bool> showSignIn(BuildContext context, AppState state, {String guestLabel = 'Guest ›'}) async {
  // already signed in (e.g. the link in the email opened the app): nothing to ask
  if (Auth.i.ready && Auth.i.user != null) {
    await state.createAccount();
    return true;
  }
  final ok = await _sheet<bool>(context, SignInCard(guestLabel: guestLabel));
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

/// Which vehicle do you ride? The same low sheet. After signing in it cannot be skipped;
/// from Profile and the map ([canClose]) it starts on the saved vehicle and closes with a tap outside.
Future<void> showVehicleStep(BuildContext context, AppState state, {bool canClose = false}) =>
    _sheet<void>(context, _VehicleStep(state: state, startOnSaved: canClose), canClose: canClose);

Future<T?> _sheet<T>(BuildContext context, Widget child, {bool canClose = false}) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true, // rises with the keyboard
      isDismissible: canClose,
      enableDrag: canClose,
      barrierColor: _barrier,
      backgroundColor: Colors.transparent,
      builder: (_) => PopScope(canPop: canClose, child: child),
    );

/// The low white sheet: a grabber, then the content.
class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Color(0x260F1E24), blurRadius: 24, offset: Offset(0, -8))],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(color: const Color(0xFFD6DEE2), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                ...children,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _pill(String t, Color bg, Color fg, VoidCallback? onTap, {bool border = false, Widget? icon}) => SizedBox(
      height: 46,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledForegroundColor: fg.withValues(alpha: .45),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: StadiumBorder(side: border ? const BorderSide(color: AppColors.line, width: 1.5) : BorderSide.none),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[icon, const SizedBox(width: 8)],
          Text(t),
        ]),
      ),
    );

Widget _input(TextEditingController c, String hint, TextInputType type, {VoidCallback? onDone, FocusNode? focus}) =>
    TextField(
      controller: c,
      focusNode: focus,
      keyboardType: type,
      textInputAction: TextInputAction.done,
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

/// The head of a sheet: the logo, a title with one line under it, and a small action in the corner.
Widget _head(String title, String sub, {Widget? action}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        SvgPicture.asset('assets/brand/logo_m.svg', width: 32, height: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.15)),
            Text(sub,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.soft, height: 1.3)),
          ]),
        ),
        if (action != null) action,
      ]),
    );

enum _Mode { choose, email, emailSent, phone, phoneCode }

/// The sign-in card. Problems show as a short red line inside the card (no pop-ups).
class SignInCard extends StatefulWidget {
  final String guestLabel;
  const SignInCard({super.key, this.guestLabel = 'Continue as guest'});
  @override
  State<SignInCard> createState() => _SignInCardState();
}

class _SignInCardState extends State<SignInCard> with WidgetsBindingObserver {
  _Mode _mode = _Mode.choose;
  bool _busy = false;
  String? _problem;
  final _email = TextEditingController();
  final _phone = TextEditingController(text: '+1 ');
  final _code = TextEditingController();
  String? _verificationId;

  @override
  void initState() {
    super.initState();
    // tapping the link in the email opens the app and signs in: close with "signed in"
    Auth.i.emailSignIns.addListener(_linked);
    Auth.i.emailLinkProblem.addListener(_linkProblem);
    WidgetsBinding.instance.addObserver(this);
  }

  bool _closed = false;
  void _linked() {
    if (!mounted || _closed) return;
    _closed = true;
    Navigator.pop(context, true);
  }

  void _linkProblem() {
    final p = Auth.i.emailLinkProblem.value;
    if (mounted && p != null) setState(() => _problem = p);
  }

  /// Back from the email app: check whether the link signed us in (and try it if it was missed).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _mode != _Mode.emailSent) return;
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && !_closed) Auth.i.checkEmailLinkNow(email: _email.text.trim());
    });
  }

  @override
  void dispose() {
    Auth.i.emailSignIns.removeListener(_linked);
    Auth.i.emailLinkProblem.removeListener(_linkProblem);
    WidgetsBinding.instance.removeObserver(this);
    _email.dispose();
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

  Widget _corner(String t, VoidCallback onTap) => TextButton(
        onPressed: _busy ? null : onTap,
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 36), visualDensity: VisualDensity.compact),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.blue, fontSize: 13)),
      );

  Widget _back() => _corner('‹ Back', () => setState(() {
        _mode = _Mode.choose;
        _problem = null;
      }));

  /// A field and its button on one row.
  Widget _row(Widget field, String button, VoidCallback onTap) => Row(children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        _pill(button, AppColors.ink, Colors.white, _busy ? null : onTap),
      ]);

  List<Widget> _body() {
    switch (_mode) {
      case _Mode.choose:
        return [
          _head('Sign in', 'Keep your places and routes',
              action: _corner(widget.guestLabel, () => Navigator.pop(context, false))),
          Row(children: [
            Expanded(
                child: _pill('Google', Colors.white, AppColors.ink, _busy ? null : _google,
                    border: true, icon: const GoogleG())),
            const SizedBox(width: 8),
            Expanded(
                child: _pill('Email', AppColors.ink, Colors.white,
                    _busy ? null : () => setState(() => _mode = _Mode.email),
                    icon: const Icon(Icons.mail_outline, size: 18))),
          ]),
          if (kPhoneSignIn) ...[
            const SizedBox(height: 8),
            _pill('Phone', Colors.white, AppColors.ink, _busy ? null : () => setState(() => _mode = _Mode.phone),
                border: true, icon: const Icon(Icons.phone_iphone, size: 18)),
          ],
        ];
      case _Mode.email:
        return [
          _head('Sign in', 'We email you a link. No password.', action: _back()),
          _row(_input(_email, 'you@example.com', TextInputType.emailAddress, onDone: _sendEmail), 'Send', _sendEmail),
        ];
      case _Mode.emailSent:
        return [
          _head('Check your email', '${_email.text.trim()} · tap the link on this phone', action: _back()),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Waiting for you to tap the link…',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.soft)),
              ),
              _corner('Send again', _sendEmail),
            ]),
          ),
        ];
      case _Mode.phone:
        return [
          _head('Sign in', 'We text you a 6-digit code.', action: _back()),
          _row(_input(_phone, '+1 312 555 0100', TextInputType.phone, onDone: _sendSms), 'Send', _sendSms),
        ];
      case _Mode.phoneCode:
        return [
          _head('Type the code', 'Sent to ${_phone.text.trim()}', action: _back()),
          _row(_input(_code, '123456', TextInputType.number, onDone: _checkCode), 'Sign in', _checkCode),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      children: [
        ..._body(),
        if (_busy && _mode != _Mode.emailSent) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(minHeight: 2)),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_problem!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: AppColors.red, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}

/// Which vehicle do you ride? A low sheet: the five vehicles on one row, each with its picture and
/// name, all in view at once. Tap yours: it gets a blue edge; under the row, on one line, the
/// model (not for a bike) and Finish, which lights up once the model is typed. Tap another vehicle
/// to change. No Skip.
class _VehicleStep extends StatefulWidget {
  final AppState state;
  final bool startOnSaved;
  const _VehicleStep({required this.state, this.startOnSaved = false});
  @override
  State<_VehicleStep> createState() => _VehicleStepState();
}

class _VehicleStepState extends State<_VehicleStep> {
  static bool _hasModel(Vehicle v) => v != Vehicle.bike;
  static const _all = [Vehicle.bike, Vehicle.ebike, Vehicle.scooter, Vehicle.moped, Vehicle.moto];
  final _model = TextEditingController();
  final _focus = FocusNode();
  Vehicle? _chosen;

  @override
  void initState() {
    super.initState();
    final saved = widget.state.myVehicle;
    if (widget.startOnSaved && saved != null) {
      _chosen = saved;
      _model.text = widget.state.model;
    }
    _model.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _pick(Vehicle v) {
    setState(() => _chosen = v);
    if (_hasModel(v)) {
      _focus.requestFocus();
    } else {
      _focus.unfocus();
    }
  }

  bool get _ready => _chosen != null && (!_hasModel(_chosen!) || _model.text.trim().isNotEmpty);

  Future<void> _finish() async {
    final v = _chosen!;
    await widget.state.saveVehicle(v, _hasModel(v) ? _model.text.trim() : '');
    if (mounted) Navigator.pop(context);
  }

  static String _example(Vehicle v) => switch (v) {
        Vehicle.ebike => 'Model, e.g. RadCity',
        Vehicle.scooter => 'Model, e.g. Ninebot Max',
        Vehicle.moped => 'Model, e.g. Vespa',
        Vehicle.moto => 'Model, e.g. Honda CB500',
        Vehicle.bike => '',
      };

  static String _short(Vehicle v) => v == Vehicle.moto ? 'Moto' : v.label;

  Widget _tile(Vehicle v) {
    final on = v == _chosen;
    return Expanded(
      child: GestureDetector(
        onTap: () => _pick(v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
          decoration: BoxDecoration(
            color: on ? Colors.white : AppColors.paper,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? AppColors.blue : Colors.transparent, width: 2),
            boxShadow: [if (on) const BoxShadow(color: Color(0x2E2F6FDC), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(height: 40, child: Image.asset(v.asset, fit: BoxFit.contain)),
            const SizedBox(height: 4),
            Text(_short(v),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    final finish = _pill('Finish', _ready ? AppColors.blue : const Color(0xFFD5E0F5), Colors.white, _ready ? _finish : null);
    return _Card(
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text('What do you ride?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
        Row(children: [for (final v in _all) _tile(v)]),
        const SizedBox(height: 10),
        if (chosen == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('Tap your vehicle',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.soft, fontWeight: FontWeight.w600)),
          )
        else if (_hasModel(chosen))
          // the model helps us show the right plugs and services; Finish lights up once it is typed
          Row(children: [
            Expanded(
                child: _input(_model, _example(chosen), TextInputType.text, focus: _focus, onDone: () {
              if (_ready) _finish();
            })),
            const SizedBox(width: 8),
            finish,
          ])
        else
          finish,
      ],
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
