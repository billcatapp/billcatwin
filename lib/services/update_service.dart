import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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

  /// The updater script leaves %TEMP%\billcat_update.log behind ONLY when a
  /// previous "Install Update" failed to apply (it deletes the log on
  /// success). Returns the failure reason and removes the log so the message
  /// surfaces once — without this, a failed update silently relaunches the
  /// old version and the user just sees "same version" with no explanation.
  static Future<String?> consumeFailedUpdateLog() async {
    try {
      final tmp = Platform.environment['TEMP'] ?? Platform.environment['TMP'];
      if (tmp == null) return null;
      final f = File('$tmp\\billcat_update.log');
      if (!await f.exists()) return null;
      // Add-Content writes the ANSI code page, so an accented user name in
      // the log is not valid UTF-8; decode leniently so the message still shows.
      final content = utf8.decode(await f.readAsBytes(), allowMalformed: true);
      await f.delete();
      // The log is gone after this; remember the failure past a restart, but
      // only if this version started the failed update. A log left by an
      // older version (e.g. read by the version the user then installed by
      // hand) must not mark this one as failed.
      if (content.contains('from version ${await currentVersion()},')) {
        await markUpdateFailed();
      }
      // Last "failed" line carries the actual copy error, if any.
      final failLines =
          content.split('\n').where((l) => l.contains('failed')).toList();
      return failLines.isNotEmpty ? failLines.last.trim() : content.trim();
    } catch (_) {
      return null;
    }
  }

  static Future<File> _failedMarker() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}update_failed.txt');
  }

  /// Records that an in-place update failed on the version running now, so
  /// the banner keeps offering the installer instead of retrying (see
  /// [previousUpdateFailed]).
  static Future<void> markUpdateFailed() async {
    try {
      await (await _failedMarker()).writeAsString(await currentVersion());
    } catch (_) {}
  }

  /// True while the version whose in-place update failed is still installed.
  /// Once a different version runs (e.g. after using the installer) the
  /// marker is removed and normal updates resume.
  static Future<bool> previousUpdateFailed() async {
    try {
      final marker = await _failedMarker();
      if (!await marker.exists()) return false;
      if ((await marker.readAsString()).trim() == await currentVersion()) {
        return true;
      }
      await marker.delete();
    } catch (_) {}
    return false;
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
    // Installs that live under a read-only location (e.g. a leftover MSIX
    // install under WindowsApps) can never succeed the in-place file copy
    // below. Derive the GitHub release page so the fallback can send the
    // user to grab the installer manually instead of failing silently.
    final releasePageUrl = releasePageFor(url);

    final tmpDir = await Directory.systemTemp.createTemp('billcat_update_');
    final zipPath = '${tmpDir.path}\\update.zip';

    onProgress(0.05);

    // Download using Dart's HttpClient (no curl dependency on Windows).
    // Timeouts so a stalled connection ends in an error instead of a progress
    // bar that never moves.
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw UpdateCheckError('Download failed: HTTP ${response.statusCode}');
      }

      final totalBytes =
          int.tryParse(response.headers.value('content-length') ?? '') ?? 0;
      int received = 0;

      final sink = File(zipPath).openWrite();
      try {
        await for (final chunk
            in response.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          received += chunk.length;
          if (totalBytes > 0) {
            onProgress(0.05 + (received / totalBytes) * 0.75);
          }
        }
      } on TimeoutException {
        throw const UpdateCheckError(
          'Update download stopped responding. Check your internet connection and try again.',
        );
      } finally {
        await sink.close();
      }
      if (totalBytes > 0 &&
          received != totalBytes &&
          response.compressionState !=
              HttpClientResponseCompressionState.decompressed) {
        throw const UpdateCheckError(
          'Update download was interrupted. Check your internet connection and try again.',
        );
      }
    } on TimeoutException {
      throw const UpdateCheckError(
        'Could not reach the update server. Check your internet connection and try again.',
      );
    } finally {
      client.close();
    }

    onProgress(0.82);

    // Extract using PowerShell's built-in Expand-Archive. Expand-Archive
    // reports a bad zip as a non-terminating error and still exits 0, so make
    // errors terminating. Paths are single-quoted so a '$' or backtick in the
    // Windows user name is not expanded by PowerShell.
    final extractDir = '${tmpDir.path}\\extracted';
    await Directory(extractDir).create();
    final extract = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      "\$ErrorActionPreference = 'Stop'; "
          'Expand-Archive -LiteralPath ${_psq(zipPath)} '
          '-DestinationPath ${_psq(extractDir)} -Force',
    ]);
    // A Wi-Fi login page, proxy, or antivirus can hand back something that is
    // not the zip (extract fails), or a zip with files stripped out (no
    // billcat.exe). Retrying the same download won't help, and the raw
    // PowerShell error is unreadable, so say what to do instead.
    if (extract.exitCode != 0 ||
        !File('$extractDir\\billcat.exe').existsSync()) {
      throw const UpdatePackageError(
        'The update download was damaged or blocked (Wi-Fi login page, proxy '
        'or antivirus). Use "Download Installer" on the update banner.',
      );
    }

    onProgress(0.92);

    final execPath = Platform.resolvedExecutable;
    final appDir = File(execPath).parent.path;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final scriptPath = '${Directory.systemTemp.path}\\billcat_updater_$ts.ps1';
    // Written into the log so a failure is only remembered by the version
    // that started this update (see consumeFailedUpdateLog).
    final fromVersion = await currentVersion();

    // PowerShell script: wait for the app process to exit, copy new files, relaunch.
    // Windows keeps the outgoing exe's image memory-mapped for a short window after
    // the process disappears from Get-Process, so the first Copy-Item attempt can
    // fail with "a user-mapped section open" even though the process is gone.
    // Retry with backoff instead of relaunching whatever happens to be on disk.
    //
    // The file starts with a UTF-8 BOM: Windows PowerShell 5.1 reads a .ps1
    // without one as the ANSI code page, which garbles a Tamil, Hindi or
    // accented user name in the paths below. Paths are single-quoted (_psq)
    // so a '$' or backtick in them is not expanded.
    await File(scriptPath).writeAsString(
      // Written as a char code, not an invisible literal, so it can't be
      // stripped by accident. Must stay first.
      '${String.fromCharCode(0xFEFF)}'
      r'$log = "$env:TEMP\billcat_update.log"' '\n'
      'Add-Content \$log "[\$(Get-Date)] Updater started from version $fromVersion, waiting for BillCat..."\n'
      r'$maxWait = 20; $waited = 0' '\n'
      r'while ((Get-Process -Name "billcat" -ErrorAction SilentlyContinue) -and ($waited -lt $maxWait)) {' '\n'
      r'    Start-Sleep -Milliseconds 500; $waited += 0.5' '\n'
      r'}' '\n'
      // A leftover second instance keeps billcat.exe locked, which would make
      // every copy attempt fail and silently relaunch the old version. The
      // user asked for the update — stop the straggler.
      r'if (Get-Process -Name "billcat" -ErrorAction SilentlyContinue) {' '\n'
      r'    Add-Content $log "[$(Get-Date)] BillCat still running after $maxWait s - stopping it..."' '\n'
      r'    Stop-Process -Name "billcat" -Force -ErrorAction SilentlyContinue' '\n'
      r'    Start-Sleep -Milliseconds 1000' '\n'
      r'}' '\n'
      r'Add-Content $log "[$(Get-Date)] Copying files..."' '\n'
      r'$copyAttempts = 0; $copyOk = $false' '\n'
      r'while (-not $copyOk -and $copyAttempts -lt 10) {' '\n'
      '    try {\n'
      '        Copy-Item -Path ${_psq('$extractDir\\*')} -Destination ${_psq(appDir)} -Recurse -Force -ErrorAction Stop\n'
      r'        $copyOk = $true' '\n'
      '    } catch {\n'
      r'        $copyAttempts++' '\n'
      r'        Add-Content $log "[$(Get-Date)] Copy attempt $copyAttempts failed: $($_.Exception.Message)"' '\n'
      r'        Start-Sleep -Milliseconds 500' '\n'
      '    }\n'
      r'}' '\n'
      r'if ($copyOk) {' '\n'
      r'    Add-Content $log "[$(Get-Date)] Copy succeeded. Launching updated app..."' '\n'
      r'} else {' '\n'
      r'    Add-Content $log "[$(Get-Date)] Copy failed after $copyAttempts attempts (BillCat files are locked or the install folder is read-only). Opening manual download page..."' '\n'
      '    Start-Process ${_psq(releasePageUrl)}\n'
      r'}' '\n'
      'Start-Process ${_psq(execPath)}\n'
      r'if ($copyOk) {' '\n'
      r'    Remove-Item -Path "$env:TEMP\billcat_update.log" -Force -ErrorAction SilentlyContinue' '\n'
      r'}' '\n'
      r'Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue' '\n',
    );

    onProgress(1.0);

    // Launch the script via `cmd /c start`, not a direct detached Process.start:
    // Process.run would block here until the script exits, but the script's
    // first step waits for *this* process to exit first — a deadlock only
    // broken by the wait-loop's timeout, by which point this process still
    // hasn't actually exited. A direct `Process.start(mode: detached)` avoids
    // that deadlock but on Windows the child can still be torn down along
    // with this process's tree once exit() runs. `cmd /c start` goes through
    // ShellExecute, which reliably survives the parent's exit.
    // The script path is passed in an environment variable, not on the cmd
    // command line: cmd treats '&' or '^' in a user name (e.g. "R&S") as
    // syntax, and the script would never start.
    await Process.start(
      'cmd',
      ['/c', 'start', '""', '/min', 'powershell', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-Command', r'& $env:BC_UPDATER_SCRIPT'],
      environment: {'BC_UPDATER_SCRIPT': scriptPath},
      mode: ProcessStartMode.detached,
    );
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

  /// PowerShell single-quoted string literal: nothing inside is expanded.
  static String _psq(String s) => "'${s.replaceAll("'", "''")}'";

  /// GitHub release page for a release asset URL, where the installer can be
  /// downloaded by hand. Returns [url] unchanged if it is not a GitHub asset.
  static String releasePageFor(String url) {
    final m =
        RegExp(r'^(https://github\.com/[^/]+/[^/]+)/releases/download/([^/]+)/')
            .firstMatch(url);
    return m == null ? url : '${m.group(1)}/releases/tag/${m.group(2)}';
  }
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

/// The download finished but the package is unusable (blocked, replaced or
/// corrupt). Retrying the same download will not help; use the installer.
class UpdatePackageError extends UpdateCheckError {
  const UpdatePackageError(super.message);
}
