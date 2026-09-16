import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

Map<String,String> _makeCert(int bits) {
  final pair = CryptoUtils.generateRSAKeyPair(keySize: bits);
  final pub = pair.publicKey as RSAPublicKey;
  final priv = pair.privateKey as RSAPrivateKey;
  final csr = X509Utils.generateRsaCsrPem({'CN':'kumanda'}, priv, pub);
  final cert = X509Utils.generateSelfSignedCertificate(priv, csr, 3650);
  final key = CryptoUtils.encodeRSAPrivateKeyToPem(priv);
  return {'cert':cert,'key':key};
}

class CertificateManager {
  static const _certK='kumanda_cert_v1', _keyK='kumanda_key_v1';
  final _storage = const FlutterSecureStorage();
  String? _cert, _key;
  Future<void> ensureReady() async {
    if (_cert != null && _key != null) return;
    _cert = await _storage.read(key:_certK); _key = await _storage.read(key:_keyK);
    if (_cert == null || _key == null) {
      final r = await compute(_makeCert, 2048);
      _cert=r['cert']; _key=r['key'];
      await _storage.write(key:_certK,value:_cert); await _storage.write(key:_keyK,value:_key);
    }
  }
  Future<SecurityContext> buildSecurityContext() async {
    await ensureReady();
    final c=SecurityContext(withTrustedRoots:false);
    c.useCertificateChainBytes(utf8.encode(_cert!));
    c.usePrivateKeyBytes(utf8.encode(_key!));
    return c;
  }
  Future<String?> getClientCertPem() async { await ensureReady(); return _cert; }
  Future<Uint8List> getClientCertDer() async { await ensureReady(); return CryptoUtils.getBytesFromPEMString(_cert!); }
}
