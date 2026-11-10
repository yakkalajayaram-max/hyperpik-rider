import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';

/// Where this app's releases live: a Supabase Storage bucket holding `manifest.json` and the APKs
/// (written by tools/upload-apk.mjs when a release is built).
const String kReleaseBucket = 'rider-app-releases';

/// A private bucket is read with a short-lived signed link, which only a signed-in person with access can get.
const bool kReleaseBucketIsPrivate = false;
const String kAppLabel = 'Hyperpik Rider';

@immutable
class AppRelease {
  const AppRelease({required this.version, required this.build, required this.minBuild, required this.path, this.sha256, this.size, this.notes});

  final String version;

  /// The number after "+" in pubspec.yaml; versions are compared on this.
  final int build;

  /// Builds below this are stopped at an "Update required" screen.
  final int minBuild;
  final String path;
  final String? sha256;
  final int? size;
  final String? notes;

  static AppRelease? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final build = (raw['build'] as num?)?.toInt();
    final path = raw['path'] as String?;
    if (build == null || path == null || path.isEmpty) return null;
    return AppRelease(
      version: raw['version'] as String? ?? '$build',
      build: build,
      minBuild: (raw['minBuild'] as num?)?.toInt() ?? 0,
      path: path,
      sha256: (raw['sha256'] as String?)?.toLowerCase(),
      size: (raw['size'] as num?)?.toInt(),
      notes: raw['notes'] as String?,
    );
  }
}

enum UpdateStage { idle, downloading, installing, failed }

/// Checks for a newer build and installs it (Android). Android always asks for one tap on Install, and the first time
/// for permission to install apps from this one. A failed check is silent: being offline never blocks the app.
class AppUpdate extends ChangeNotifier {
  AppUpdate._();
  static final AppUpdate instance = AppUpdate._();

  String installedVersion = '';
  int installedBuild = 0;
  AppRelease? release;
  UpdateStage stage = UpdateStage.idle;
  double progress = 0;
  String? error;

  Timer? _timer;
  bool _checking = false;
  bool _snoozed = false;

  bool get available => release != null && release!.build > installedBuild;
  bool get required => release != null && installedBuild > 0 && installedBuild < release!.minBuild;
  bool get showBanner => available && !required && !_snoozed;
  String get installedLabel => installedVersion.isEmpty ? '' : 'v$installedVersion ($installedBuild)';

  Future<String?> _urlFor(String path) async {
    if (kReleaseBucketIsPrivate) {
      if (Supabase.instance.client.auth.currentSession == null) return null;
      return Supabase.instance.client.storage.from(kReleaseBucket).createSignedUrl(path, 3600);
    }
    return '${AppConfig.supabaseUrl}/storage/v1/object/public/$kReleaseBucket/$path';
  }

  Future<void> start() async {
    if (_timer != null || kIsWeb) return;
    try {
      final info = await PackageInfo.fromPlatform();
      installedVersion = info.version;
      installedBuild = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {}
    notifyListeners();
    await check();
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => check());
  }

  Future<void> check() async {
    if (kIsWeb || _checking || stage == UpdateStage.downloading || stage == UpdateStage.installing) return;
    _checking = true;
    try {
      final base = await _urlFor('manifest.json');
      if (base == null) return;
      final uri = Uri.parse(base);
      final res = await http
          .get(uri.replace(queryParameters: {...uri.queryParameters, 't': '${DateTime.now().millisecondsSinceEpoch}'}))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body);
      final next = AppRelease.fromJson(body is Map ? body['android'] : null);
      if (next == null) return;
      release = next;
      notifyListeners();
    } catch (_) {
      // Offline or signed out: keep whatever was known.
    } finally {
      _checking = false;
    }
  }

  void snooze() {
    _snoozed = true;
    notifyListeners();
  }

  Future<void> install() async {
    final r = release;
    if (r == null || stage == UpdateStage.downloading || stage == UpdateStage.installing) return;
    error = null;
    stage = UpdateStage.downloading;
    progress = 0;
    notifyListeners();
    try {
      final url = await _urlFor(r.path);
      if (url == null) throw Exception('Sign in again, then retry the update.');
      final done = Completer<void>();
      final sub = OtaUpdate().execute(url, destinationFilename: 'hyperpik-${r.version}-b${r.build}.apk', sha256checksum: r.sha256).listen((event) {
        switch (event.status) {
          case OtaStatus.DOWNLOADING:
            progress = ((double.tryParse(event.value ?? '') ?? 0) / 100).clamp(0.0, 1.0);
            stage = UpdateStage.downloading;
          case OtaStatus.INSTALLING:
            stage = UpdateStage.installing;
          case OtaStatus.INSTALLATION_DONE:
            if (!done.isCompleted) done.complete();
          case OtaStatus.CHECKSUM_ERROR:
            if (!done.isCompleted) done.completeError(Exception('The downloaded update did not match what was published, so it was not installed.'));
          case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
            if (!done.isCompleted) done.completeError(Exception('Allow $kAppLabel to install apps in the phone settings that just opened, then tap Update now again.'));
          case OtaStatus.CANCELED:
            if (!done.isCompleted) done.completeError(Exception('The update was cancelled.'));
          case OtaStatus.DOWNLOAD_ERROR:
          case OtaStatus.INTERNAL_ERROR:
          case OtaStatus.INSTALLATION_ERROR:
          case OtaStatus.ALREADY_RUNNING_ERROR:
            if (!done.isCompleted) done.completeError(Exception('The update could not be downloaded or installed (${event.value ?? event.status.name}). Please try again.'));
        }
        notifyListeners();
      }, onError: (Object e) {
        if (!done.isCompleted) done.completeError(Exception('The update could not be downloaded. Check the connection and try again.'));
      }, onDone: () {
        if (!done.isCompleted) done.complete();
      });
      try {
        await done.future;
        stage = UpdateStage.idle;
        notifyListeners();
      } finally {
        await sub.cancel();
      }
    } catch (e) {
      stage = UpdateStage.failed;
      error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }
}

/// Wrap the app's content with this (MaterialApp.builder): an optional update shows as a strip on top; a required one
/// replaces the app until the person updates.
class UpdateGate extends StatelessWidget {
  const UpdateGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final u = AppUpdate.instance;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final r = u.release;
        final busy = u.stage == UpdateStage.downloading || u.stage == UpdateStage.installing;
        final cs = Theme.of(context).colorScheme;
        if (u.required && r != null) {
          return Material(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.system_update_alt_rounded, size: 48, color: cs.primary),
                  const SizedBox(height: 16),
                  Text('Please update the app', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('This version is no longer supported. Update to version ${r.version} to keep using $kAppLabel.', textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  if (busy)
                    LinearProgressIndicator(value: u.progress > 0 ? u.progress : null)
                  else
                    FilledButton.icon(
                      onPressed: u.install,
                      icon: const Icon(Icons.download_rounded),
                      label: Text(u.stage == UpdateStage.failed ? 'Try again' : 'Update now'),
                    ),
                  if (u.error != null)
                    Padding(padding: const EdgeInsets.only(top: 12), child: Text(u.error!, textAlign: TextAlign.center, style: TextStyle(color: cs.error))),
                ]),
              ),
            ),
          );
        }
        final show = r != null && (u.showBanner || u.stage != UpdateStage.idle);
        return Column(children: [
          if (show)
            Material(
              color: cs.primaryContainer,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(children: [
                    Icon(Icons.system_update_alt_rounded, size: 18, color: cs.onPrimaryContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          u.stage == UpdateStage.installing
                              ? 'Installing the update. The app will restart.'
                              : u.stage == UpdateStage.downloading
                                  ? 'Downloading version ${r.version}… ${(u.progress * 100).clamp(0, 100).toStringAsFixed(0)}%'
                                  : 'Version ${r.version} is available.',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onPrimaryContainer),
                        ),
                        if (u.stage == UpdateStage.failed && u.error != null) Text(u.error!, style: TextStyle(fontSize: 12, color: cs.error)),
                        if (u.stage == UpdateStage.downloading)
                          Padding(padding: const EdgeInsets.only(top: 6), child: LinearProgressIndicator(value: u.progress > 0 ? u.progress : null, minHeight: 4)),
                      ]),
                    ),
                    if (!busy) ...[
                      TextButton(onPressed: u.snooze, child: const Text('Later')),
                      FilledButton(onPressed: u.install, child: Text(u.stage == UpdateStage.failed ? 'Try again' : 'Update now')),
                    ],
                  ]),
                ),
              ),
            ),
          Expanded(child: child),
        ]);
      },
    );
  }
}
