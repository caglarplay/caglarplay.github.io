from pathlib import Path
import re
import sys

path = Path(sys.argv[1] if len(sys.argv) > 1 else 'remote_build/lib/main.dart')
s = path.read_text()

replacement = r'''  void acChange(void Function() change) {
    setState(change);
    HapticFeedback.selectionClick();
    acSend();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08090D),
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(child: tab == 0 ? _tvPage() : _acPage()),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF121319),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(.06))),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 68,
            child: Row(
              children: [
                Expanded(child: _modernTab(Icons.tv_rounded, 'TV', 0)),
                Expanded(child: _modernTab(Icons.ac_unit_rounded, 'Klima', 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modernTab(IconData icon, String label, int index) {
    final selected = tab == index;
    return InkWell(
      onTap: () => setState(() => tab = index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 74,
            height: 34,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF8B73FF).withOpacity(.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: selected ? const Color(0xFF9B7CFF) : Colors.white54, size: 24),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : Colors.white54)),
        ],
      ),
    );
  }

  Widget _header() {
    final online = tab == 0 ? tvConnected : irOk;
    final text = tab == 0
        ? (tvConnected ? 'Bağlı' : reconnecting ? 'Bağlanıyor' : 'Çevrimdışı')
        : (irOk ? 'IR hazır' : 'IR yok');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F15),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(.035))),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF342765), Color(0xFF19172D)]),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF8B73FF).withOpacity(.28)),
              boxShadow: [BoxShadow(color: const Color(0xFF8B73FF).withOpacity(.10), blurRadius: 18)],
            ),
            child: const Icon(Icons.settings_remote_rounded, color: Color(0xFFA98EFF), size: 28),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kumanda', style: TextStyle(fontSize: 24, height: 1, fontWeight: FontWeight.w900, letterSpacing: -.4)),
                SizedBox(height: 6),
                Text('Vestel TV  •  Baymak Klima', style: TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFF171920),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(.07)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: online ? const Color(0xFF56E49B) : Colors.white30)),
                const SizedBox(width: 7),
                Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 7),
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _toast(tvIp == null ? 'TV seçilmedi' : 'TV: $tvIp'),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: const Color(0xFF171920), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(.06))),
              child: const Icon(Icons.settings_rounded, size: 21, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tvPage() {
    if (tvIp == null && !tvConnected) return _connectPage();
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 390,
              height: 706,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Column(
                  children: [
                    if (!tvConnected)
                      Container(
                        height: 28,
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        decoration: BoxDecoration(color: const Color(0xFF8B73FF).withOpacity(.10), borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.7)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(status, style: const TextStyle(fontSize: 10.5, color: Colors.white70))),
                        ]),
                      ),
                    Row(
                      children: [
                        Expanded(child: _modernQuick(Icons.power_settings_new_rounded, 'Güç', () => key(26), danger: true)),
                        const SizedBox(width: 7),
                        Expanded(child: _modernQuick(Icons.input_rounded, 'Kaynak', () => key(178))),
                        const SizedBox(width: 7),
                        Expanded(child: _modernQuick(Icons.grid_view_rounded, 'Uygulamalar', () => key(284))),
                        const SizedBox(width: 7),
                        Expanded(child: _modernQuick(Icons.live_tv_rounded, 'Rehber', () => key(172))),
                        const SizedBox(width: 7),
                        Expanded(child: _modernQuick(Icons.favorite_rounded, 'Favori', () => key(174), accent: true)),
                      ],
                    ),
                    const SizedBox(height: 9),
                    _modernDpad(),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(child: _modernNav(Icons.menu_rounded, 'Menü', () => key(82))),
                        const SizedBox(width: 8),
                        Expanded(child: _modernNav(Icons.home_rounded, 'Ana Sayfa', () => key(3), accent: true)),
                        const SizedBox(width: 8),
                        Expanded(child: _modernNav(Icons.undo_rounded, 'Geri', () => key(4), accent: true)),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: _modernRocker('Ses', Icons.volume_up_rounded, () => key(24), () => key(25))),
                        const SizedBox(width: 12),
                        _modernMute(),
                        const SizedBox(width: 12),
                        Expanded(child: _modernRocker('Kanal', Icons.tv_rounded, () => key(166), () => key(167))),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(child: _modernBottom(Icons.keyboard_rounded, 'Klavye', _showKeyboard)),
                        const SizedBox(width: 8),
                        Expanded(child: _modernBottom(Icons.play_arrow_rounded, 'Oynat / Duraklat', () => key(85))),
                        const SizedBox(width: 8),
                        Expanded(child: _modernBottom(Icons.stop_rounded, 'Durdur', () => key(86))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _modernQuick(IconData icon, String label, VoidCallback onTap, {bool danger = false, bool accent = false}) {
    final fg = danger ? const Color(0xFFFF626B) : (accent ? const Color(0xFFA98EFF) : Colors.white78);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 66,
        decoration: BoxDecoration(
          color: const Color(0xFF15171E),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: danger ? const Color(0xFFFF4D58).withOpacity(.22) : accent ? const Color(0xFF8B73FF).withOpacity(.28) : Colors.white.withOpacity(.055)),
          boxShadow: [BoxShadow(color: accent ? const Color(0xFF8B73FF).withOpacity(.08) : Colors.black26, blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: fg, size: 23),
          const SizedBox(height: 5),
          FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700))),
        ]),
      ),
    );
  }

  Widget _modernDpad() {
    return Container(
      width: 300,
      height: 300,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF11131A),
        border: Border.all(color: const Color(0xFF7655E8).withOpacity(.55), width: 1.4),
        boxShadow: [BoxShadow(color: const Color(0xFF6F4CFF).withOpacity(.10), blurRadius: 25, spreadRadius: 2)],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(top: 18, child: _modernPadKey(Icons.keyboard_arrow_up_rounded, () => key(19), 112, 70)),
          Positioned(bottom: 18, child: _modernPadKey(Icons.keyboard_arrow_down_rounded, () => key(20), 112, 70)),
          Positioned(left: 18, child: _modernPadKey(Icons.keyboard_arrow_left_rounded, () => key(21), 70, 112)),
          Positioned(right: 18, child: _modernPadKey(Icons.keyboard_arrow_right_rounded, () => key(22), 70, 112)),
          InkWell(
            onTap: () => key(23),
            customBorder: const CircleBorder(),
            child: Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF9A7CFF), Color(0xFF6A42FF)]),
                boxShadow: [BoxShadow(color: const Color(0xFF7048FF).withOpacity(.45), blurRadius: 28, spreadRadius: 2)],
              ),
              child: const Center(child: Text('OK', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modernPadKey(IconData icon, VoidCallback onTap, double width, double height) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1D202A), Color(0xFF13151C)]),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withOpacity(.04)),
        ),
        child: Icon(icon, size: 38, color: Colors.white88),
      ),
    );
  }

  Widget _modernNav(IconData icon, String label, VoidCallback onTap, {bool accent = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          gradient: accent ? const LinearGradient(colors: [Color(0xFF31235C), Color(0xFF1A172A)]) : null,
          color: accent ? null : const Color(0xFF171920),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent ? const Color(0xFF8B73FF).withOpacity(.65) : Colors.white.withOpacity(.055)),
          boxShadow: [if (accent) BoxShadow(color: const Color(0xFF7B55FF).withOpacity(.13), blurRadius: 18)],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 23, color: Colors.white88),
          const SizedBox(width: 7),
          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)))),
        ]),
      ),
    );
  }

  Widget _modernRocker(String label, IconData icon, VoidCallback plus, VoidCallback minus) {
    return Container(
      height: 128,
      decoration: BoxDecoration(
        color: const Color(0xFF15171E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(.055)),
      ),
      child: Column(
        children: [
          Expanded(child: InkWell(onTap: plus, borderRadius: const BorderRadius.vertical(top: Radius.circular(24)), child: const Center(child: Icon(Icons.add_rounded, size: 31, color: Colors.white88)))),
          Icon(icon, size: 25, color: Colors.white78),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w700)),
          Expanded(child: InkWell(onTap: minus, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)), child: const Center(child: Icon(Icons.remove_rounded, size: 30, color: Colors.white88)))),
        ],
      ),
    );
  }

  Widget _modernMute() {
    return InkWell(
      onTap: () => key(164),
      customBorder: const CircleBorder(),
      child: Container(
        width: 82,
        height: 82,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [Color(0xFF292641), Color(0xFF171920)]),
          border: Border.all(color: const Color(0xFF8B73FF).withOpacity(.40)),
          boxShadow: [BoxShadow(color: const Color(0xFF7A54FF).withOpacity(.10), blurRadius: 17)],
        ),
        child: const Icon(Icons.volume_off_rounded, size: 31, color: Colors.white88),
      ),
    );
  }

  Widget _modernBottom(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 56,
        decoration: BoxDecoration(color: const Color(0xFF191B23), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withOpacity(.055))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 20, color: Colors.white88),
          const SizedBox(width: 6),
          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)))),
        ]),
      ),
    );
  }

  Widget _topActions() {'''

pattern = re.compile(r"  void acChange\(void Function\(\) change\) \{.*?\n  Widget _topActions\(\) \{", re.S)
new_s, count = pattern.subn(replacement, s, count=1)
if count != 1:
    raise SystemExit(f'UI patch target not found: {count}')
path.write_text(new_s)
print('modern one-hand UI applied')
