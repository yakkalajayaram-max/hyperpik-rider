import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/theme.dart';

/// Where Hyperpik sends the rider's earnings. The rider types the account holder's name, the account number and the IFSC;
/// the server checks them again and keeps the number, and the app only ever shows the last four digits afterwards.
class BankScreen extends StatefulWidget {
  const BankScreen({super.key});

  @override
  State<BankScreen> createState() => _BankScreenState();
}

class _BankScreenState extends State<BankScreen> {
  final _holder = TextEditingController();
  final _account = TextEditingController();
  final _account2 = TextEditingController();
  final _ifsc = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _holder.dispose();
    _account.dispose();
    _account2.dispose();
    _ifsc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final holder = _holder.text.trim();
    final account = _account.text.replaceAll(' ', '');
    final ifsc = _ifsc.text.replaceAll(' ', '').toUpperCase();
    if (holder.length < 3) return setState(() => _error = "Enter the account holder's name as it is on the bank account.");
    if (!RegExp(r'^\d{9,18}$').hasMatch(account)) return setState(() => _error = 'The account number should be 9 to 18 digits.');
    if (account != _account2.text.replaceAll(' ', '')) return setState(() => _error = 'The two account numbers do not match.');
    if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(ifsc)) return setState(() => _error = 'The IFSC should look like SBIN0001234.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.saveBank(holderName: holder, accountNumber: account, ifsc: ifsc);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bank account', style: TextStyle(fontWeight: FontWeight.w900))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Hyperpik pays your earnings to this account. Check it carefully: a wrong number sends your money to someone else.', style: TextStyle(color: Rd.muted, height: 1.4)),
          const SizedBox(height: 18),
          TextField(controller: _holder, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Account holder name')),
          const SizedBox(height: 12),
          TextField(controller: _account, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Account number')),
          const SizedBox(height: 12),
          TextField(controller: _account2, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Re-enter account number')),
          const SizedBox(height: 12),
          TextField(controller: _ifsc, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'IFSC code')),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: const TextStyle(color: Rd.bad, fontWeight: FontWeight.w700))),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(_busy ? 'Saving…' : 'Save bank account')),
          ),
        ],
      ),
    );
  }
}
