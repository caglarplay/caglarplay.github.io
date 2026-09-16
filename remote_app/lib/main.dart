import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'certificate_manager.dart';
import 'tv_discovery.dart';
import 'tv_remote_client.dart';
import 'tv_security.dart';

void main() => runApp(const KumandaApp());

class KumandaApp extends StatelessWidget {
  const KumandaApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF7C5CFC);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kumanda',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0B0C10),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF17191F),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: seed.withOpacity(.7))),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const ir = MethodChannel('kumanda/ir');
  static const storage = FlutterSecureStorage();
  static const lastTvKey = 'last_tv_ip';

  final cert = CertificateManager();
  final discovery = TVDiscoveryService();
  late final TVSecurityManager security;
  late final TVRemoteClient remote;
  StreamSubscription? discoverySub;
  Timer? reconnectTimer;

  List<BonsoirService> tvs = [];
  bool scanning = true;
  bool tvConnected = false;
  bool irOk = false;
  bool busy = false;
  bool reconnecting = false;
  bool keepConnected = true;
  String status = 'TV aranıyor…';
  String? tvIp;

  int tab = 0;
  int tvMode = 0;
  int temp = 24;
  int fan = 0;
  int mode = 1;
  bool acPower = false;
  bool swing = false;

  final ipCtrl = TextEditingController();
  final textCtrl = TextEditingController();
  double dragX = 0;
  double dragY = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    security = TVSecurityManager(cert);
    remote = TVRemoteClient(cert, onDisconnected: _onTvDisconnected);
    _init();
  }

  Future<void> _init() async {
    try {
      irOk = await ir.invokeMethod<bool>('hasIr') ?? false;
    } catch (_) {
      irOk = false;
    }

    await cert.ensureReady();

    final savedIp = await storage.read(key: lastTvKey);
    if (savedIp != null && savedIp.isNotEmpty && await security.isPaired(savedIp)) {
      tvIp = savedIp;
      ipCtrl.text = savedIp;
      await _reconnectNow(showStatus: false);
    }

    discoverySub = discovery.stream.listen((items) {
      if (!mounted) return;
      setState(() {
        tvs = items;
        scanning = false;
        if (!tvConnected && !reconnecting) {
          status = items.isEmpty ? 'TV bulunamadı' : 'TV seç';
        }
      });
    });

    try {
      await discovery.start();
    } catch (_) {
      if (mounted && !tvConnected) {
        setState(() {
          scanning = false;
          status = 'TV taraması açılamadı';
        });
      }
    }

    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && keepConnected && !tvConnected && tvIp != null) {
      _reconnectNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    reconnectTimer?.cancel();
    discoverySub?.cancel();
    discovery.dispose();
    remote.dispose();
    security.cancel();
    ipCtrl.dispose();
    textCtrl.dispose();
    super.dispose();
  }

  void note(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  void _onTvDisconnected() {
    if (!mounted) return;
    setState(() {
      tvConnected = false;
      status = keepConnected ? 'Bağlantı düştü • geri bağlanıyor…' : 'Bağlantı kapalı';
    });
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    reconnectTimer?.cancel();
    if (!keepConnected || tvIp == null) return;
    reconnectTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!tvConnected && !reconnecting) _reconnectNow();
    });
  }

  Future<void> _reconnectNow({bool showStatus = true}) async {
    final ip = tvIp;
    if (ip == null || ip.isEmpty || reconnecting || tvConnected) return;

    reconnecting = true;
    if (mounted && showStatus) {
      setState(() => status = 'TV’ye bağlanıyor…');
    }

    final ok = await remote.connect(ip);
    reconnecting = false;

    if (!mounted) return;
    setState(() {
      tvConnected = ok;
      status = ok ? 'Bağlı' : 'Tekrar bağlanıyor…';
    });

    if (ok) {
      reconnectTimer?.cancel();
    } else {
      _scheduleReconnect();
    }
  }

  Future<void> connectIp(String ip) async {
    ip = ip.trim();
    if (ip.isEmpty) return;

    keepConnected = true;
    reconnectTimer?.cancel();
    tvIp = ip;
    ipCtrl.text = ip;

    setState(() {
      busy = true;
      status = 'Bağlanıyor…';
    });

    if (await security.isPaired(ip)) {
      final ok = await remote.connect(ip);
      if (ok) await storage.write(key: lastTvKey, value: ip);
      if (mounted) {
        setState(() {
          busy = false;
          tvConnected = ok;
          status = ok ? 'Bağlı' : 'Bağlantı olmadı';
        });
      }
      if (!ok) _scheduleReconnect();
      return;
    }

    final error = await security.begin(ip);
    if (error != null) {
      if (mounted) {
        setState(() {
          busy = false;
          status = 'Eşleştirme olmadı';
        });
      }
      note(error);
      return;
    }

    if (!mounted) return;
    setState(() => busy = false);

    final pinCtrl = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('TV’deki kodu gir'),
        content: TextField(
          controller: pinCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          decoration: const InputDecoration(hintText: 'A1B2C3'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(context, pinCtrl.text), child: const Text('Eşleştir')),
        ],
      ),
    );

    if (pin == null) {
      security.cancel();
      return;
    }

    setState(() => busy = true);
    final paired = await security.submitPin(ip, pin);
    if (!paired) {
      if (mounted) {
        setState(() {
          busy = false;
          status = 'Kod kabul edilmedi';
        });
      }
      note('Kod yanlış veya TV cevap vermedi');
      return;
    }

    final ok = await remote.connect(ip);
    if (ok) await storage.write(key: lastTvKey, value: ip);
    if (mounted) {
      setState(() {
        busy = false;
        tvConnected = ok;
        status = ok ? 'Bağlı' : 'Bağlantı olmadı';
      });
    }
    if (!ok) _scheduleReconnect();
  }

  void key(int code) {
    if (!tvConnected) {
      _reconnectNow();
      note('TV’ye yeniden bağlanıyor');
      return;
    }
    HapticFeedback.selectionClick();
    remote.send(code);
  }

  int? keyForChar(String ch) {
    final c = ch.toLowerCase();
    if (c.isEmpty) return null;
    final n = c.codeUnitAt(0);
    if (n >= 97 && n <= 122) return 29 + (n - 97);
    if (n >= 48 && n <= 57) return 7 + (n - 48);
    if (c == ' ') return 62;
    if (c == '\n') return 66;
    return null;
  }

  Future<void> sendText() async {
    if (!tvConnected) {
      _reconnectNow();
      return;
    }
    for (final rune in textCtrl.text.runes) {
      final code = keyForChar(String.fromCharCode(rune));
      if (code != null) {
        remote.send(code);
        await Future.delayed(const Duration(milliseconds: 45));
      }
    }
  }

  Future<void> _sendSwipe() async {
    final x = dragX;
    final y = dragY;
    dragX = 0;
    dragY = 0;

    final distance = x.abs() > y.abs() ? x.abs() : y.abs();
    if (distance < 22) return;

    int steps = (distance / 70).ceil();
    if (steps < 1) steps = 1;
    if (steps > 4) steps = 4;

    final code = x.abs() > y.abs()
        ? (x > 0 ? 22 : 21)
        : (y > 0 ? 20 : 19);

    for (int i = 0; i < steps; i++) {
      key(code);
      await Future.delayed(const Duration(milliseconds: 55));
    }
  }

  Future<void> acSend() async {
    try {
      final ok = await ir.invokeMethod<bool>('sendAc', {
            'power': acPower,
            'temp': temp,
            'mode': mode,
            'fan': fan,
            'swing': swing,
          }) ??
          false;
      if (!ok) note('IR gönderilemedi');
    } catch (_) {
      note('IR hatası');
    }
  }

  void acChange(void Function() change) {
    setState(change);
    HapticFeedback.selectionClick();
    acSend();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(child: tab == 0 ? _tvPage() : _acPage()),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.tv_rounded), selectedIcon: Icon(Icons.tv), label: 'TV'),
          NavigationDestination(icon: Icon(Icons.ac_unit_rounded), label: 'Klima'),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.settings_remote_rounded),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kumanda', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                Text('Vestel TV + Baymak Klima', style: TextStyle(fontSize: 12, color: Colors.white54)),
              ],
            ),
          ),
          if (tab == 0)
            _statusPill(
              tvConnected ? 'Bağlı' : (reconnecting ? 'Bağlanıyor' : 'Çevrimdışı'),
              tvConnected ? Icons.check_circle_rounded : Icons.sync_rounded,
              tvConnected,
            )
          else
            _statusPill(irOk ? 'IR hazır' : 'IR yok', Icons.sensors_rounded, irOk),
        ],
      ),
    );
  }

  Widget _statusPill(String text, IconData icon, bool active) {
    final color = active ? const Color(0xFF62D394) : Colors.white54;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.055),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _tvPage() {
    if (!tvConnected && tvIp == null) return _connectPage();
    if (!tvConnected && busy) return _connectPage();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
      children: [
        if (!tvConnected)
          _connectionBanner(),
        _quickKeys(),
        const SizedBox(height: 16),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, icon: Icon(Icons.gamepad_rounded), label: Text('Kumanda')),
            ButtonSegment(value: 1, icon: Icon(Icons.touch_app_rounded), label: Text('Touchpad')),
          ],
          selected: {tvMode},
          showSelectedIcon: false,
          onSelectionChanged: (value) => setState(() => tvMode = value.first),
        ),
        const SizedBox(height: 18),
        if (tvMode == 0) _remoteControls() else _touchpadControls(),
        const SizedBox(height: 18),
        _keyboardCard(),
      ],
    );
  }

  Widget _connectionBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(.35),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2)),
          const SizedBox(width: 12),
          Expanded(child: Text('$status\n${tvIp ?? ''}', style: const TextStyle(height: 1.35))),
          IconButton(onPressed: _reconnectNow, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
    );
  }

  Widget _connectPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF15171D),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.tv_rounded, size: 36),
              const SizedBox(height: 14),
              Text(status, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'TV ve telefon aynı Wi‑Fi’da olsun. İlk eşleştirmeden sonra uygulama TV’ye otomatik bağlanır.',
                style: TextStyle(color: Colors.white.withOpacity(.58), height: 1.4),
              ),
              if (busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
              const SizedBox(height: 10),
              for (final tv in tvs)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(.045), borderRadius: BorderRadius.circular(18)),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.tv_rounded)),
                    title: Text(tv.name),
                    subtitle: Text(tv.host ?? ''),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                    onTap: () => connectIp(tv.host ?? ''),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: ipCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'TV IP adresi',
            hintText: '192.168.1.50',
            suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: () => connectIp(ipCtrl.text)),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              scanning = true;
              status = 'TV aranıyor…';
            });
            discovery.start();
          },
          icon: const Icon(Icons.radar_rounded),
          label: const Text('TV’leri tekrar tara'),
        ),
      ],
    );
  }

  Widget _quickKeys() {
    return Row(
      children: [
        Expanded(child: _quickButton(Icons.power_settings_new_rounded, 'Güç', () => key(26), danger: true)),
        const SizedBox(width: 8),
        Expanded(child: _quickButton(Icons.home_rounded, 'Ana Sayfa', () => key(3))),
        const SizedBox(width: 8),
        Expanded(child: _quickButton(Icons.arrow_back_rounded, 'Geri', () => key(4))),
        const SizedBox(width: 8),
        Expanded(child: _quickButton(Icons.input_rounded, 'Kaynak', () => key(178))),
      ],
    );
  }

  Widget _quickButton(IconData icon, String label, VoidCallback action, {bool danger = false}) {
    return Material(
      color: danger ? const Color(0xFF3A181C) : const Color(0xFF17191F),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: action,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, size: 24, color: danger ? const Color(0xFFFF7E89) : null),
              const SizedBox(height: 6),
              Text(label, maxLines: 1, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _remoteControls() {
    return Column(
      children: [
        _dpad(),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: _rocker('SES', Icons.volume_up_rounded, Icons.volume_down_rounded, () => key(24), () => key(25))),
            const SizedBox(width: 12),
            Expanded(child: _rocker('KANAL', Icons.keyboard_arrow_up_rounded, Icons.keyboard_arrow_down_rounded, () => key(166), () => key(167))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _wideButton(Icons.volume_off_rounded, 'Sessiz', () => key(164))),
            const SizedBox(width: 10),
            Expanded(child: _wideButton(Icons.menu_rounded, 'Menü', () => key(82))),
          ],
        ),
        const SizedBox(height: 16),
        _mediaRow(),
      ],
    );
  }

  Widget _dpad() {
    const size = 286.0;
    const edge = 76.0;
    const center = 92.0;
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF15171D),
          border: Border.all(color: Colors.white.withOpacity(.07)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.28), blurRadius: 28, offset: const Offset(0, 14))],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(top: 18, child: _circleKey(Icons.keyboard_arrow_up_rounded, () => key(19), edge)),
            Positioned(bottom: 18, child: _circleKey(Icons.keyboard_arrow_down_rounded, () => key(20), edge)),
            Positioned(left: 18, child: _circleKey(Icons.keyboard_arrow_left_rounded, () => key(21), edge)),
            Positioned(right: 18, child: _circleKey(Icons.keyboard_arrow_right_rounded, () => key(22), edge)),
            _circleKey(null, () => key(23), center, text: 'OK', primary: true),
          ],
        ),
      ),
    );
  }

  Widget _circleKey(IconData? icon, VoidCallback action, double size, {String? text, bool primary = false}) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: primary ? Theme.of(context).colorScheme.primary : Colors.white.withOpacity(.055),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: action,
          child: Center(
            child: text != null
                ? Text(text, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))
                : Icon(icon, size: size * .52),
          ),
        ),
      ),
    );
  }

  Widget _rocker(String title, IconData upIcon, IconData downIcon, VoidCallback up, VoidCallback down) {
    return Container(
      height: 138,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xFF15171D), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(.06))),
      child: Column(
        children: [
          Expanded(child: _rockerPart(upIcon, up)),
          Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Colors.white.withOpacity(.45))),
          Expanded(child: _rockerPart(downIcon, down)),
        ],
      ),
    );
  }

  Widget _rockerPart(IconData icon, VoidCallback action) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: action,
        child: Center(child: Icon(icon, size: 30)),
      ),
    );
  }

  Widget _wideButton(IconData icon, String text, VoidCallback action) {
    return Material(
      color: const Color(0xFF17191F),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: action,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon), const SizedBox(width: 8), Text(text, style: const TextStyle(fontWeight: FontWeight.w600))]),
        ),
      ),
    );
  }

  Widget _mediaRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFF15171D), borderRadius: BorderRadius.circular(22)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(onPressed: () => key(88), icon: const Icon(Icons.fast_rewind_rounded)),
          IconButton.filled(onPressed: () => key(85), icon: const Icon(Icons.play_arrow_rounded)),
          IconButton(onPressed: () => key(87), icon: const Icon(Icons.fast_forward_rounded)),
        ],
      ),
    );
  }

  Widget _touchpadControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 330,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [const Color(0xFF1B1E27), Theme.of(context).colorScheme.primaryContainer.withOpacity(.35)],
            ),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white.withOpacity(.08)),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => key(23),
            onPanStart: (_) {
              dragX = 0;
              dragY = 0;
            },
            onPanUpdate: (details) {
              dragX += details.delta.dx;
              dragY += details.delta.dy;
            },
            onPanEnd: (_) => _sendSwipe(),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app_rounded, size: 44, color: Colors.white.withOpacity(.65)),
                  const SizedBox(height: 12),
                  const Text('Kaydır', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Text('Dokun = OK  •  Uzun kaydır = birkaç adım', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(.46))),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _wideButton(Icons.arrow_back_rounded, 'Geri', () => key(4))),
            const SizedBox(width: 10),
            Expanded(child: _wideButton(Icons.home_rounded, 'Ana Sayfa', () => key(3))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _wideButton(Icons.volume_down_rounded, 'Ses -', () => key(25))),
            const SizedBox(width: 10),
            Expanded(child: _wideButton(Icons.volume_up_rounded, 'Ses +', () => key(24))),
          ],
        ),
      ],
    );
  }

  Widget _keyboardCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF15171D), borderRadius: BorderRadius.circular(22)),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: textCtrl,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => sendText(),
              decoration: const InputDecoration(hintText: 'TV’ye yaz…', prefixIcon: Icon(Icons.keyboard_rounded)),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 52, height: 52, child: IconButton.filled(onPressed: sendText, icon: const Icon(Icons.send_rounded))),
        ],
      ),
    );
  }

  Widget _acPage() {
    final modeNames = ['Auto', 'Soğut', 'Kurut', 'Isıt', 'Fan'];
    final modeIcons = [Icons.auto_awesome_rounded, Icons.ac_unit_rounded, Icons.water_drop_outlined, Icons.local_fire_department_rounded, Icons.air_rounded];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [const Color(0xFF181B22), Theme.of(context).colorScheme.primaryContainer.withOpacity(.28)],
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(.07)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Baymak Klima', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)), SizedBox(height: 3), Text('IR kumanda', style: TextStyle(fontSize: 12, color: Colors.white54))])),
                  SizedBox(
                    width: 58,
                    height: 58,
                    child: IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: acPower ? const Color(0xFF5A43D6) : Colors.white.withOpacity(.08)),
                      onPressed: () => acChange(() => acPower = !acPower),
                      icon: const Icon(Icons.power_settings_new_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('$temp°', style: const TextStyle(fontSize: 78, height: 1, fontWeight: FontWeight.w300, letterSpacing: -4)),
              const SizedBox(height: 6),
              Text(modeNames[mode], style: TextStyle(color: Colors.white.withOpacity(.55), fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _tempButton(Icons.remove_rounded, () {
                    if (temp > 16) acChange(() => temp--);
                  }),
                  const SizedBox(width: 28),
                  _tempButton(Icons.add_rounded, () {
                    if (temp < 30) acChange(() => temp++);
                  }),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text('Mod', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        SizedBox(
          height: 82,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: modeNames.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, index) {
              final selected = mode == index;
              return Material(
                color: selected ? Theme.of(context).colorScheme.primary : const Color(0xFF17191F),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => acChange(() => mode = index),
                  child: SizedBox(
                    width: 82,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(modeIcons[index], size: 25), const SizedBox(height: 7), Text(modeNames[index], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))]),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _acTile(
                Icons.air_rounded,
                ['Fan Auto', 'Fan Düşük', 'Fan Orta', 'Fan Yüksek'][fan],
                () => acChange(() => fan = (fan + 1) % 4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _acTile(
                Icons.swap_vert_rounded,
                swing ? 'Swing Açık' : 'Swing Kapalı',
                () => acChange(() => swing = !swing),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tempButton(IconData icon, VoidCallback action) {
    return SizedBox(
      width: 68,
      height: 68,
      child: IconButton.filledTonal(onPressed: action, icon: Icon(icon, size: 30)),
    );
  }

  Widget _acTile(IconData icon, String text, VoidCallback action) {
    return Material(
      color: const Color(0xFF17191F),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: action,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          child: Column(children: [Icon(icon, size: 28), const SizedBox(height: 9), Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))]),
        ),
      ),
    );
  }
}
