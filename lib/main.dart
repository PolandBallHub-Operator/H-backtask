import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HBacktaskApp());
}

class HBacktaskApp extends StatelessWidget {
  const HBacktaskApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'H-backtask',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4),
        brightness: Brightness.dark,
      ),
    ),
    themeMode: ThemeMode.system,
    home: const HomePage(),
  );
}

enum Bucket {
  active(10, 'ACTIVE', 'active'),
  workingSet(20, 'WORKING_SET', 'working_set'),
  frequent(30, 'FREQUENT', 'frequent'),
  rare(40, 'RARE', 'rare'),
  never(50, 'NEVER', 'never');

  const Bucket(this.value, this.label, this.arg);
  final int value;
  final String label;
  final String arg;
  static Bucket? parse(String text) {
    final lower = text.toLowerCase();
    final match = RegExp(r'\b(10|20|30|40|50)\b').firstMatch(lower);
    if (match != null) {
      return Bucket.values
          .where((b) => b.value == int.parse(match.group(1)!))
          .firstOrNull;
    }
    return Bucket.values
        .where(
          (b) => lower.contains(b.arg) || lower.contains(b.label.toLowerCase()),
        )
        .firstOrNull;
  }
}

class Device {
  const Device(this.serial, this.state, this.details);
  final String serial, state, details;
}

class AppPackage {
  AppPackage(this.name);
  final String name;
  Bucket? bucket;
  bool get excluded =>
      name.toLowerCase() == 'android' ||
      name.toLowerCase() == 'com.android.systemui' ||
      name.toLowerCase().contains('framework');
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Device? device;
  List<AppPackage> apps = [];
  final Set<String> selected = {};
  final search = TextEditingController();
  bool busy = false, revealSystem = false;
  String status = 'AndroidOS / FireOSを接続してください';
  String? error;
  double? progress;
  int versionTaps = 0;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<ProcessResult> adb(List<String> args) => Process.run(
    'adb',
    args,
    runInShell: false,
    stdoutEncoding: SystemEncoding(),
    stderrEncoding: SystemEncoding(),
  ).timeout(const Duration(seconds: 35));

  String resultError(ProcessResult r) {
    final message = '${r.stderr}\n${r.stdout}'.trim();
    return message.isEmpty ? 'ADB終了コード ${r.exitCode}' : message;
  }

  String friendly(Object e) {
    final s = e.toString().replaceFirst('Exception: ', '');
    if (e is ProcessException || s.toLowerCase().contains('no such file')) {
      return 'adb が見つかりません。Android Platform Toolsをインストールし、adb.exeにPATHを通してください。';
    }
    if (s.contains('TimeoutException')) {
      return 'ADBが応答しません。USB接続を確認して再試行してください。';
    }
    return s;
  }

  Future<void> connect() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      status = 'ADBデバイスを検索しています…';
    });
    try {
      final r = await adb(['devices', '-l']);
      if (r.exitCode != 0) throw Exception(resultError(r));
      final devices = <Device>[];
      for (final line in r.stdout.toString().split(RegExp(r'\r?\n'))) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2 && parts.first != '*' && parts.first != 'List') {
          devices.add(Device(parts.first, parts[1], parts.skip(2).join(' ')));
        }
      }
      final ready = devices.where((d) => d.state == 'device').toList();
      if (ready.isEmpty) {
        throw Exception(
          devices.any((d) => d.state == 'unauthorized')
              ? '端末側でUSBデバッグを許可してください。'
              : 'デバイスが見つかりません。USBデバッグとADB接続を確認してください。',
        );
      }
      final chosen = ready.length == 1
          ? ready.first
          : await chooseDevice(ready);
      if (chosen == null || !mounted) return;
      setState(() {
        device = chosen;
        status = '${chosen.serial} 接続済み。アプリ一覧を取得しています…';
      });
      await loadApps();
    } catch (e) {
      if (mounted) {
        setState(() {
          device = null;
          error = friendly(e);
          status = '接続できませんでした';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Device?> chooseDevice(List<Device> devices) => showDialog<Device>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('接続する端末を選択'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: devices
              .map(
                (d) => ListTile(
                  leading: const Icon(Icons.phone_android),
                  title: Text(d.serial),
                  subtitle: Text(d.details),
                  onTap: () => Navigator.pop(context, d),
                ),
              )
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
      ],
    ),
  );

  Future<void> loadApps() async {
    final d = device;
    if (d == null) return;
    setState(() {
      busy = true;
      error = null;
      progress = null;
      status = 'インストール済みアプリを取得しています…';
      selected.clear();
    });
    try {
      final r = await adb(['-s', d.serial, 'shell', 'pm', 'list', 'packages']);
      if (r.exitCode != 0) throw Exception(resultError(r));
      final names =
          r.stdout
              .toString()
              .split(RegExp(r'\r?\n'))
              .map((s) => s.trim())
              .where((s) => s.startsWith('package:'))
              .map((s) => s.substring(8).trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      if (names.isEmpty) throw Exception('端末からアプリ一覧を取得できませんでした。');
      final list = names.map(AppPackage.new).toList();
      setState(() {
        apps = list;
        progress = 0;
        status = '待機バケットを確認しています…';
      });
      var done = 0;
      const concurrency = 6;
      for (var i = 0; i < list.length; i += concurrency) {
        await Future.wait(
          list.skip(i).take(concurrency).map((app) async {
            try {
              final q = await adb([
                '-s',
                d.serial,
                'shell',
                'am',
                'get-standby-bucket',
                app.name,
              ]);
              if (q.exitCode == 0) {
                app.bucket = Bucket.parse(q.stdout.toString());
              }
            } catch (_) {
              /* unavailable stays unknown */
            }
            done++;
            if (mounted) {
              setState(() {
                progress = done / list.length;
                status = 'バケット確認中 $done / ${list.length}';
              });
            }
          }),
        );
      }
      if (mounted) {
        setState(() {
          status = '${list.length} 件のアプリを読み込みました';
          progress = 1;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = friendly(e);
          status = 'アプリ一覧を取得できませんでした';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> apply(List<AppPackage> targets, Bucket bucket) async {
    final d = device;
    if (d == null || targets.isEmpty || busy) return;
    setState(() {
      busy = true;
      progress = 0;
      error = null;
      status = '${bucket.label} を適用しています…';
    });
    final failures = <String>[];
    var done = 0;
    for (final app in targets) {
      try {
        final r = await adb([
          '-s',
          d.serial,
          'shell',
          'am',
          'set-standby-bucket',
          app.name,
          bucket.arg,
        ]);
        if (r.exitCode == 0) {
          app.bucket = bucket;
        } else {
          failures.add('${app.name}: ${resultError(r)}');
        }
      } catch (e) {
        failures.add('${app.name}: $e');
      }
      done++;
      if (mounted) {
        setState(() {
          progress = done / targets.length;
          status = '適用中 $done / ${targets.length}';
        });
      }
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      progress = 1;
      status = failures.isEmpty
          ? '${targets.length} 件に ${bucket.label} を適用しました'
          : '${targets.length - failures.length} 件成功、${failures.length} 件失敗';
      selected.removeAll(targets.map((e) => e.name));
      if (failures.isNotEmpty) error = failures.take(5).join('\n');
    });
    toast(
      failures.isEmpty
          ? '${targets.length} 件に ${bucket.label} (${bucket.value}) を適用しました'
          : '一部のアプリに適用できませんでした。状態表示をご確認ください。',
    );
  }

  Future<void> pickBucket(
    List<AppPackage> targets, {
    String title = '待機バケットを選択',
  }) async {
    final bucket = await showModalBottomSheet<Bucket>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final b in Bucket.values)
                ListTile(
                  leading: BucketIcon(bucket: b),
                  title: Text(b.label),
                  subtitle: Text('値 ${b.value}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, b),
                ),
            ],
          ),
        ),
      ),
    );
    if (bucket != null) await apply(targets, bucket);
  }

  Future<void> backup() async {
    if (apps.isEmpty || device == null) {
      toast('先にAndroidOS / FireOSを接続してください');
      return;
    }
    try {
      final home =
          Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home == null || home.isEmpty) throw Exception('ユーザーフォルダーがありません');
      final dir = Directory('$home${Platform.pathSeparator}Downloads');
      if (!await dir.exists()) await dir.create(recursive: true);
      final now = DateTime.now();
      String p(int n) => n.toString().padLeft(2, '0');
      final name =
          'H-backtask_backup_${now.year}${p(now.month)}${p(now.day)}_${p(now.hour)}${p(now.minute)}${p(now.second)}.json';
      final payload = {
        'format': 'H-backtask standby bucket backup',
        'schemaVersion': 1,
        'createdAt': now.toIso8601String(),
        'device': {'serial': device!.serial, 'details': device!.details},
        'bucketLegend': {for (final b in Bucket.values) '${b.value}': b.label},
        'packages': [
          for (final a in apps)
            {
              'packageName': a.name,
              'bucketValue': a.bucket?.value,
              'bucketName': a.bucket?.label ?? 'UNKNOWN',
              'hiddenByDefault': a.excluded,
            },
        ],
      };
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
        flush: true,
      );
      if (mounted) toast('バックアップを保存しました: ${file.path}');
    } catch (e) {
      if (mounted) toast('バックアップに失敗しました: $e');
    }
  }

  Future<void> settings() async => showDialog<void>(
    context: context,
    builder: (dc) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        title: const Text('設定'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('現在の設定をバックアップ'),
                subtitle: const Text('アプリ一覧とバケットをDownloadsにJSON保存'),
                onTap: () {
                  Navigator.pop(dc);
                  backup();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('アプリバージョン'),
                subtitle: const Text('H-backtask 1.0.0'),
                onTap: () {
                  versionTaps++;
                  refresh(() {});
                  if (versionTaps >= 7) {
                    versionTaps = 0;
                    setState(() => revealSystem = !revealSystem);
                    Navigator.pop(dc);
                    toast(
                      revealSystem
                          ? 'システムアプリを表示しました。変更は慎重に行ってください。'
                          : '通常表示に戻しました',
                    );
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dc),
            child: const Text('閉じる'),
          ),
        ],
      ),
    ),
  );

  List<AppPackage> get visible {
    final q = search.text.trim().toLowerCase();
    return apps
        .where(
          (a) =>
              (revealSystem || !a.excluded) &&
              (q.isEmpty || a.name.toLowerCase().contains(q)),
        )
        .toList();
  }

  void toggleAll() {
    final list = visible;
    final all = list.isNotEmpty && list.every((a) => selected.contains(a.name));
    setState(() {
      if (all) {
        selected.removeAll(list.map((a) => a.name));
      } else {
        selected.addAll(list.map((a) => a.name));
      }
    });
  }

  void toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = visible;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 18, 10),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.battery_saver,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'H-backtask',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Android / FireOS standby bucket manager',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (device != null) ...[
                    Chip(
                      avatar: const Icon(Icons.usb, size: 18),
                      label: Text(device!.serial),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      tooltip: '再読み込み',
                      onPressed: busy ? null : loadApps,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                  IconButton(
                    tooltip: '設定',
                    onPressed: settings,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
            ),
            if (busy) LinearProgressIndicator(value: progress),
            Expanded(
              child: device == null ? welcome(theme) : content(theme, list),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              color: theme.colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  Icon(
                    error == null
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: 18,
                    color: error == null
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error ?? status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : (device == null ? connect : loadApps),
                    icon: Icon(device == null ? Icons.cable : Icons.refresh),
                    label: Text(device == null ? '接続' : '再読込'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget welcome(ThemeData t) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Card(
          color: t.colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.phone_android_rounded,
                  size: 64,
                  color: t.colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'AndroidOS / FireOSを接続してください',
                  textAlign: TextAlign.center,
                  style: t.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'USBデバッグを有効にして端末を接続します。\nADB経由で待機バケットを表示・変更します。',
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: busy ? null : connect,
                  icon: const Icon(Icons.cable),
                  label: const Text('ADBデバイスに接続'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: t.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      error!,
                      style: TextStyle(color: t.colorScheme.onErrorContainer),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Android Platform Tools（adb）をインストールし、PATHを設定してください。',
                  textAlign: TextAlign.center,
                  style: t.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget content(ThemeData t, List<AppPackage> list) {
    final all = list.isNotEmpty && list.every((a) => selected.contains(a.name));
    final hidden = apps.where((a) => a.excluded).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'アプリ一覧',
                  style: t.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text('${list.length} 件'),
              if (!revealSystem && hidden > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Chip(
                    avatar: const Icon(Icons.visibility_off_outlined, size: 16),
                    label: Text('システム $hidden 件を非表示'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SearchBar(
                  controller: search,
                  hintText: 'パッケージ名を検索',
                  leading: const Icon(Icons.search),
                  onChanged: (_) => setState(() {}),
                  constraints: const BoxConstraints(minHeight: 48),
                  trailing: [
                    if (search.text.isNotEmpty)
                      IconButton(
                        onPressed: () {
                          search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: busy || list.isEmpty ? null : toggleAll,
                icon: Icon(all ? Icons.deselect : Icons.select_all),
                label: Text(all ? '選択解除' : '表示中を選択'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: busy || selected.isEmpty
                    ? null
                    : () => pickBucket(
                        apps.where((a) => selected.contains(a.name)).toList(),
                        title: '選択した ${selected.length} 件に適用',
                      ),
                icon: const Icon(Icons.tune),
                label: Text(
                  '選択を適用${selected.isEmpty ? '' : ' (${selected.length})'}',
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<Bucket>(
                enabled: !busy && apps.isNotEmpty,
                onSelected: (b) => confirmAll(b),
                tooltip: 'システムアプリを除く全アプリに適用',
                itemBuilder: (_) => [
                  for (final b in Bucket.values)
                    PopupMenuItem(
                      value: b,
                      child: Text('${b.label} (${b.value})'),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: t.colorScheme.outline),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.all_inclusive, size: 18),
                      SizedBox(width: 6),
                      Text('全アプリに一括適用'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: apps.isEmpty
                ? (error == null
                      ? const Center(child: CircularProgressIndicator())
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_off_outlined, size: 44),
                              const SizedBox(height: 12),
                              const Text('アプリ一覧を取得できませんでした'),
                              const SizedBox(height: 12),
                              FilledButton.tonalIcon(
                                onPressed: busy ? null : loadApps,
                                icon: const Icon(Icons.refresh),
                                label: const Text('再試行'),
                              ),
                            ],
                          ),
                        ))
                : list.isEmpty
                ? const Center(child: Text('一致するアプリがありません'))
                : Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        Container(
                          color: t.colorScheme.surfaceContainerHighest
                              .withValues(alpha: .55),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 38),
                              Expanded(
                                child: Text(
                                  'パッケージ名',
                                  style: t.textTheme.labelLarge,
                                ),
                              ),
                              const SizedBox(
                                width: 210,
                                child: Text(
                                  '現在のバケット',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1, indent: 54),
                            itemBuilder: (context, i) => packageRow(t, list[i]),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          if (revealSystem)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: t.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'システムアプリ表示中：SystemUI / framework の変更は端末に影響する可能性があります。',
                      style: t.textTheme.bodySmall?.copyWith(
                        color: t.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget packageRow(ThemeData t, AppPackage a) {
    final isSelected = selected.contains(a.name);
    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: t.colorScheme.secondaryContainer.withValues(
        alpha: .35,
      ),
      leading: Checkbox(
        value: isSelected,
        onChanged: busy
            ? null
            : (v) => setState(
                () =>
                    v == true ? selected.add(a.name) : selected.remove(a.name),
              ),
      ),
      title: Text(
        a.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      subtitle: a.excluded ? const Text('システムパッケージ') : null,
      trailing: SizedBox(
        width: 220,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: BucketPill(bucket: a.bucket),
              ),
            ),
            IconButton(
              tooltip: 'バケットを変更',
              onPressed: busy ? null : () => pickBucket([a], title: a.name),
              icon: const Icon(Icons.settings_outlined, size: 20),
            ),
          ],
        ),
      ),
      onTap: busy
          ? null
          : () => setState(
              () => isSelected ? selected.remove(a.name) : selected.add(a.name),
            ),
    );
  }

  Future<void> confirmAll(Bucket b) async {
    final targets = apps.where((a) => !a.excluded).toList();
    if (targets.isEmpty) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('全アプリに一括適用'),
        content: Text(
          'SystemUI / frameworkを除く ${targets.length} 件すべてに ${b.label} (${b.value}) を適用します。よろしいですか？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('適用'),
          ),
        ],
      ),
    );
    if (yes == true) await apply(targets, b);
  }
}

class BucketIcon extends StatelessWidget {
  const BucketIcon({super.key, required this.bucket});
  final Bucket bucket;
  @override
  Widget build(BuildContext context) {
    final icon = switch (bucket) {
      Bucket.active => Icons.bolt,
      Bucket.workingSet => Icons.work_history_outlined,
      Bucket.frequent => Icons.autorenew,
      Bucket.rare => Icons.hourglass_bottom,
      Bucket.never => Icons.block_outlined,
    };
    return Icon(icon, color: Theme.of(context).colorScheme.primary);
  }
}

class BucketPill extends StatelessWidget {
  const BucketPill({super.key, required this.bucket});
  final Bucket? bucket;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (bucket == null) {
      return Chip(
        label: const Text('未取得'),
        visualDensity: VisualDensity.compact,
        backgroundColor: t.colorScheme.surfaceContainerHighest,
      );
    }
    return Chip(
      avatar: BucketIcon(bucket: bucket!),
      label: Text(
        '${bucket!.label} (${bucket!.value})',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      visualDensity: VisualDensity.compact,
      backgroundColor: t.colorScheme.secondaryContainer,
      labelStyle: TextStyle(
        color: t.colorScheme.onSecondaryContainer,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
