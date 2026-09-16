import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'certificate_manager.dart';
import 'remote_protocol.dart';

class TVRemoteClient {
  TVRemoteClient(this.certManager, {this.onDisconnected});

  final CertificateManager certManager;
  final void Function()? onDisconnected;

  SecureSocket? _socket;
  StreamSubscription? _sub;
  final _buffer = <int>[];
  bool connected = false;
  bool _connecting = false;
  String? currentIp;

  Future<bool> connect(String ip) async {
    if (_connecting) return false;
    if (connected && currentIp == ip) return true;

    _connecting = true;
    await _close(notify: false);

    try {
      final ctx = await certManager.buildSecurityContext();
      final socket = await SecureSocket.connect(
        ip,
        6466,
        context: ctx,
        onBadCertificate: (_) => true,
        timeout: const Duration(seconds: 5),
      );

      _socket = socket;
      currentIp = ip;
      connected = true;
      _buffer.clear();
      _sub = socket.listen(
        _onData,
        onDone: () => _close(notify: true),
        onError: (_) => _close(notify: true),
        cancelOnError: true,
      );
      return true;
    } catch (_) {
      await _close(notify: false);
      return false;
    } finally {
      _connecting = false;
    }
  }

  void send(int code) {
    if (!connected || _socket == null) return;
    try {
      _socket!.add(RemoteMessage.buildKeyInject(code, RemoteDirection.short));
    } catch (_) {
      _close(notify: true);
    }
  }

  void _onData(List<int> data) {
    _buffer.addAll(data);
    while (_buffer.isNotEmpty) {
      int len = 0, shift = 0, prefix = 0;
      bool complete = false;

      for (int i = 0; i < _buffer.length && i < 5; i++) {
        final b = _buffer[i];
        len |= (b & 0x7f) << shift;
        shift += 7;
        prefix++;
        if ((b & 0x80) == 0) {
          complete = true;
          break;
        }
      }

      if (!complete || _buffer.length < prefix + len) return;

      final msg = Uint8List.fromList(_buffer.sublist(prefix, prefix + len));
      _buffer.removeRange(0, prefix + len);
      final incoming = RemoteMessage.parse(msg);

      try {
        if (incoming.field == 1) {
          _socket?.add(RemoteMessage.buildConfigure());
        } else if (incoming.field == 2) {
          _socket?.add(RemoteMessage.buildSetActive());
        } else if (incoming.field == 8) {
          _socket?.add(RemoteMessage.buildPingResponse(incoming.pingVal));
        }
      } catch (_) {
        _close(notify: true);
      }
    }
  }

  Future<void> _close({required bool notify}) async {
    final wasConnected = connected;
    connected = false;
    currentIp = null;
    _buffer.clear();

    final sub = _sub;
    _sub = null;
    await sub?.cancel();

    final socket = _socket;
    _socket = null;
    socket?.destroy();

    if (notify && wasConnected) onDisconnected?.call();
  }

  void dispose() {
    _close(notify: false);
  }
}
