import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/api.dart';
import 'core/config.dart';
import 'core/models.dart';
import 'core/theme.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/onboarding/onboarding_screens.dart';
import 'features/shell/rider_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
  runApp(const RiderApp());
}

class RiderApp extends StatelessWidget {
  const RiderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hyperpik Rider',
      debugShowCheckedModeBanner: false,
      theme: Rd.theme(),
      home: const _Gate(),
    );
  }
}

/// Decides which screen a person belongs on: sign in, apply, finish documents, wait for approval, or work.
class _Gate extends StatefulWidget {
  const _Gate();

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  StreamSubscription<AuthState>? _sub;
  Me? _me;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _sub = Api.db.auth.onAuthStateChange.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (Api.user == null) {
      if (mounted) setState(() => _me = null);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final me = await Api.me();
      if (mounted) setState(() {
        _me = me;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Api.user == null) return const SignInScreen();
    if (_error != null && _me == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Try again')),
              TextButton(onPressed: Api.signOut, child: const Text('Sign out')),
            ]),
          ),
        ),
      );
    }
    final me = _me;
    if (me == null || (_loading && me.rider == null)) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final rider = me.rider;
    if (rider == null) return ApplyScreen(onDone: _load);
    if (rider.approved) return RiderShell(rider: rider, onRefresh: _load);
    return StatusScreen(me: me, onChanged: _load);
  }
}
