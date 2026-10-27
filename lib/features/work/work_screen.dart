import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/work_service.dart';

/// The working screen: go online, get offers, run a delivery.
class WorkScreen extends StatefulWidget {
  const WorkScreen({super.key, required this.rider});
  final Rider rider;

  @override
  State<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends State<WorkScreen> with WidgetsBindingObserver {
  late bool _online = widget.rider.online;
  bool _toggling = false;
  String? _error;

  Trip? _active;
  List<Trip> _offers = [];
  Earnings? _today;

  Timer? _poll;
  Timer? _ring;
  Timer? _tick;
  bool _busy = false;
  int _lastOfferCount = 0;

  /// A step the rider took that has not reached the server yet (no network at the door). It is kept on the phone, shown as
  /// "sending", and retried until the server answers, so a delivery done in a dead zone is not lost or done twice.
  Map<String, dynamic>? _queued;
  Timer? _retry;
  static const _queueKey = 'rider_pending_step';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WorkService.configure();
    _loadToday();
    if (_online) _startWorking();
    _loadQueue();
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _ring?.cancel();
    _tick?.cancel();
    _retry?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _loadToday();
    }
  }

  Future<void> _loadToday() async {
    try {
      final e = await Api.earnings();
      if (mounted) setState(() => _today = e);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    try {
      final r = await Api.offers();
      if (!mounted) return;
      final fresh = r.offers.length;
      setState(() {
        _active = r.active;
        _offers = r.offers;
        _online = _online || r.active != null;
      });
      if (fresh > _lastOfferCount) _startRinging();
      if (fresh == 0) _ring?.cancel();
      _lastOfferCount = fresh;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _startRinging() {
    _ring?.cancel();
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    _ring = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_offers.isEmpty) {
        _ring?.cancel();
        return;
      }
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    });
  }

  Future<bool> _ensureLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _error = 'Turn on location (GPS) so we can find deliveries near you.');
      return false;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      setState(() => _error = 'Location permission is needed to go online. Allow it in your phone settings.');
      return false;
    }
    return true;
  }

  Future<void> _toggle(bool on) async {
    if (_toggling) return;
    setState(() {
      _toggling = true;
      _error = null;
    });
    try {
      if (on && !await _ensureLocation()) return;
      await Api.setOnline(on);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _online = on);
      if (on) {
        await _startWorking();
      } else {
        _stopWorking();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _startWorking() async {
    WakelockPlus.enable();
    final s = Api.db.auth.currentSession;
    await WorkService.syncSession(s);
    await WorkService.start();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 10), (_) async {
      await WorkService.syncSession(Api.db.auth.currentSession);
      try {
        final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)));
        await Api.sendLocation(pos.latitude, pos.longitude);
      } catch (_) {}
    });
    _refresh();
  }

  void _stopWorking() {
    _poll?.cancel();
    _tick?.cancel();
    _ring?.cancel();
    WakelockPlus.disable();
    WorkService.stop();
    setState(() {
      _offers = [];
      _lastOfferCount = 0;
    });
  }

  Future<void> _accept(Trip t) async {
    setState(() => _busy = true);
    try {
      final trip = await Api.accept(t.id);
      _ring?.cancel();
      if (mounted) setState(() {
        _active = trip;
        _offers = [];
      });
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline(Trip t) async {
    try {
      await Api.decline(t.id);
    } catch (_) {}
    await _refresh();
  }

  bool _offline(ApiException e) => e.status == null && !e.needsPin && e.message.startsWith('No connection');

  Future<void> _loadQueue() async {
    final raw = (await SharedPreferences.getInstance()).getString(_queueKey);
    if (raw == null) return;
    try {
      _queued = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      _startRetry();
      if (mounted) setState(() {});
      unawaited(_flush());
    } catch (_) {}
  }

  Future<void> _saveQueue() async {
    final prefs = await SharedPreferences.getInstance();
    if (_queued == null) {
      await prefs.remove(_queueKey);
    } else {
      await prefs.setString(_queueKey, jsonEncode(_queued));
    }
  }

  void _startRetry() {
    _retry?.cancel();
    _retry = Timer.periodic(const Duration(seconds: 6), (_) => _flush());
  }

  Future<void> _step(String step, {String? pin, String? reason}) async {
    final t = _active;
    if (t == null || _queued != null) return;
    try {
      await Api.step(t.id, step, pin: pin, overrideReason: reason);
      await _stepDone(t, step);
    } on ApiException catch (e) {
      if (_offline(e)) {
        // No network: keep the step, show it as sending, and keep trying until the server confirms it.
        _queued = {'tripId': t.id, 'step': step, 'pin': pin, 'reason': reason};
        await _saveQueue();
        _startRetry();
        if (mounted) setState(() {});
      } else if (e.needsPin && step == 'delivered') {
        await _askPin(e.message);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  bool _flushing = false;

  Future<void> _flush() async {
    final q = _queued;
    if (q == null || _flushing) return;
    _flushing = true;
    try {
      await Api.step(q['tripId'] as String, q['step'] as String, pin: q['pin'] as String?, overrideReason: q['reason'] as String?);
      final t = _active;
      _queued = null;
      _retry?.cancel();
      await _saveQueue();
      if (t != null && t.id == q['tripId']) {
        await _stepDone(t, q['step'] as String);
      } else {
        if (mounted) setState(() {});
        await _refresh();
      }
    } on ApiException catch (e) {
      if (!_offline(e)) {
        // The server answered and said no (for example a wrong code): stop retrying and tell the rider.
        _queued = null;
        _retry?.cancel();
        await _saveQueue();
        if (e.needsPin) {
          if (mounted) setState(() {});
          await _askPin(e.message);
        } else if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _stepDone(Trip t, String step) async {
    if (step == 'delivered') {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _active = null);
      _loadToday();
      if (mounted) _showDone(t);
    } else if (mounted) {
      setState(() {});
    }
    await _refresh();
  }

  Future<void> _askPin(String message) async {
    final pin = TextEditingController();
    final reason = TextEditingController();
    var override = false;
    final result = await showDialog<({String? pin, String? reason})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: Rd.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text("Customer's delivery code", style: TextStyle(fontWeight: FontWeight.w900)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(message, style: const TextStyle(color: Rd.muted, height: 1.4)),
            const SizedBox(height: 14),
            if (!override)
              TextField(
                controller: pin,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 10),
                decoration: const InputDecoration(counterText: '', hintText: '••••'),
              )
            else
              TextField(controller: reason, decoration: const InputDecoration(labelText: 'Why the code could not be used')),
            TextButton(onPressed: () => set(() => override = !override), child: Text(override ? 'Enter the code instead' : "Customer can't give the code")),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(110, 48)),
              onPressed: () => Navigator.pop(ctx, (pin: override ? null : pin.text.trim(), reason: override ? reason.text.trim() : null)),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _step('delivered', pin: result.pin, reason: result.reason);
  }

  void _showDone(Trip t) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Rd.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 84, height: 84, decoration: BoxDecoration(color: Rd.online.withValues(alpha: 0.15), shape: BoxShape.circle), child: const Icon(Icons.check_rounded, color: Rd.online, size: 50)),
          const SizedBox(height: 18),
          const Text('Delivered!', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('You earned ${rupees(t.fee)} for ${t.orderNumber}', style: const TextStyle(color: Rd.muted, fontSize: 16)),
          if (t.cod) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Remember to hand over ${rupees(t.collect)} cash collected.', style: const TextStyle(color: Rd.warn, fontWeight: FontWeight.w800))),
          const SizedBox(height: 22),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back to work')),
        ]),
      ),
    );
  }

  Future<void> _drop() async {
    final t = _active;
    if (t == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Rd.card,
        title: const Text('Give up this delivery?', style: TextStyle(fontWeight: FontWeight.w900)),
        content: const Text('It will be offered to another rider. Dropping deliveries often can pause your account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Rd.bad, minimumSize: const Size(110, 48)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Give up')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.drop(t.id);
      if (mounted) setState(() => _active = null);
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _navigate(double? lat, double? lng, String? label) async {
    if (lat == null || lng == null) return;
    final uri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=two-wheeler'), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _refresh();
            await _loadToday();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _Header(rider: widget.rider, online: _online, toggling: _toggling, onToggle: _active != null ? null : _toggle),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Rd.bad.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Icon(Icons.error_outline_rounded, color: Rd.bad),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!, style: const TextStyle(fontWeight: FontWeight.w700))),
                      IconButton(onPressed: () => setState(() => _error = null), icon: const Icon(Icons.close_rounded, size: 18)),
                    ]),
                  ),
                ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: StatTile(label: 'Today', value: rupees(_today?.today ?? 0), icon: Icons.account_balance_wallet_rounded)),
                const SizedBox(width: 10),
                Expanded(child: StatTile(label: 'Trips', value: '${widget.rider.totalDeliveries}', icon: Icons.check_circle_outline_rounded)),
              ]),
              const SizedBox(height: 18),
              if (_active != null)
                _TripPanel(trip: _active!, onStep: _step, onNavigate: _navigate, onDrop: _drop, pendingStep: _queued != null && _queued!['tripId'] == _active!.id ? _queued!['step'] as String : null)
              else if (_offers.isNotEmpty)
                for (final o in _offers) _OfferCard(trip: o, busy: _busy, onAccept: () => _accept(o), onDecline: () => _decline(o))
              else
                _Idle(online: _online),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.rider, required this.online, required this.toggling, required this.onToggle});
  final Rider rider;
  final bool online;
  final bool toggling;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final first = rider.name.split(' ').first;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(colors: online ? const [Color(0xFF065F46), Color(0xFF16A34A)] : const [Color(0xFF241C3F), Color(0xFF16122A)]),
        border: Border.all(color: online ? Rd.online.withValues(alpha: 0.5) : Rd.line),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hi, $first', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(online ? 'You are online' : 'You are offline', style: TextStyle(color: online ? Colors.white : Rd.muted, fontWeight: FontWeight.w700)),
          ]),
        ),
        if (toggling)
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))
        else
          Switch.adaptive(value: online, onChanged: onToggle, activeTrackColor: Colors.white, activeThumbColor: Rd.online),
      ]),
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.online});
  final bool online;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(children: [
        Radar(active: online),
        const SizedBox(height: 8),
        Text(online ? 'Looking for deliveries…' : 'Go online to start earning', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(
          online ? 'Stay near busy shops. We will ring you the moment an order is ready.' : 'Flip the switch above. We use your location only while you are online.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Rd.muted, height: 1.45),
        ),
      ]),
    );
  }
}

class _OfferCard extends StatefulWidget {
  const _OfferCard({required this.trip, required this.busy, required this.onAccept, required this.onDecline});
  final Trip trip;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  Timer? _t;
  int _left = 0;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _recount();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _recount());
  }

  void _recount() {
    final e = widget.trip.expiresAt;
    final left = e == null ? 60 : e.difference(DateTime.now()).inSeconds.clamp(0, 600);
    if (mounted) setState(() => _left = left);
    if (left == 0 && !_expired) {
      _expired = true;
      widget.onDecline();
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trip;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Rd.card, borderRadius: BorderRadius.circular(26), border: Border.all(color: Rd.accent, width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('NEW DELIVERY', style: TextStyle(color: Rd.accent, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: (_left <= 15 ? Rd.bad : Rd.warn).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(999)),
            child: Text('${_left}s', style: TextStyle(fontWeight: FontWeight.w900, color: _left <= 15 ? Rd.bad : Rd.warn)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(rupees(t.fee), style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: -1)),
          const SizedBox(width: 10),
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('${t.distanceKm?.toStringAsFixed(1) ?? '?'} km', style: const TextStyle(color: Rd.muted, fontWeight: FontWeight.w800, fontSize: 16))),
        ]),
        const SizedBox(height: 14),
        _Leg(icon: Icons.storefront_rounded, color: const Color(0xFFF97316), title: 'Pick up', text: '${t.shopName}${t.shopAddress != null ? ' · ${t.shopAddress}' : ''}'),
        const SizedBox(height: 10),
        _Leg(icon: Icons.home_rounded, color: Rd.online, title: 'Drop', text: t.dropAddress ?? 'Customer address'),
        if (t.cod) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Cash on delivery · collect ${rupees(t.collect)}', style: const TextStyle(color: Rd.warn, fontWeight: FontWeight.w900))),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: widget.busy ? null : widget.onDecline, child: const Text('Decline'))),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: FilledButton(onPressed: widget.busy ? null : widget.onAccept, child: Text(widget.busy ? 'Accepting…' : 'Accept'))),
        ]),
      ]),
    );
  }
}

class _Leg extends StatelessWidget {
  const _Leg({required this.icon, required this.color, required this.title, required this.text});
  final IconData icon;
  final Color color;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 38, height: 38, decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Rd.muted, fontSize: 12, fontWeight: FontWeight.w800)),
          Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
        ]),
      ),
    ]);
  }
}

class _TripPanel extends StatelessWidget {
  const _TripPanel({required this.trip, required this.onStep, required this.onNavigate, required this.onDrop, this.pendingStep});
  final Trip trip;
  /// A step waiting to reach the server (no network). While set, the slider is replaced by a sending notice.
  final String? pendingStep;
  final Future<void> Function(String step, {String? pin, String? reason}) onStep;
  final Future<void> Function(double?, double?, String?) onNavigate;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    final toShop = trip.status == 'assigned' || trip.status == 'at_pickup';
    final stage = trip.status == 'assigned' ? 0 : trip.status == 'at_pickup' ? 1 : 2;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Rd.card, borderRadius: BorderRadius.circular(26), border: Border.all(color: Rd.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(trip.orderNumber, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          const Spacer(),
          Text(rupees(trip.fee), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Rd.online)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          for (var i = 0; i < 3; i++) ...[
            Expanded(child: Container(height: 5, decoration: BoxDecoration(color: i <= stage ? Rd.accent : Rd.line, borderRadius: BorderRadius.circular(3)))),
            if (i < 2) const SizedBox(width: 6),
          ],
        ]),
        const SizedBox(height: 8),
        Text(stage == 0 ? 'Head to the shop' : stage == 1 ? 'Collect the order' : 'Deliver to the customer', style: const TextStyle(color: Rd.muted, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        if (toShop) ...[
          _Leg(icon: Icons.storefront_rounded, color: const Color(0xFFF97316), title: 'Pick up from', text: '${trip.shopName}${trip.shopAddress != null ? '\n${trip.shopAddress}' : ''}'),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => onNavigate(trip.shopLat, trip.shopLng, trip.shopName), icon: const Icon(Icons.navigation_rounded), label: const Text('Navigate'))),
            if (trip.shopPhone != null) ...[
              const SizedBox(width: 10),
              OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(60, 52)), onPressed: () => launchUrl(Uri.parse('tel:${trip.shopPhone}')), child: const Icon(Icons.call_rounded)),
            ],
          ]),
          const SizedBox(height: 14),
          const Text('ITEMS', style: TextStyle(color: Rd.muted, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 6),
          for (final i in trip.items) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('${i.quantity} × ${i.name}', style: const TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(height: 18),
          if (pendingStep != null)
            _SendingNotice(step: pendingStep!)
          else if (trip.status == 'assigned')
            SlideToConfirm(label: "Slide when you're at the shop", color: Rd.accent, onConfirmed: () => onStep('arrived_pickup'))
          else
            SlideToConfirm(label: 'Slide when picked up', color: const Color(0xFFF97316), onConfirmed: () => onStep('picked_up')),
        ] else ...[
          _Leg(icon: Icons.home_rounded, color: Rd.online, title: 'Deliver to ${trip.customerName ?? 'customer'}', text: trip.dropAddress ?? ''),
          if (trip.note != null && trip.note!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Note: ${trip.note}', style: const TextStyle(color: Rd.warn, fontWeight: FontWeight.w700))),
          if (trip.cod) Container(margin: const EdgeInsets.only(top: 14), width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Rd.warn.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)), child: Text('Collect ${rupees(trip.collect)} in cash', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Rd.warn))),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => onNavigate(trip.dropLat, trip.dropLng, trip.dropAddress), icon: const Icon(Icons.navigation_rounded), label: const Text('Navigate'))),
            if (trip.customerPhone != null) ...[
              const SizedBox(width: 10),
              OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(60, 52)), onPressed: () => launchUrl(Uri.parse('tel:${trip.customerPhone}')), child: const Icon(Icons.call_rounded)),
            ],
          ]),
          const SizedBox(height: 18),
          if (pendingStep != null)
            _SendingNotice(step: pendingStep!)
          else
            SlideToConfirm(label: 'Slide when delivered', color: Rd.online, onConfirmed: () => onStep('delivered')),
        ],
        if (toShop && pendingStep == null) TextButton(onPressed: onDrop, style: TextButton.styleFrom(foregroundColor: Rd.bad), child: const Text('Give up this delivery')),
      ]),
    );
  }
}

/// Shown instead of the slider while a step has not reached the server: it spins and says it will confirm by itself.
class _SendingNotice extends StatelessWidget {
  const _SendingNotice({required this.step});
  final String step;

  @override
  Widget build(BuildContext context) {
    final what = step == 'delivered' ? 'Delivery' : step == 'picked_up' ? 'Pick-up' : 'Arrival';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Rd.warn.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: Rd.warn)),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            '$what saved on this phone. Sending to Hyperpik, it will confirm by itself as soon as you have network. Keep the app open.',
            style: const TextStyle(color: Rd.warn, fontWeight: FontWeight.w700, height: 1.35),
          ),
        ),
      ]),
    );
  }
}
