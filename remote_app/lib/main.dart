import 'dart:async';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'certificate_manager.dart';
import 'tv_discovery.dart';
import 'tv_remote_client.dart';
import 'tv_security.dart';

void main() => runApp(const KumandaApp());

class KumandaApp extends StatelessWidget {
  const KumandaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Kumanda',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const ir = MethodChannel('kumanda/ir');
  final cert = CertificateManager();
  final discovery = TVDiscoveryService();
  late final TVSecurityManager security;
  late final TVRemoteClient remote;
  StreamSubscription? discoverySub;

  List<BonsoirService> tvs = [];
  bool scanning = true, tvConnected = false, irOk = false, busy = false;
  String status = 'TV aranıyor…';
  String? tvIp;
  int tab = 0, temp = 24, fan = 0, mode = 1;
  bool acPower = false, swing = false;
  final ipCtrl = TextEditingController();
  final textCtrl = TextEditingController();
  double dx = 0, dy = 0;

  @override
  void initState() {
    super.initState();
    security = TVSecurityManager(cert);
    remote = TVRemoteClient(cert, onDisconnected: () {
      if (mounted) setState(() { tvConnected = false; status = 'TV bağlantısı koptu'; });
    });
    _init();
  }

  Future<void> _init() async {
    try { irOk = await ir.invokeMethod<bool>('hasIr') ?? false; } catch (_) { irOk = false; }
    await cert.ensureReady();
    discoverySub = discovery.stream.listen((v) {
      if (!mounted) return;
      setState(() {
        tvs = v;
        scanning = false;
        status = v.isEmpty ? 'TV bulunamadı' : 'TV seç';
      });
    });
    try { await discovery.start(); } catch (_) {
      if (mounted) setState(() { scanning = false; status = 'TV taraması açılamadı'; });
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    discoverySub?.cancel();
    discovery.dispose();
    remote.dispose();
    security.cancel();
    ipCtrl.dispose();
    textCtrl.dispose();
    super.dispose();
  }

  void note(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s), duration: const Duration(seconds: 2)));
  }

  Future<void> connectIp(String ip) async {
    ip = ip.trim();
    if (ip.isEmpty) return;
    setState(() { busy = true; status = 'Bağlanıyor…'; });
    if (await security.isPaired(ip)) {
      final ok = await remote.connect(ip);
      if (mounted) setState(() { busy = false; tvConnected = ok; tvIp = ok ? ip : null; status = ok ? 'TV bağlı' : 'Bağlantı olmadı'; });
      return;
    }
    final err = await security.begin(ip);
    if (err != null) {
      if (mounted) setState(() { busy = false; status = 'Eşleştirme olmadı'; });
      note(err);
      return;
    }
    if (!mounted) return;
    setState(() => busy = false);
    final pinCtrl = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('TV’deki 6 haneli kod'),
        content: TextField(controller: pinCtrl, autofocus: true, textCapitalization: TextCapitalization.characters, maxLength: 6, decoration: const InputDecoration(hintText: 'A1B2C3')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(c, pinCtrl.text), child: const Text('Eşleştir')),
        ],
      ),
    );
    if (pin == null) { security.cancel(); return; }
    setState(() => busy = true);
    final paired = await security.submitPin(ip, pin);
    if (!paired) {
      if (mounted) setState(() { busy = false; status = 'Kod kabul edilmedi'; });
      note('Kod yanlış veya TV cevap vermedi');
      return;
    }
    final ok = await remote.connect(ip);
    if (mounted) setState(() { busy = false; tvConnected = ok; tvIp = ok ? ip : null; status = ok ? 'TV bağlı' : 'Bağlantı olmadı'; });
  }

  void key(int code) {
    if (!tvConnected) { note('Önce TV’ye bağlan'); return; }
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
    for (final rune in textCtrl.text.runes) {
      final k = keyForChar(String.fromCharCode(rune));
      if (k != null) { remote.send(k); await Future.delayed(const Duration(milliseconds: 45)); }
    }
  }

  Future<void> acSend() async {
    try {
      final ok = await ir.invokeMethod<bool>('sendAc', {'power': acPower, 'temp': temp, 'mode': mode, 'fan': fan, 'swing': swing}) ?? false;
      if (!ok) note('IR gönderilemedi');
    } catch (_) { note('IR hatası'); }
  }

  void acChange(void Function() f) { setState(f); acSend(); }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Kumanda'), centerTitle: true),
        body: SafeArea(child: tab == 0 ? _tvPage() : _acPage()),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.tv), label: 'TV'),
            NavigationDestination(icon: Icon(Icons.ac_unit), label: 'Klima'),
          ],
        ),
      );

  Widget _tvPage() {
    if (tvConnected) return _remotePage();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                if (busy) const LinearProgressIndicator(),
                if (scanning) const Padding(padding: EdgeInsets.only(top: 10), child: Text('Aynı Wi‑Fi’daki Android TV aranıyor…')),
                for (final tv in tvs)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.tv),
                    title: Text(tv.name),
                    subtitle: Text(tv.host ?? ''),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => connectIp(tv.host ?? ''),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: ipCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'TV IP (gerekirse)',
            hintText: '192.168.1.50',
            suffixIcon: IconButton(icon: const Icon(Icons.link), onPressed: () => connectIp(ipCtrl.text)),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () { setState(() => scanning = true); discovery.start(); },
          icon: const Icon(Icons.refresh),
          label: const Text('Tekrar ara'),
        ),
      ],
    );
  }

  Widget _remotePage() => ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(children: [
            const Icon(Icons.circle, size: 12, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(child: Text('Vestel Android TV  •  ${tvIp ?? ''}')),
            IconButton(onPressed: () { remote.dispose(); setState(() => tvConnected = false); }, icon: const Icon(Icons.link_off)),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _round(Icons.power_settings_new, () => key(26)),
            _round(Icons.home, () => key(3)),
            _round(Icons.arrow_back, () => key(4)),
            _round(Icons.input, () => key(178)),
          ]),
          const SizedBox(height: 18),
          Center(
            child: SizedBox(
              width: 250, height: 250,
              child: Stack(children: [
                Positioned(top: 0, left: 90, child: _round(Icons.keyboard_arrow_up, () => key(19), size: 70)),
                Positioned(bottom: 0, left: 90, child: _round(Icons.keyboard_arrow_down, () => key(20), size: 70)),
                Positioned(left: 0, top: 90, child: _round(Icons.keyboard_arrow_left, () => key(21), size: 70)),
                Positioned(right: 0, top: 90, child: _round(Icons.keyboard_arrow_right, () => key(22), size: 70)),
                Positioned(left: 90, top: 90, child: _round(Icons.circle_outlined, () => key(23), size: 70)),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: FilledButton.tonalIcon(onPressed: () => key(25), icon: const Icon(Icons.volume_down), label: const Text('Ses -'))),
            const SizedBox(width: 8),
            IconButton.filledTonal(onPressed: () => key(164), icon: const Icon(Icons.volume_off)),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.tonalIcon(onPressed: () => key(24), icon: const Icon(Icons.volume_up), label: const Text('Ses +'))),
          ]),
          const SizedBox(height: 16),
          Text('Touchpad', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => key(23),
            onPanUpdate: (d) {
              dx += d.delta.dx; dy += d.delta.dy;
              if (dx.abs() > 32 || dy.abs() > 32) {
                if (dx.abs() > dy.abs()) key(dx > 0 ? 22 : 21); else key(dy > 0 ? 20 : 19);
                dx = 0; dy = 0;
              }
            },
            onPanEnd: (_) { dx = 0; dy = 0; },
            child: Container(
              height: 160,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), color: Theme.of(context).colorScheme.surfaceContainerHighest),
              child: const Center(child: Text('Kaydır = yön   •   Dokun = OK')),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: TextField(controller: textCtrl, decoration: const InputDecoration(labelText: 'TV’ye yaz', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: sendText, icon: const Icon(Icons.send)),
          ]),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _round(Icons.fast_rewind, () => key(88)),
            _round(Icons.play_arrow, () => key(85)),
            _round(Icons.fast_forward, () => key(87)),
          ]),
        ],
      );

  Widget _acPage() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [Icon(irOk ? Icons.wifi_tethering : Icons.warning_amber), const SizedBox(width: 8), Text(irOk ? 'POCO IR hazır' : 'IR erişimi bulunamadı')]),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Baymak', style: Theme.of(context).textTheme.titleLarge),
                  IconButton.filled(onPressed: () => acChange(() => acPower = !acPower), icon: Icon(acPower ? Icons.power_settings_new : Icons.power_off)),
                ]),
                Text('$temp°', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w300)),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _round(Icons.remove, () { if (temp > 16) acChange(() => temp--); }, size: 64),
                  const SizedBox(width: 28),
                  _round(Icons.add, () { if (temp < 30) acChange(() => temp++); }, size: 64),
                ]),
                const SizedBox(height: 18),
                Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
                  for (final x in const [(0,'Auto'),(1,'Soğut'),(2,'Kurut'),(3,'Isıt'),(4,'Fan')])
                    ChoiceChip(label: Text(x.$2), selected: mode == x.$1, onSelected: (_) => acChange(() => mode = x.$1)),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: FilledButton.tonal(onPressed: () => acChange(() => fan = (fan + 1) % 4), child: Text(['Fan Auto','Fan Düşük','Fan Orta','Fan Yüksek'][fan]))),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton.tonal(onPressed: () => acChange(() => swing = !swing), child: Text(swing ? 'Swing Açık' : 'Swing Kapalı'))),
                ]),
              ]),
            ),
          ),
        ],
      );

  Widget _round(IconData icon, VoidCallback onTap, {double size = 56}) => SizedBox(
        width: size,
        height: size,
        child: IconButton.filledTonal(onPressed: onTap, icon: Icon(icon), iconSize: size * .42),
      );
}
