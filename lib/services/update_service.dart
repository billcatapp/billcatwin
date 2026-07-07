import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';

// version.json shape (host at feedUrl, update "version" to trigger update banner):
// {
//   "version": "1.1.0",
//   "download_url": "https://example.com/BillCat-1.1.0.zip",
//   "release_notes": "What's new",
//   "mandatory": false
// }
class UpdateService {
  // Windows-specific feed: the Mac app reads version.json in this bucket and
  // both platforms consume the same download_url field, so each platform
  // needs its own feed file.
  static const String feedUrl =
      'https://xawpxbhglzhaibmcpwho.supabase.co/storage/v1/object/public/billcat-updates/version-windows.json';

  /// Returns an [UpdateInfo] if a newer version exists, null otherwise.
  /// Throws [UpdateCheckError] with a human-readable message on failure.
  static Future<UpdateInfo?> checkForUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final current = info.version;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(feedUrl));
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw UpdateCheckError('Server returned ${res.statusCode}');
      }
      final body = await res.transform(utf8.decoder).join();
      client.close();

      final data = jsonDecode(body) as Map<String, dynamic>;
      final latest = data['version'] as String;

      if (_isNewer(latest, current)) {
        return UpdateInfo(
          version: latest,
          downloadUrl: data['download_url'] as String,
          releaseNotes: data['release_notes'] as String? ?? '',
          mandatory: data['mandatory'] as bool? ?? false,
        );
      }
      return null;
    } on UpdateCheckError {
      rethrow;
    } catch (e) {
      client.close();
      throw UpdateCheckError('Could not check for updates. Check your internet connection.');
    }
  }

  static bool _isNewer(String latest, String current) {
    String core(String v) => v.split('-').first;
    List<int> parse(String v) =>
        core(v).split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final l = parse(latest);
    final c = parse(current);
    for (int i = 0; i < 3; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    final latestIsPre = latest.contains('-');
    final currentIsPre = current.contains('-');
    if (!latestIsPre && currentIsPre) return true;
    return false;
  }

  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// Downloads the zip, extracts it, replaces the running app, and relaunches.
  /// [onProgress] is called with 0.0–1.0. The app exits at 1.0 and relaunches.
  static Future<void> installUpdate(
    String url,
    void Function(double progress) onProgress,
  ) async {
    if (Platform.isWindows) {
      await _installUpdateWindows(url, onProgress);
    } else {
      await _installUpdateMacOS(url, onProgress);
    }
  }

  // ── Windows updater ────────────────────────────────────────────────────────
  static Future<void> _installUpdateWindows(
    String url,
    void Function(double progress) onProgress,
  ) async {
    final tmpDir = await Directory.systemTemp.createTemp('billcat_update_');
    final zipPath = '${tmpDir.path}\\update.zip';

    onProgress(0.05);

    // Download using Dart's HttpClient (no curl dependency on Windows)
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw UpdateCheckError('Download failed: HTTP ${response.statusCode}');
      }

      final totalBytes =
          int.tryParse(response.headers.value('content-length') ?? '') ?? 0;
      int received = 0;

      final sink = File(zipPath).openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (totalBytes > 0) {
          onProgress(0.05 + (received / totalBytes) * 0.75);
        }
      }
      await sink.close();
    } finally {
      client.close();
    }

    onProgress(0.82);

    // Extract using PowerShell's built-in Expand-Archive
    final extractDir = '${tmpDir.path}\\extracted';
    await Directory(extractDir).create();
    final extract = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      'Expand-Archive -LiteralPath "$zipPath" -DestinationPath "$extractDir" -Force',
    ]);
    if (extract.exitCode != 0) {
      throw UpdateCheckError('Failed to extract update: ${extract.stderr}');
    }

    onProgress(0.92);

    final execPath = Platform.resolvedExecutable;
    final appDir = File(execPath).parent.path;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final scriptPath = '${Directory.systemTemp.path}\\billcat_updater_$ts.ps1';

    // PowerShell script: wait for the app process to exit, copy new files, relaunch
    await File(scriptPath).writeAsString(
      r'$log = "$env:TEMP\billcat_update.log"' '\n'
      r'Add-Content $log "[$(Get-Date)] Updater started, waiting for BillCat..."' '\n'
      r'$maxWait = 20; $waited = 0' '\n'
      r'while ((Get-Process -Name "billcat" -ErrorAction SilentlyContinue) -and ($waited -lt $maxWait)) {' '\n'
      r'    Start-Sleep -Milliseconds 500; $waited += 0.5' '\n'
      r'}' '\n'
      r'Add-Content $log "[$(Get-Date)] Copying files..."' '\n'
      'Copy-Item -Path "$extractDir\\*" -Destination "$appDir" -Recurse -Force\n'
      r'Add-Content $log "[$(Get-Date)] Launching updated app..."' '\n'
      'Start-Process "$execPath"\n'
      r'Remove-Item -Path "$env:TEMP\billcat_update.log" -Force -ErrorAction SilentlyContinue' '\n'
      r'Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue' '\n',
    );

    onProgress(1.0);

    // Launch the script in a hidden window, detached from this process
    await Process.run('powershell', [
      '-WindowStyle', 'Hidden',
      '-ExecutionPolicy', 'Bypass',
      '-File', scriptPath,
    ]);
    await Future.delayed(const Duration(milliseconds: 500));
    exit(0);
  }

  // ── macOS updater (original logic) ────────────────────────────────────────
  static Future<void> _installUpdateMacOS(
    String url,
    void Function(double progress) onProgress,
  ) async {
    final tmpDir = await Directory.systemTemp.createTemp('billcat_update_');
    final zipPath = '${tmpDir.path}/update.zip';

    onProgress(0.05);

    int totalBytes = 0;
    try {
      final headResult = await Process.run('curl', ['-sI', '-L', url]);
      final headOutput = headResult.stdout as String;
      final match = RegExp(r'content-length:\s*(\d+)', caseSensitive: false)
          .allMatches(headOutput)
          .lastOrNull;
      if (match != null) totalBytes = int.tryParse(match.group(1)!) ?? 0;
    } catch (_) {}

    bool downloadComplete = false;
    Timer? pollTimer;
    if (totalBytes > 0) {
      pollTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (downloadComplete) return;
        try {
          final size = File(zipPath).statSync().size;
          if (size > 0) onProgress(0.05 + (size / totalBytes) * 0.80);
        } catch (_) {}
      });
    }

    final dlResult = await Process.run(
        'curl', ['-L', '--silent', '--show-error', '-o', zipPath, url]);
    downloadComplete = true;
    pollTimer?.cancel();

    if (dlResult.exitCode != 0) {
      throw UpdateCheckError('Download failed. Check your connection.');
    }

    onProgress(0.88);
    final extractDir = '${tmpDir.path}/extracted';
    await Directory(extractDir).create();
    final unzip =
        await Process.run('unzip', ['-q', zipPath, '-d', extractDir]);
    if (unzip.exitCode != 0) throw UpdateCheckError('Failed to extract update.');

    final entries = Directory(extractDir).listSync();
    final appEntry = entries
        .whereType<Directory>()
        .where((d) => d.path.endsWith('.app'))
        .toList();
    if (appEntry.isEmpty) throw UpdateCheckError('No .app found in update package.');
    final newAppPath = appEntry.first.path;

    onProgress(0.95);
    final execPath = Platform.resolvedExecutable;
    final appPath = File(execPath).parent.parent.parent.path;

    final scriptPath =
        '${Directory.systemTemp.path}/billcat_updater_${DateTime.now().millisecondsSinceEpoch}.sh';
    final logPath = '${Directory.systemTemp.path}/billcat_update.log';
    await File(scriptPath).writeAsString(
      '#!/bin/bash\n'
      'exec >>${_esc(logPath)} 2>&1\n'
      'echo "[\$(date)] updater started, waiting for BillCat to quit..."\n'
      'for i in \$(seq 1 40); do sleep 0.5; pgrep -xq "BillCat" || break; done\n'
      'echo "[\$(date)] BillCat exited, replacing app..."\n'
      'rm -rf ${_esc(appPath)}\n'
      'cp -R ${_esc(newAppPath)} ${_esc(appPath)}\n'
      'xattr -cr ${_esc(appPath)}\n'
      'echo "[\$(date)] launching new app..."\n'
      'open ${_esc(appPath)}\n'
      'echo "[\$(date)] done"\n'
      'rm -rf ${_esc(tmpDir.path)}\n'
      'rm -- "\$0"\n',
    );
    await Process.run('chmod', ['+x', scriptPath]);

    onProgress(1.0);
    await Process.run(
        'bash', ['-c', 'nohup bash ${_esc(scriptPath)} >/dev/null 2>&1 &']);
    await Future.delayed(const Duration(milliseconds: 500));
    exit(0);
  }

  static String _esc(String path) => "'${path.replaceAll("'", "'\\''")}'";
}

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final bool mandatory;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.mandatory,
  });
}

class UpdateCheckError implements Exception {
  final String message;
  const UpdateCheckError(this.message);
  @override
  String toString() => message;
}
