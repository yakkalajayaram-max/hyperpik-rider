import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';

const _docLabels = {
  'photo': 'Your photo',
  'license': 'Driving licence',
  'aadhaar': 'Aadhaar card',
  'vehicle_rc': 'Vehicle RC (optional)',
  'pan': 'PAN card (optional)',
  'bank_proof': 'Bank proof (optional)',
};

/// Step one: who you are and what you ride.
class ApplyScreen extends StatefulWidget {
  const ApplyScreen({super.key, required this.onDone, this.existing});
  final VoidCallback onDone;
  final Rider? existing;

  @override
  State<ApplyScreen> createState() => _ApplyScreenState();
}

class _ApplyScreenState extends State<ApplyScreen> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _city = TextEditingController(text: widget.existing?.city ?? '');
  late final _vehicleNo = TextEditingController(text: widget.existing?.vehicleNumber ?? '');
  late final _license = TextEditingController(text: widget.existing?.licenseNumber ?? '');
  late String _vehicle = widget.existing?.vehicleType ?? 'bike';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _city, _vehicleNo, _license]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.apply(
        fullName: _name.text,
        phone: _phone.text,
        vehicleType: _vehicle,
        city: _city.text,
        vehicleNumber: _vehicleNo.text,
        licenseNumber: _license.text,
      );
      widget.onDone();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Become a rider', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [TextButton(onPressed: Api.signOut, child: const Text('Sign out'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Step 1 of 2', style: TextStyle(color: Rd.accent, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Tell us about you', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 20),
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 14),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91  ')),
          const SizedBox(height: 14),
          TextField(controller: _city, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'City')),
          const SizedBox(height: 20),
          const Text('What do you ride?', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final v in const [('bike', 'Motorbike', Icons.two_wheeler_rounded), ('scooter', 'Scooter', Icons.electric_moped_rounded), ('ev', 'Electric', Icons.bolt_rounded), ('cycle', 'Cycle', Icons.pedal_bike_rounded)])
              ChoiceChip(
                avatar: Icon(v.$3, size: 18),
                label: Text(v.$2),
                selected: _vehicle == v.$1,
                onSelected: (_) => setState(() => _vehicle = v.$1),
              ),
          ]),
          const SizedBox(height: 18),
          TextField(controller: _vehicleNo, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Vehicle number (e.g. TS09AB1234)')),
          const SizedBox(height: 14),
          TextField(controller: _license, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Driving licence number')),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: const TextStyle(color: Rd.bad, fontWeight: FontWeight.w700))),
          const SizedBox(height: 24),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Saving…' : 'Continue')),
        ],
      ),
    );
  }
}

/// Step two and everything after: upload documents, wait for approval, or fix what was turned away.
class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key, required this.me, required this.onChanged});
  final Me me;
  final VoidCallback onChanged;

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final _picker = ImagePicker();
  String? _uploading;
  String? _error;
  bool _editing = false;
  Timer? _watch;

  @override
  void initState() {
    super.initState();
    // Approval happens on the admin side: look again every half minute so the rider is let in without pulling to refresh.
    _watch = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_editing && _uploading == null) widget.onChanged();
    });
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  Future<void> _upload(String kind) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final shot = await _picker.pickImage(source: source, maxWidth: 1800, imageQuality: 82);
    if (shot == null) return;
    setState(() {
      _uploading = kind;
      _error = null;
    });
    try {
      await Api.uploadDocument(kind: kind, bytes: await shot.readAsBytes(), filename: shot.name);
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rider = widget.me.rider!;
    if (_editing) return ApplyScreen(existing: rider, onDone: () {
      setState(() => _editing = false);
      widget.onChanged();
    });

    final have = {for (final d in widget.me.documents) d.kind: d};
    final required = widget.me.required.isEmpty ? const ['photo', 'license', 'aadhaar'] : widget.me.required;
    final missing = required.where((k) => !have.containsKey(k) || have[k]!.status == 'rejected').toList();
    final suspended = rider.status == 'suspended';
    final rejected = rider.status == 'rejected';

    return Scaffold(
      appBar: AppBar(
        title: Text(suspended ? 'Account paused' : 'Your application', style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [TextButton(onPressed: Api.signOut, child: const Text('Sign out'))],
      ),
      body: RefreshIndicator(
        onRefresh: () async => widget.onChanged(),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Banner(
              icon: suspended ? Icons.pause_circle_rounded : rejected ? Icons.error_rounded : missing.isNotEmpty ? Icons.upload_file_rounded : Icons.hourglass_top_rounded,
              color: suspended || rejected ? Rd.bad : missing.isNotEmpty ? Rd.warn : Rd.accent,
              title: suspended
                  ? 'Your account is paused'
                  : rejected
                      ? 'Your application needs changes'
                      : missing.isNotEmpty
                          ? 'Add your documents'
                          : 'Under review',
              body: suspended
                  ? 'Please contact Hyperpik support to find out why and how to continue.'
                  : rejected
                      ? (rider.rejectionReason ?? 'Please check your details and documents and send them again.')
                      : missing.isNotEmpty
                          ? 'Step 2 of 2. Upload clear photos of the documents below so we can verify you.'
                          : 'We have your documents. We will tell you as soon as you are approved, usually within a day.',
            ),
            const SizedBox(height: 20),
            if (!suspended) ...[
              for (final kind in _docLabels.keys) _DocRow(
                label: _docLabels[kind]!,
                status: have[kind],
                required: required.contains(kind),
                uploading: _uploading == kind,
                onTap: () => _upload(kind),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Rd.bad, fontWeight: FontWeight.w700))),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: () => setState(() => _editing = true), child: const Text('Edit my details')),
            ],
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.title, required this.body});
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(22), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(body, style: const TextStyle(color: Rd.muted, height: 1.4)),
          ]),
        ),
      ]),
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({required this.label, required this.status, required this.required, required this.uploading, required this.onTap});
  final String label;
  final DocStatus? status;
  final bool required;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = status?.status;
    final color = s == 'approved' ? Rd.online : s == 'rejected' ? Rd.bad : s == 'pending' ? Rd.warn : Rd.muted;
    final text = s == 'approved' ? 'Verified' : s == 'rejected' ? (status?.note ?? 'Rejected, upload again') : s == 'pending' ? 'Uploaded, being checked' : required ? 'Required' : 'Optional';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Icon(s == 'approved' ? Icons.verified_rounded : s == null ? Icons.add_a_photo_rounded : Icons.description_rounded, color: color),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          trailing: uploading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : TextButton(onPressed: s == 'approved' ? null : onTap, child: Text(s == null ? 'Upload' : 'Replace')),
        ),
      ),
    );
  }
}
