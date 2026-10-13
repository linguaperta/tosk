/// Bundled course packs from the Flutter asset bundle (`assets/courses/*.sqlite`),
/// discovered through the AssetManifest, so adding a pack needs no code change.
library;

import 'package:flutter/services.dart';

import 'local_pack_source.dart';

class AssetBundlePacks implements BundledPacks {
  AssetBundlePacks({AssetBundle? bundle, this.prefix = 'assets/courses/'})
      : bundle = bundle ?? rootBundle;

  final AssetBundle bundle;
  final String prefix;

  @override
  Future<List<String>> list() async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    return manifest
        .listAssets()
        .where((k) => k.startsWith(prefix) && k.endsWith('.sqlite'))
        .toList()
      ..sort();
  }

  @override
  Future<Uint8List> load(String key) async {
    final data = await bundle.load(key);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
