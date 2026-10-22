import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/work_service.dart';
import 'bank_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.rider, required this.onRefresh});
  final Rider rider;
  final VoidCallback onRefresh;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _version = '';
  BankAccount? _bank;
  bool _bankLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBank();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = '${p.version} (${p.buildNumber})');
    });
  }

  Future<void> _loadBank() async {
    try {
      final b = await Api.bank();
      if (mounted) setState(() {
        _bank = b;
        _bankLoaded = true;
      });
    } on ApiException {
      if (mounted) setState(() => _bankLoaded = true);
    }
  }

  String get _vehicle => switch (widget.rider.vehicleType) {
        'bike' => 'Motorbike',
        'scooter' => 'Scooter',
        'ev' => 'Electric scooter',
        'cycle' => 'Cycle',
        _ => widget.rider.vehicleType,
      };

  @override
  Widget build(BuildContext context) {
    final r = widget.rider;
    Widget row(IconData icon, String label, String value) => ListTile(
          leading: Icon(icon, color: Rd.accent),
          title: Text(label, style: const TextStyle(color: Rd.muted, fontSize: 12.5, fontWeight: FontWeight.w700)),
          subtitle: Text(value.isEmpty ? '—' : value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Me', style: TextStyle(fontWeight: FontWeight.w900))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Rd.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: Rd.line)),
            child: Row(children: [
              CircleAvatar(radius: 34, backgroundColor: Rd.accent, child: Text(r.name.isEmpty ? '?' : r.name.characters.first.toUpperCase(), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white))),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text('+91 ${r.phone}', style: const TextStyle(color: Rd.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Rd.online.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.verified_rounded, size: 15, color: Rd.online), SizedBox(width: 5), Text('Verified rider', style: TextStyle(color: Rd.online, fontWeight: FontWeight.w900, fontSize: 12.5))]),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(color: Rd.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: Rd.line)),
            child: Column(children: [
              row(Icons.two_wheeler_rounded, 'Vehicle', '$_vehicle${r.vehicleNumber != null ? ' · ${r.vehicleNumber}' : ''}'),
              const Divider(height: 1, color: Rd.line),
              row(Icons.badge_rounded, 'Licence number', r.licenseNumber ?? ''),
              const Divider(height: 1, color: Rd.line),
              row(Icons.location_city_rounded, 'City', r.city ?? ''),
              const Divider(height: 1, color: Rd.line),
              row(Icons.check_circle_rounded, 'Deliveries', '${r.totalDeliveries}'),
            ]),
          ),
          const SizedBox(height: 14),
          if (r.ownerType == 'platform')
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: Rd.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: Rd.line)),
              child: ListTile(
                leading: const Icon(Icons.account_balance_rounded, color: Rd.accent),
                title: const Text('Bank account for payouts', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(
                  !_bankLoaded ? 'Loading…' : (_bank == null ? 'Not added yet. Hyperpik needs it to pay you.' : '${_bank!.holderName} · A/c ending ${_bank!.last4} · ${_bank!.ifsc}'),
                  style: TextStyle(color: _bankLoaded && _bank == null ? Rd.warn : Rd.muted, fontWeight: FontWeight.w600),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const BankScreen()));
                  if (saved == true) _loadBank();
                },
              ),
            ),
          Container(
            decoration: BoxDecoration(color: Rd.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: Rd.line)),
            child: ListTile(
              leading: const Icon(Icons.logout_rounded, color: Rd.bad),
              title: const Text('Sign out', style: TextStyle(fontWeight: FontWeight.w800, color: Rd.bad)),
              onTap: () async {
                try {
                  await Api.setOnline(false);
                } catch (_) {}
                await WorkService.stop();
                await Api.signOut();
              },
            ),
          ),
          const SizedBox(height: 20),
          Center(child: Text(_version.isEmpty ? 'Hyperpik Rider' : 'Hyperpik Rider $_version', style: const TextStyle(color: Rd.muted, fontSize: 12))),
        ],
      ),
    );
  }
}
