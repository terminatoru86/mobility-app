import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Our Firebase project (Authentication).
const String kFirebaseProject = 'mobility-d0e54';

/// Sign-in with the phone number (SMS code). Off for now: Firebase sends SMS only on the
/// Blaze plan. The code is ready; turn this on after the project moves to Blaze.
const bool kPhoneSignIn = false;

/// Sign-in with Firebase Authentication: Google, a link sent by email, the phone (later).
class Auth {
  Auth._();
  static final Auth i = Auth._();

  /// Firebase is set up (google-services.json was in the build).
  bool ready = false;
  bool _googleInit = false;

  User? get user => ready ? FirebaseAuth.instance.currentUser : null;

  /// Name to show: the Google name, else the email, else the phone number.
  String? get name {
    final u = user;
    if (u == null) return null;
    for (final v in [u.displayName, u.email, u.phoneNumber]) {
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// How the user signed in: Google, Email or Phone.
  String? get provider {
    final u = user;
    if (u == null) return null;
    final ids = u.providerData.map((p) => p.providerId).toSet();
    if (ids.contains('google.com')) return 'Google';
    if (ids.contains('phone')) return 'Phone';
    return 'Email';
  }

  String? get photoUrl => user?.photoURL;

  /// Bumps when the email link signs someone in (the sign-in card listens and closes).
  final ValueNotifier<int> emailSignIns = ValueNotifier(0);

  Future<void> init() async {
    try {
      await Firebase.initializeApp();
      ready = true;
      listenForEmailLink((_) => emailSignIns.value++);
    } catch (e) {
      debugPrint('Sign-in not set up (no Firebase config in this build): $e');
    }
  }

  /// The link from the email, pasted into the app (when tapping it does not open the app).
  Future<User?> signInWithPastedLink(String text) async {
    if (!ready) throw const AuthProblem("Sign-in isn't set up in this build yet.");
    final m = RegExp(r'https?://\S+').firstMatch(text.trim());
    final link = m?.group(0) ?? text.trim();
    if (!FirebaseAuth.instance.isSignInWithEmailLink(link)) {
      throw const AuthProblem('Paste the whole link from the email.');
    }
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_emailKey);
    if (email == null) throw const AuthProblem('Send the email again from this phone.');
    try {
      final u = (await FirebaseAuth.instance.signInWithEmailLink(email: email, emailLink: link)).user;
      await prefs.remove(_emailKey);
      return u;
    } on FirebaseAuthException catch (e) {
      throw AuthProblem(e.code == 'invalid-action-code'
          ? 'This link was used already or is too old. Send a new one.'
          : (e.message ?? e.code));
    }
  }

  /// Google: the account picker of the phone, then Firebase.
  Future<User?> google() async {
    if (!ready) throw const AuthProblem("Sign-in isn't set up in this build yet.");
    final gs = GoogleSignIn.instance;
    if (!_googleInit) {
      await gs.initialize();
      _googleInit = true;
    }
    final GoogleSignInAccount acc;
    try {
      acc = await gs.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw AuthProblem('Google sign-in failed (${e.code.name}).');
    }
    final idToken = acc.authentication.idToken;
    final cred = GoogleAuthProvider.credential(idToken: idToken);
    return (await FirebaseAuth.instance.signInWithCredential(cred)).user;
  }

  // ---- email link (no password: we email a link, tapping it on this phone signs you in)

  static const _emailKey = 'emailForSignIn';

  Future<void> sendEmailLink(String email) async {
    if (!ready) throw const AuthProblem("Sign-in isn't set up in this build yet.");
    final acs = ActionCodeSettings(
      url: 'https://$kFirebaseProject.firebaseapp.com/signin',
      handleCodeInApp: true,
      androidPackageName: 'com.mobility.mobility',
      androidInstallApp: true,
      androidMinimumVersion: '1',
    );
    try {
      await FirebaseAuth.instance.sendSignInLinkToEmail(email: email, actionCodeSettings: acs);
    } on FirebaseAuthException catch (e) {
      throw AuthProblem(e.code == 'invalid-email' ? 'That email address looks wrong.' : (e.message ?? e.code));
    }
    (await SharedPreferences.getInstance()).setString(_emailKey, email);
  }

  StreamSubscription<Uri>? _links;

  /// Waits for the link from the email (it opens the app); signs in when it comes.
  void listenForEmailLink(void Function(User user) onSignedIn) {
    if (!ready || _links != null) return;
    _links = AppLinks().uriLinkStream.listen((uri) async {
      final link = uri.toString();
      if (!FirebaseAuth.instance.isSignInWithEmailLink(link)) return;
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_emailKey);
      if (email == null) return; // the link was opened on another phone
      try {
        final u = (await FirebaseAuth.instance.signInWithEmailLink(email: email, emailLink: link)).user;
        await prefs.remove(_emailKey);
        if (u != null) onSignedIn(u);
      } catch (e) {
        debugPrint('Email link sign-in failed: $e');
      }
    });
  }

  // ---- phone (SMS code); used only when [kPhoneSignIn] is on

  Future<void> phoneStart(
    String number, {
    required void Function(String verificationId) codeSent,
    required void Function(User user) done,
    required void Function(String message) failed,
  }) async {
    if (!ready) return failed("Sign-in isn't set up in this build yet.");
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: number,
      verificationCompleted: (cred) async {
        // Android can read the SMS by itself
        final u = (await FirebaseAuth.instance.signInWithCredential(cred)).user;
        if (u != null) done(u);
      },
      verificationFailed: (e) => failed(e.message ?? e.code),
      codeSent: (id, _) => codeSent(id),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<User?> phoneCode(String verificationId, String code) async {
    final cred = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code);
    return (await FirebaseAuth.instance.signInWithCredential(cred)).user;
  }

  Future<void> signOut() async {
    if (!ready) return;
    await FirebaseAuth.instance.signOut();
    if (_googleInit) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
  }
}

/// A sign-in problem with a short message to show.
class AuthProblem implements Exception {
  final String message;
  const AuthProblem(this.message);
  @override
  String toString() => message;
}
