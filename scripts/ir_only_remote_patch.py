from pathlib import Path
import re
import sys

path = Path(sys.argv[1] if len(sys.argv) > 1 else 'remote_build/lib/main.dart')
s = path.read_text()

# Route every TV key through the phone IR blaster, never through Wi-Fi.
pattern = re.compile(r"  void key\(int code\) \{.*?\n  \}\n\n  Future<void> _tvPowerIr\(\) async \{.*?\n  \}\n\n", re.S)
replacement = '''  void key(int code) {
    HapticFeedback.selectionClick();
    ir.invokeMethod<bool>('sendTvKey', {'keyCode': code}).then((ok) {
      if (ok != true) _toast('IR kodu gönderilemedi');
    }).catchError((_) {
      _toast('IR hatası');
      return false;
    });
  }

'''
s, count = pattern.subn(replacement, s, count=1)
if count != 1:
    raise SystemExit(f'key patch target not found: {count}')

# TV header status is IR only.
s = s.replace("final online = tab == 0 ? tvConnected : irOk;", "final online = irOk;", 1)
s = s.replace("final text = tab == 0\n        ? (tvConnected ? 'Bağlı' : reconnecting ? 'Bağlanıyor' : 'Çevrimdışı')\n        : (irOk ? 'IR hazır' : 'IR yok');", "final text = irOk ? 'IR hazır' : 'IR yok';", 1)

# Never show Wi-Fi pairing page in TV mode.
s = s.replace("    if (tvIp == null && !tvConnected) return _connectPage();\n", "", 1)

# Replace the reconnect banner with an IR warning only when the phone has no IR emitter.
s = s.replace("                    if (!tvConnected)\n", "                    if (!irOk)\n", 1)
s = s.replace("Expanded(child: Text(status, style: const TextStyle(fontSize: 10.5, color: Colors.white70))),", "const Expanded(child: Text('Telefonun IR vericisi bulunamadı', style: TextStyle(fontSize: 10.5, color: Colors.white70))),", 1)

# Keyboard cannot type arbitrary text over ordinary TV IR. Turn that slot into Info.
s = s.replace("_modernBottom(Icons.keyboard_rounded, 'Klavye', _showKeyboard)", "_modernBottom(Icons.info_outline_rounded, 'Bilgi', () => key(18))", 1)

path.write_text(s)
print('IR-only TV remote applied')
