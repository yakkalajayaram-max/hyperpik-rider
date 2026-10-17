import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api.dart';
import '../../core/theme.dart';

/// Phone number and a code by SMS: the same sign-in as the rest of Hyperpik.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const SizedBox(height: 40),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(color: Rd.accent, borderRadius: BorderRadius.circular(24)),
                child: const Icon(Icons.two_wheeler_rounded, size: 42, color: Colors.white),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Ride with Hyperpik', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
            const SizedBox(height: 8),
            const Text('Deliver orders near you, on your own time, and see exactly what each trip earns.', style: TextStyle(color: Rd.muted, height: 1.4, fontSize: 15)),
            const SizedBox(height: 36),
            if (!_sent) ...[
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91  '),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 10) {
                            setState(() => _error = 'Enter your 10-digit mobile number.');
                            return;
                          }
                          await Api.sendOtp(_phone.text);
                          if (mounted) setState(() => _sent = true);
                        }),
                child: Text(_busy ? 'Sending…' : 'Send code'),
              ),
            ] else ...[
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 4),
                decoration: InputDecoration(labelText: 'Code sent to +91 ${_phone.text}'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          if (_code.text.trim().length < 4) {
                            setState(() => _error = 'Enter the code we sent you.');
                            return;
                          }
                          await Api.verifyOtp(_phone.text, _code.text);
                        }),
                child: Text(_busy ? 'Checking…' : 'Sign in'),
              ),
              TextButton(onPressed: _busy ? null : () => setState(() => _sent = false), child: const Text('Use a different number')),
            ],
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: const TextStyle(color: Rd.bad, fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }
}
