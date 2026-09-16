import 'dart:async';
import 'dart:io';

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
    const accent = Color(0xFF8B73FF);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kumanda',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090A0E),
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          surface: const Color(0xFF121319),
        ),
        useMaterial3: true,
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
  bool busy = false;
  bool tvConnected = false;
  bool reconnecting = false;
  bool keepConnected = true;
  bool irOk = false;
  String? tvIp;
  String status = 'TV aranıyor…';

  int tab = 0;
  int temp = 24;
  int fan = 0;
  int mode = 1;
  bool acPower = false;
  bool swing = false;

  final ipCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    security = TVSecurityManager(cert);
    remote = TVRemoteClient(cert, onDisconnected: _onDisconnected);
    _init();
  }

  Future<void> _init() async {
    try {
      irOk = await ir.invokeMethod<bool>('hasIr') ?? false;
    } catch (_) {
      irOk = false;
    }

    await cert.ensureReady();
    final saved = await storage.read(key: lastTvKey);
    if (saved != null && saved.isNotEmpty && await security.isPaired(saved)) {
      tvIp = saved;
      ipCtrl.text = saved;
      await _reconnectNow(showStatus: false);
    }

    discoverySub = discovery.stream.listen((items) {
      if (!mounted) return;
      setState(() {
        tvs = items;
        scanning = false;
        if (!tvConnected && !reconnecting && tvIp == null) {
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
    super.dispose();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1300),
        content: Text(text),
      ),
    );
  }

  void _onDisconnected() {
    if (!mounted) return;
    setState(() {
      tvConnected = false;
      status = 'Bağlantı yenileniyor…';
    });
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    reconnectTimer?.cancel();
    if (!keepConnected || tvIp == null) return;
    reconnectTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!tvConnected && !reconnecting) _reconnectNow(showStatus: false);
    });
  }

  Future<void> _reconnectNow({bool showStatus = true}) async {
    final ip = tvIp;
    if (ip == null || ip.isEmpty || reconnecting || tvConnected) return;
    reconnecting = true;
    if (mounted && showStatus) setState(() => status = 'TV’ye bağlanıyor…');
    final ok = await remote.connect(ip);
    reconnecting = false;
    if (!mounted) return;
    setState(() {
      tvConnected = ok;
      status = ok ? 'Bağlı' : 'Tekrar deneniyor…';
    });
    if (ok) {
      reconnectTimer?.cancel();
    } else {
      _scheduleReconnect();
    }
  }

  Future<void> connectIp(String rawIp) async {
    final ip = rawIp.trim();
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
      if (mounted) setState(() { busy = false; status = 'Eşleştirme olmadı'; });
      _toast(error);
      return;
    }

    if (!mounted) return;
    setState(() => busy = false);
    final pinController = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('TV’deki kodu gir'),
        content: TextField(
          controller: pinController,
          autofocus: true,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'A1B2C3'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(context, pinController.text), child: const Text('Eşleştir')),
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
      if (mounted) setState(() { busy = false; status = 'Kod kabul edilmedi'; });
      _toast('Kod yanlış veya TV cevap vermedi');
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
      _toast('TV’ye yeniden bağlanıyor');
      return;
    }
    HapticFeedback.selectionClick();
    remote.send(code);
  }

  int? _keyForChar(String ch) {
    final c = ch.toLowerCase();
    if (c.isEmpty) return null;
    final n = c.codeUnitAt(0);
    if (n >= 97 && n <= 122) return 29 + (n - 97);
    if (n >= 48 && n <= 57) return 7 + (n - 48);
    if (c == ' ') return 62;
    if (c == '\n') return 66;
    return null;
  }

  Future<void> _showKeyboard() async {
    if (!tvConnected) {
      _reconnectNow();
      return;
    }
    final controller = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15171E),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(context).viewInsets.bottom + 18),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (value) => Navigator.pop(context, value),
                  decoration: InputDecoration(
                    hintText: 'TV’ye yaz…',
                    filled: true,
                    fillColor: Colors.white.withOpacity(.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: () => Navigator.pop(context, controller.text),
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ),
    );
    if (text == null || text.isEmpty) return;
    for (final rune in text.runes) {
      final code = _keyForChar(String.fromCharCode(rune));
      if (code != null) {
        remote.send(code);
        await Future.delayed(const Duration(milliseconds: 45));
      }
    }
  }

  void _openTouchpad() {
    final ip = tvIp;
    if (ip == null) {
      _toast('Önce TV’ye bağlan');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TouchpadPage(
          tvIp: ip,
          sendKey: key,
          showKeyboard: _showKeyboard,
        ),
      ),
    );
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
      if (!ok) _toast('IR gönderilemedi');
    } catch (_) {
      _toast('IR hatası');
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
        height: 70,
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.tv_rounded), label: 'TV'),
          NavigationDestination(icon: Icon(Icons.ac_unit_rounded), label: 'Klima'),
        ],
      ),
    );
  }

  Widget _header() {
    final online = tab == 0 ? tvConnected : irOk;
    final text = tab == 0
        ? (tvConnected ? 'Bağlı' : reconnecting ? 'Bağlanıyor' : 'Çevrimdışı')
        : (irOk ? 'IR hazır' : 'IR yok');
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF8B73FF).withOpacity(.16),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.settings_remote_rounded, color: Color(0xFFB7A9FF)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kumanda', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                Text('Vestel TV  •  Baymak Klima', style: TextStyle(fontSize: 12, color: Colors.white54)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.05),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: Colors.white.withOpacity(.07)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: online ? const Color(0xFF63D49A) : Colors.white38,
                  ),
                ),
                const SizedBox(width: 7),
                Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tvPage() {
    if (tvIp == null && !tvConnected) return _connectPage();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          if (!tvConnected)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF8B73FF).withOpacity(.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(status, style: const TextStyle(fontSize: 12))),
                ],
              ),
            ),
          _topActions(),
          const SizedBox(height: 12),
          Expanded(child: Center(child: _dpad())),
          const SizedBox(height: 10),
          _rockerRow(),
          const SizedBox(height: 10),
          _bottomActions(),
        ],
      ),
    );
  }

  Widget _topActions() {
    return Row(
      children: [
        Expanded(child: _actionTile(Icons.power_settings_new_rounded, 'Güç', () => key(26), danger: true)),
        const SizedBox(width: 8),
        Expanded(child: _actionTile(Icons.home_rounded, 'Ana Sayfa', () => key(3))),
        const SizedBox(width: 8),
        Expanded(child: _actionTile(Icons.arrow_back_rounded, 'Geri', () => key(4))),
        const SizedBox(width: 8),
        Expanded(child: _actionTile(Icons.mouse_rounded, 'Mouse', _openTouchpad, accent: true)),
      ],
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap, {bool accent = false, bool danger = false}) {
    final color = danger
        ? const Color(0xFFFF7373)
        : accent
            ? const Color(0xFFB7A9FF)
            : Colors.white70;
    return Material(
      color: accent ? const Color(0xFF8B73FF).withOpacity(.14) : Colors.white.withOpacity(.045),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 5),
              Text(label, maxLines: 1, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dpad() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final max = constraints.maxHeight < constraints.maxWidth ? constraints.maxHeight : constraints.maxWidth;
        final size = max.clamp(230.0, 292.0);
        final keySize = size * .31;
        final edge = size * .055;
        return SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF14161D),
              border: Border.all(color: Colors.white.withOpacity(.055)),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 28, offset: Offset(0, 12))],
            ),
            child: Stack(
              children: [
                Positioned(top: edge, left: (size - keySize) / 2, child: _dirKey(Icons.keyboard_arrow_up_rounded, () => key(19), keySize)),
                Positioned(bottom: edge, left: (size - keySize) / 2, child: _dirKey(Icons.keyboard_arrow_down_rounded, () => key(20), keySize)),
                Positioned(left: edge, top: (size - keySize) / 2, child: _dirKey(Icons.keyboard_arrow_left_rounded, () => key(21), keySize)),
                Positioned(right: edge, top: (size - keySize) / 2, child: _dirKey(Icons.keyboard_arrow_right_rounded, () => key(22), keySize)),
                Positioned(
                  left: size * .31,
                  top: size * .31,
                  child: Material(
                    color: const Color(0xFF8B73FF),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => key(23),
                      child: SizedBox(
                        width: size * .38,
                        height: size * .38,
                        child: const Center(child: Text('OK', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dirKey(IconData icon, VoidCallback onTap, double size) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: size, height: size, child: Icon(icon, size: size * .52, color: Colors.white70)),
      ),
    );
  }

  Widget _rockerRow() {
    return Row(
      children: [
        Expanded(child: _rocker('SES', Icons.volume_down_rounded, Icons.volume_up_rounded, () => key(25), () => key(24))),
        const SizedBox(width: 10),
        _smallRound(Icons.volume_off_rounded, () => key(164)),
        const SizedBox(width: 10),
        Expanded(child: _rocker('KANAL', Icons.remove_rounded, Icons.add_rounded, () => key(167), () => key(166))),
      ],
    );
  }

  Widget _rocker(String title, IconData minus, IconData plus, VoidCallback onMinus, VoidCallback onPlus) {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.045),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(child: IconButton(onPressed: onMinus, icon: Icon(minus))),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: const TextStyle(fontSize: 10, color: Colors.white46, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              const Icon(Icons.more_horiz_rounded, size: 17, color: Colors.white24),
            ],
          ),
          Expanded(child: IconButton(onPressed: onPlus, icon: Icon(plus))),
        ],
      ),
    );
  }

  Widget _smallRound(IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: 58,
      height: 58,
      child: IconButton.filledTonal(onPressed: onTap, icon: Icon(icon)),
    );
  }

  Widget _bottomActions() {
    return Row(
      children: [
        Expanded(child: _wideButton(Icons.keyboard_rounded, 'Klavye', _showKeyboard)),
        const SizedBox(width: 8),
        Expanded(child: _wideButton(Icons.menu_rounded, 'Menü', () => key(82))),
        const SizedBox(width: 8),
        Expanded(child: _wideButton(Icons.play_arrow_rounded, 'Oynat', () => key(85))),
      ],
    );
  }

  Widget _wideButton(IconData icon, String label, VoidCallback onTap) {
    return SizedBox(
      height: 50,
      child: FilledButton.tonalIcon(onPressed: onTap, icon: Icon(icon, size: 19), label: Text(label)),
    );
  }

  Widget _connectPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.white.withOpacity(.04), borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(status, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Telefon ve TV aynı Wi‑Fi ağında olsun.', style: TextStyle(color: Colors.white54)),
              if (busy || scanning) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(minHeight: 2),
              ],
              const SizedBox(height: 12),
              for (final tv in tvs)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.tv_rounded)),
                  title: Text(tv.name),
                  subtitle: Text(tv.host ?? ''),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => connectIp(tv.host ?? ''),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: ipCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'TV IP',
            hintText: '192.168.1.50',
            filled: true,
            fillColor: Colors.white.withOpacity(.04),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            suffixIcon: IconButton(icon: const Icon(Icons.link_rounded), onPressed: () => connectIp(ipCtrl.text)),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () async {
            setState(() => scanning = true);
            await discovery.start();
          },
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tekrar ara'),
        ),
      ],
    );
  }

  Widget _acPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(colors: [Color(0xFF171922), Color(0xFF111319)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            border: Border.all(color: Colors.white.withOpacity(.06)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Baymak', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
                  IconButton.filled(
                    onPressed: () => acChange(() => acPower = !acPower),
                    icon: Icon(acPower ? Icons.power_settings_new_rounded : Icons.power_off_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text('$temp°', style: const TextStyle(fontSize: 76, height: 1, fontWeight: FontWeight.w300)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _smallRound(Icons.remove_rounded, () { if (temp > 16) acChange(() => temp--); }),
                  const SizedBox(width: 28),
                  _smallRound(Icons.add_rounded, () { if (temp < 30) acChange(() => temp++); }),
                ],
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                alignment: WrapAlignment.center,
                children: [
                  for (final item in const [(0, 'Auto'), (1, 'Soğut'), (2, 'Kurut'), (3, 'Isıt'), (4, 'Fan')])
                    ChoiceChip(
                      label: Text(item.$2),
                      selected: mode == item.$1,
                      onSelected: (_) => acChange(() => mode = item.$1),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => acChange(() => fan = (fan + 1) % 4),
                      child: Text(['Fan Auto', 'Fan Düşük', 'Fan Orta', 'Fan Yüksek'][fan]),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => acChange(() => swing = !swing),
                      child: Text(swing ? 'Swing Açık' : 'Swing Kapalı'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MouseHelperClient {
  MouseHelperClient(this.ip);
  final String ip;
  Socket? socket;
  bool connecting = false;

  Future<bool> connect() async {
    if (socket != null) return true;
    if (connecting) return false;
    connecting = true;
    try {
      socket = await Socket.connect(ip, 9090, timeout: const Duration(seconds: 2));
      socket!.done.whenComplete(() => socket = null);
      return true;
    } catch (_) {
      socket = null;
      return false;
    } finally {
      connecting = false;
    }
  }

  Future<void> send(String command) async {
    if (socket == null && !await connect()) return;
    try {
      socket!.write('$command\n');
    } catch (_) {
      socket?.destroy();
      socket = null;
    }
  }

  void dispose() {
    socket?.destroy();
    socket = null;
  }
}

class TouchpadPage extends StatefulWidget {
  const TouchpadPage({
    super.key,
    required this.tvIp,
    required this.sendKey,
    required this.showKeyboard,
  });

  final String tvIp;
  final void Function(int code) sendKey;
  final Future<void> Function() showKeyboard;

  @override
  State<TouchpadPage> createState() => _TouchpadPageState();
}

class _TouchpadPageState extends State<TouchpadPage> {
  late final MouseHelperClient helper;
  final Map<int, Offset> pointers = {};
  Offset totalMovement = Offset.zero;
  DateTime? pointerDownAt;
  bool helperOnline = false;
  bool wasTwoFinger = false;
  double scrollAccumulator = 0;

  @override
  void initState() {
    super.initState();
    helper = MouseHelperClient(widget.tvIp);
    _connect();
  }

  Future<void> _connect() async {
    final ok = await helper.connect();
    if (mounted) setState(() => helperOnline = ok);
  }

  @override
  void dispose() {
    helper.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent e) {
    pointers[e.pointer] = e.position;
    if (pointers.length == 1) {
      totalMovement = Offset.zero;
      pointerDownAt = DateTime.now();
      wasTwoFinger = false;
    } else if (pointers.length >= 2) {
      wasTwoFinger = true;
    }
  }

  void _move(PointerMoveEvent e) {
    final old = pointers[e.pointer];
    if (old == null) return;
    final delta = e.position - old;
    pointers[e.pointer] = e.position;

    if (pointers.length == 1 && !wasTwoFinger) {
      totalMovement += Offset(delta.dx.abs(), delta.dy.abs());
      helper.send('MOVE ${(delta.dx * 2.1).round()} ${(delta.dy * 2.1).round()}');
    } else if (pointers.length >= 2) {
      scrollAccumulator += delta.dy;
      if (scrollAccumulator.abs() >= 5) {
        helper.send('SCROLL ${(scrollAccumulator * 4).round()}');
        scrollAccumulator = 0;
      }
    }
  }

  void _up(PointerUpEvent e) {
    pointers.remove(e.pointer);
    if (pointers.isEmpty) {
      final elapsed = pointerDownAt == null ? 9999 : DateTime.now().difference(pointerDownAt!).inMilliseconds;
      final moved = totalMovement.dx + totalMovement.dy;
      if (!wasTwoFinger && elapsed < 320 && moved < 14) {
        HapticFeedback.lightImpact();
        helper.send('CLICK');
      }
      totalMovement = Offset.zero;
      scrollAccumulator = 0;
      wasTwoFinger = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08090D),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton.filledTonal(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mouse', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                        Text('Tam ekran touchpad', style: TextStyle(fontSize: 12, color: Colors.white46)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(.05), borderRadius: BorderRadius.circular(50)),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: helperOnline ? const Color(0xFF63D49A) : const Color(0xFFFFB45E)),
                        ),
                        const SizedBox(width: 7),
                        Text(helperOnline ? 'Mouse hazır' : 'Yardımcı bekleniyor', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerUp: _up,
                  onPointerCancel: (e) {
                    pointers.remove(e.pointer);
                    if (pointers.isEmpty) {
                      totalMovement = Offset.zero;
                      wasTwoFinger = false;
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF171922), Color(0xFF0F1016)],
                      ),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: Colors.white.withOpacity(.065)),
                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 26, offset: Offset(0, 12))],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B73FF).withOpacity(.14),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.mouse_rounded, size: 31, color: Color(0xFFB7A9FF)),
                        ),
                        const SizedBox(height: 18),
                        const Text('Parmağını hareket ettir', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 9),
                        const Text(
                          '1 parmak  •  İmleç\nDokun  •  Tıkla\n2 parmak  •  Sayfayı kaydır',
                          textAlign: TextAlign.center,
                          style: TextStyle(height: 1.75, color: Colors.white46, fontSize: 13),
                        ),
                        if (!helperOnline) ...[
                          const SizedBox(height: 22),
                          OutlinedButton.icon(
                            onPressed: _connect,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Mouse yardımcısına bağlan'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _padButton(Icons.arrow_back_rounded, 'Geri', () => widget.sendKey(4))),
                  const SizedBox(width: 8),
                  Expanded(child: _padButton(Icons.keyboard_rounded, 'Klavye', widget.showKeyboard)),
                  const SizedBox(width: 8),
                  Expanded(child: _padButton(Icons.home_rounded, 'Ana Sayfa', () => widget.sendKey(3))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _padButton(IconData icon, String label, VoidCallback onTap) {
    return SizedBox(
      height: 54,
      child: FilledButton.tonalIcon(onPressed: onTap, icon: Icon(icon, size: 19), label: Text(label)),
    );
  }
}
