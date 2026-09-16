import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'certificate_manager.dart';
import 'remote_protocol.dart';

class TVRemoteClient {
  TVRemoteClient(this.certManager,{this.onDisconnected});
  final CertificateManager certManager;
  final void Function()? onDisconnected;
  SecureSocket? _socket; StreamSubscription? _sub; final _buffer=<int>[]; bool connected=false;
  Future<bool> connect(String ip) async {
    try{
      final ctx=await certManager.buildSecurityContext();
      _socket=await SecureSocket.connect(ip,6466,context:ctx,onBadCertificate:(_)=>true,timeout:const Duration(seconds:8));
      connected=true; _sub=_socket!.listen(_onData,onDone:_drop,onError:(_)=>_drop()); return true;
    }catch(_){_drop();return false;}
  }
  void send(int code){if(!connected)return;_socket!.add(RemoteMessage.buildKeyInject(code,RemoteDirection.short));}
  void _onData(List<int> d){_buffer.addAll(d);while(_buffer.isNotEmpty){int len=0,s=0,n=0;bool done=false;for(int i=0;i<_buffer.length&&i<5;i++){final b=_buffer[i];len|=(b&0x7f)<<s;s+=7;n++;if((b&0x80)==0){done=true;break;}}if(!done||_buffer.length<n+len)return;final msg=Uint8List.fromList(_buffer.sublist(n,n+len));_buffer.removeRange(0,n+len);final inc=RemoteMessage.parse(msg);if(inc.field==1)_socket!.add(RemoteMessage.buildConfigure());else if(inc.field==2)_socket!.add(RemoteMessage.buildSetActive());else if(inc.field==8)_socket!.add(RemoteMessage.buildPingResponse(inc.pingVal));}}
  void _drop(){final was=connected;connected=false;_sub?.cancel();_sub=null;_socket?.destroy();_socket=null;if(was)onDisconnected?.call();}
  void dispose()=>_drop();
}
