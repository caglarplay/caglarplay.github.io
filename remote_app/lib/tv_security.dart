import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'certificate_manager.dart';
import 'remote_protocol.dart';

class TVSecurityManager {
  TVSecurityManager(this.certManager);
  final CertificateManager certManager;
  final _storage = const FlutterSecureStorage();
  SecureSocket? _socket;
  Uint8List? _serverDer;
  StreamSubscription? _sub;
  final _buffer=<int>[];
  final _messages=StreamController<Uint8List>.broadcast();

  String _k(String ip)=>'paired_$ip';
  Future<bool> isPaired(String ip)=>_storage.containsKey(key:_k(ip));
  Future<void> forget(String ip)=>_storage.delete(key:_k(ip));

  Future<String?> begin(String ip) async {
    try {
      final ctx=await certManager.buildSecurityContext();
      X509Certificate? peer;
      _socket=await SecureSocket.connect(ip,6467,context:ctx,onBadCertificate:(c){peer=c; return true;},timeout:const Duration(seconds:8));
      _serverDer=peer?.der ?? _socket?.peerCertificate?.der;
      _listen();
      _socket!.add(PairingMessage.buildRequest(serviceName:'atvremote',clientName:'Kumanda')); await _socket!.flush();
      if(await _next()==null) return 'TV cevap vermedi';
      _socket!.add(PairingMessage.buildOptions()); await _socket!.flush();
      if(await _next()==null) return 'TV seçenek cevabı gelmedi';
      _socket!.add(PairingMessage.buildConfiguration()); await _socket!.flush();
      if(await _next(timeout:const Duration(seconds:7))==null) return 'TV PIN göstermedi';
      return null;
    } catch(e){ _clean(); return '$e'; }
  }

  Future<bool> submitPin(String ip,String pin) async {
    try {
      if(_socket==null || _serverDer==null) return false;
      final cPem=await certManager.getClientCertPem();
      if(cPem==null) return false;
      final ck=_rsaFromPem(cPem), sk=_rsaFromDer(_serverDer!);
      if(ck==null||sk==null) return false;
      final p=pin.trim().replaceFirst(RegExp(r'^(0x|0X)'), '').toUpperCase();
      if(p.length!=6) return false;
      final check=int.parse(p.substring(0,2),radix:16);
      final nonce=[int.parse(p.substring(2,4),radix:16),int.parse(p.substring(4,6),radix:16)];
      final input=[..._big(ck.modulus!,256),..._big(ck.exponent!),..._big(sk.modulus!,256),..._big(sk.exponent!),...nonce];
      final secret=sha256.convert(input).bytes;
      if(secret[0]!=check) return false;
      _socket!.add(PairingMessage.buildSecret(secret)); await _socket!.flush();
      final ack=await _next(timeout:const Duration(seconds:8));
      final ok=ack!=null && PairingMessage.parseResponseField(ack)==41;
      _clean();
      if(ok) await _storage.write(key:_k(ip),value:'1');
      return ok;
    } catch(e){ _clean(); return false; }
  }

  void _listen(){
    _buffer.clear(); _sub?.cancel();
    _sub=_socket!.listen((data){_buffer.addAll(data); _dispatch();},onDone:_clean,onError:(_)=>_clean());
  }
  void _dispatch(){
    while(_buffer.isNotEmpty){
      int len=0,shift=0,n=0; bool done=false;
      for(int i=0;i<_buffer.length&&i<5;i++){final b=_buffer[i]; len|=(b&0x7f)<<shift; shift+=7; n++; if((b&0x80)==0){done=true;break;}}
      if(!done || _buffer.length<n+len) return;
      final msg=Uint8List.fromList(_buffer.sublist(n,n+len)); _buffer.removeRange(0,n+len); _messages.add(msg);
    }
  }
  Future<Uint8List?> _next({Duration timeout=const Duration(seconds:5)}) async { try{return await _messages.stream.first.timeout(timeout);}on TimeoutException{return null;} }
  void cancel()=>_clean();
  void _clean(){_sub?.cancel();_sub=null;_socket?.destroy();_socket=null;_serverDer=null;_buffer.clear();}

  static RSAPublicKey? _rsaFromPem(String pem){try{final d=X509Utils.x509CertificateFromPem(pem);final h=d.tbsCertificate!.subjectPublicKeyInfo.bytes;final bytes=Uint8List.fromList(List.generate(h.length~/2,(i)=>int.parse(h.substring(i*2,i*2+2),radix:16)));return CryptoUtils.rsaPublicKeyFromDERBytes(bytes);}catch(_){return null;}}
  static RSAPublicKey? _rsaFromDer(Uint8List der){final b64=base64.encode(der);return _rsaFromPem('-----BEGIN CERTIFICATE-----\n$b64\n-----END CERTIFICATE-----');}
  static List<int> _big(BigInt v,[int? size]){var h=v.toRadixString(16);if(h.length.isOdd)h='0$h';if(size!=null)while(h.length<size*2)h='00$h';return List.generate(h.length~/2,(i)=>int.parse(h.substring(i*2,i*2+2),radix:16));}
}
