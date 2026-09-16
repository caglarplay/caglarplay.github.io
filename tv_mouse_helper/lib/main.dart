import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MouseHelperApp());

class MouseHelperApp extends StatelessWidget {
  const MouseHelperApp({super.key});

  static const channel = MethodChannel('tv_mouse_helper/settings');

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
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.all(42),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B73FF).withOpacity(.16),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Icon(Icons.mouse_rounded, size: 48, color: Color(0xFFB7A9FF)),
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'TV Mouse Yardımcısı',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Telefondaki Kumanda uygulamasının touchpad özelliği için bu hizmeti bir kez etkinleştir.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, height: 1.5, color: Colors.white60),
                    ),
                    const SizedBox(height: 30),
                    FilledButton.icon(
                      autofocus: true,
                      onPressed: () => channel.invokeMethod('openAccessibility'),
                      icon: const Icon(Icons.accessibility_new_rounded),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 15, horizontal: 10),
                        child: Text('Erişilebilirlik Ayarlarını Aç', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.045),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.info_outline_rounded, color: Colors.white54),
                          SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              'Listeden “TV Mouse Yardımcısı”nı aç. Telefon ve TV aynı Wi‑Fi ağında olsun.',
                              style: TextStyle(fontSize: 15, color: Colors.white54),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
