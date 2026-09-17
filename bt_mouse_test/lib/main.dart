import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const BtMouseApp());

class BtMouseApp extends StatelessWidget {
  const BtMouseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090A0E),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B73FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const BtMousePage(),
    );
  }
}

class BtMousePage extends StatefulWidget {
  const BtMousePage({super.key});

  @override
  State<BtMousePage> createState() => _BtMousePageState();
}

class _BtMousePageState extends State<BtMousePage> {
  static const channel = MethodChannel('bt_mouse/hid');
  String status = 'Hazır';
  bool hidReady = false;
  bool connected = false;
  List<Map<String, dynamic>> devices = [];

  @override
  void initState() {
    super.initState();
    channel.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'status') {
        final data = Map<String, dynamic>.from(call.arguments as Map);
        setState(() {
          status = data['text']?.toString() ?? status;
          hidReady = data['hidReady'] == true;
          connected = data['connected'] == true;
        });
      }
    });
  }

  Future<void> startHid() async {
    final r = await channel.invokeMethod<String>('startHid');
    if (!mounted) return;
    setState(() => status = r ?? 'Başlatıldı');
  }

  Future<void> discoverable() async {
    await channel.invokeMethod('discoverable');
  }

  Future<void> refreshDevices() async {
    final list = await channel.invokeListMethod<dynamic>('bondedDevices') ?? [];
    if (!mounted) return;
    setState(() {
      devices = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      status = devices.isEmpty ? 'Eşleşmiş Bluetooth cihazı yok' : 'TV’yi seç';
    });
  }

  Future<void> connect(String address) async {
    final ok = await channel.invokeMethod<bool>('connect', {'address': address}) ?? false;
    if (!mounted) return;
    setState(() => status = ok ? 'Bağlanıyor…' : 'Bağlantı başlatılamadı');
  }

  void move(DragUpdateDetails d) {
    if (!connected) return;
    channel.invokeMethod('move', {'dx': d.delta.dx * 1.8, 'dy': d.delta.dy * 1.8});
  }

  void click() {
    if (connected) channel.invokeMethod('click');
  }

  void scroll(int amount) {
    if (connected) channel.invokeMethod('scroll', {'amount': amount});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth Mouse Test')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.05),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(status, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: FilledButton(onPressed: startHid, child: const Text('1. HID Başlat'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton.tonal(onPressed: discoverable, child: const Text('2. Görünür Yap'))),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(onPressed: refreshDevices, child: const Text('3. Eşleşmiş Cihazları Getir')),
              ),
              if (devices.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    itemBuilder: (context, i) {
                      final d = devices[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.tv_rounded),
                        title: Text(d['name']?.toString() ?? 'Cihaz'),
                        subtitle: Text(d['address']?.toString() ?? ''),
                        onTap: () => connect(d['address'].toString()),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 10),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: move,
                  onTap: click,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF15171E),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: connected ? const Color(0xFF8B73FF) : Colors.white12),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.mouse_rounded, size: 48, color: connected ? const Color(0xFFB7A9FF) : Colors.white30),
                          const SizedBox(height: 12),
                          Text(connected ? 'Touchpad hazır' : 'Önce TV’ye Bluetooth ile bağlan', style: const TextStyle(fontSize: 16)),
                          const SizedBox(height: 6),
                          const Text('Sürükle = imleç • Dokun = tık', style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: FilledButton.tonal(onPressed: connected ? () => scroll(-4) : null, child: const Text('Scroll ↑'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton.tonal(onPressed: connected ? () => scroll(4) : null, child: const Text('Scroll ↓'))),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'TV’de Bluetooth/Aksesuar ekle ekranını aç. Telefonda HID Başlat → Görünür Yap → TV ile eşleştir → sonra listeden TV’yi seç.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
