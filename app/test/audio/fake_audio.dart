import 'package:tosk/audio/sound_service.dart';

/// Records what would have been played.
class FakeAudioBackend implements AudioBackend {
  final List<Sfx> played = [];
  final Set<Sfx> preloaded = {};
  bool disposed = false;

  @override
  Future<void> preload(Iterable<Sfx> sounds) async => preloaded.addAll(sounds);

  @override
  Future<void> play(Sfx sfx) async => played.add(sfx);

  @override
  Future<void> dispose() async => disposed = true;
}
