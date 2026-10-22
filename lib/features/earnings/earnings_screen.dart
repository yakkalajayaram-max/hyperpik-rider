import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../profile/bank_screen.dart';

/// What the rider has earned, what Hyperpik still owes them, what it has already paid (each payout with its bank reference),
/// a seven-day chart and the latest trips. Hyperpik pays riders by bank transfer, so without a bank account on file the screen
/// asks for one.
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key, required this.active});
  final bool active;

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  Earnings? _e;
  List<Payout> _payouts = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant EarningsScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  Future<void> _load() async {
    try {
      final e = await Api.earnings();
      List<Payout> payouts = _payouts;
      try {
        payouts = await Api.payouts();
      } on ApiException {
        // The earnings still show; the history just stays as it was.
      }
      if (mounted) setState(() {
        _e = e;
        _payouts = payouts;
        _error = null;
      });
    } on ApiException catch (ex) {
      if (mounted) setState(() => _error = ex.message);
    }
  }

  /// Earnings per day for the last seven days, oldest first.
  List<(String, num)> _week(Earnings e) {
    final today = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) DateTime(today.year, today.month, today.day).subtract(Duration(days: i))];
    return [
      for (final d in days)
        (
          DateFormat('E').format(d).substring(0, 1),
          e.recent.where((r) => r.at.year == d.year && r.at.month == d.month && r.at.day == d.day).fold<num>(0, (a, r) => a + r.amount),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final e = _e;
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings', style: TextStyle(fontWeight: FontWeight.w900))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _error != null && e == null
            ? ListView(children: [const SizedBox(height: 120), Center(child: Text(_error!))])
            : e == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), gradient: const LinearGradient(colors: [Color(0xFF4C1D95), Color(0xFF7C4DFF)])),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Total earned', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(rupees(e.total), style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: -1)),
                          const SizedBox(height: 4),
                          Text('${e.trips} deliveries', style: const TextStyle(color: Colors.white70)),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(child: StatTile(label: 'Owed to you', value: rupees(e.owed))),
                        const SizedBox(width: 10),
                        Expanded(child: StatTile(label: 'Paid so far', value: rupees(e.paid))),
                      ]),
                      if (!e.hasBank) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: Rd.bad.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Rd.bad.withValues(alpha: 0.35))),
                          child: Row(children: [
                            const Icon(Icons.account_balance_rounded, color: Rd.bad),
                            const SizedBox(width: 10),
                            const Expanded(child: Text('Add your bank account so Hyperpik can pay you.', style: TextStyle(fontWeight: FontWeight.w700, height: 1.3))),
                            TextButton(
                              onPressed: () async {
                                final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const BankScreen()));
                                if (saved == true) _load();
                              },
                              child: const Text('Add'),
                            ),
                          ]),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: StatTile(label: 'Today', value: rupees(e.today))),
                        const SizedBox(width: 10),
                        Expanded(child: StatTile(label: 'This week', value: rupees(e.week))),
                        const SizedBox(width: 10),
                        Expanded(child: StatTile(label: '30 days', value: rupees(e.month))),
                      ]),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Rd.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: Rd.line)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Last 7 days', style: TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 16),
                          _Bars(data: _week(e)),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      if (e.note != null)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: Rd.warn.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Rd.warn.withValues(alpha: 0.3))),
                          child: Row(children: [
                            const Icon(Icons.info_outline_rounded, color: Rd.warn),
                            const SizedBox(width: 10),
                            Expanded(child: Text(e.note!, style: const TextStyle(height: 1.35, fontWeight: FontWeight.w600))),
                          ]),
                        ),
                      const SizedBox(height: 18),
                      const Text('Payouts', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      if (_payouts.isEmpty)
                        const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('No payouts yet. Each one will show here with its bank reference.', textAlign: TextAlign.center, style: TextStyle(color: Rd.muted))))
                      else
                        Container(
                          decoration: BoxDecoration(color: Rd.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: Rd.line)),
                          child: Column(children: [
                            for (var i = 0; i < _payouts.length; i++) ...[
                              if (i > 0) const Divider(height: 1, color: Rd.line),
                              ListTile(
                                leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: Rd.accent.withValues(alpha: 0.16), shape: BoxShape.circle), child: const Icon(Icons.account_balance_rounded, color: Rd.accent)),
                                title: Text(rupees(_payouts[i].amount), style: const TextStyle(fontWeight: FontWeight.w900)),
                                subtitle: Text('${DateFormat('d MMM yyyy').format(_payouts[i].at)} · ${_payouts[i].reference}', style: const TextStyle(color: Rd.muted)),
                              ),
                            ],
                          ]),
                        ),
                      const SizedBox(height: 18),
                      const Text('Recent deliveries', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      if (e.recent.isEmpty)
                        const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Your deliveries will show up here.', style: TextStyle(color: Rd.muted))))
                      else
                        Container(
                          decoration: BoxDecoration(color: Rd.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: Rd.line)),
                          child: Column(children: [
                            for (var i = 0; i < e.recent.length; i++) ...[
                              if (i > 0) const Divider(height: 1, color: Rd.line),
                              ListTile(
                                leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: Rd.online.withValues(alpha: 0.14), shape: BoxShape.circle), child: const Icon(Icons.check_rounded, color: Rd.online)),
                                title: Text(e.recent[i].order ?? 'Delivery', style: const TextStyle(fontWeight: FontWeight.w800)),
                                subtitle: Text(DateFormat('d MMM, h:mm a').format(e.recent[i].at), style: const TextStyle(color: Rd.muted)),
                                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  Text('+${rupees(e.recent[i].amount)}', style: const TextStyle(fontWeight: FontWeight.w900, color: Rd.online, fontSize: 16)),
                                  Text(e.recent[i].paidAt != null ? 'paid' : 'owed', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: e.recent[i].paidAt != null ? Rd.online : Rd.warn)),
                                ]),
                              ),
                            ],
                          ]),
                        ),
                    ],
                  ),
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.data});
  final List<(String, num)> data;

  @override
  Widget build(BuildContext context) {
    final max = data.fold<num>(1, (a, d) => d.$2 > a ? d.$2 : a);
    return SizedBox(
      height: 130,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final d in data)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (d.$2 > 0) Text('${d.$2.round()}', style: const TextStyle(fontSize: 10.5, color: Rd.muted, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  height: d.$2 <= 0 ? 4 : (90 * (d.$2 / max)).toDouble().clamp(6, 90),
                  decoration: BoxDecoration(color: d.$2 > 0 ? Rd.accent : Rd.line, borderRadius: BorderRadius.circular(8)),
                ),
                const SizedBox(height: 6),
                Text(d.$1, style: const TextStyle(color: Rd.muted, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
      ]),
    );
  }
}
