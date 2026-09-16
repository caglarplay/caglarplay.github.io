import 'dart:async';
import 'package:bonsoir/bonsoir.dart';

class TVDiscoveryService {
  BonsoirDiscovery? _d; StreamSubscription? _sub;
  final _c=StreamController<List<BonsoirService>>.broadcast();
  final Map<String,BonsoirService> _items={};
  Stream<List<BonsoirService>> get stream=>_c.stream;
  Future<void> start() async {
    await stop(); _items.clear(); _c.add([]);
    _d=BonsoirDiscovery(type:'_androidtvremote2._tcp'); await _d!.initialize();
    _sub=_d!.eventStream!.listen((e){
      switch(e){
        case BonsoirDiscoveryServiceFoundEvent(): _d!.serviceResolver.resolveService(e.service);
        case BonsoirDiscoveryServiceResolvedEvent(): _items[e.service.name]=e.service; _c.add(_items.values.toList());
        case BonsoirDiscoveryServiceLostEvent(): _items.remove(e.service.name); _c.add(_items.values.toList());
        default: break;
      }
    });
    await _d!.start();
  }
  Future<void> stop() async { await _sub?.cancel(); _sub=null; await _d?.stop(); _d=null; }
  void dispose(){stop();_c.close();}
}
