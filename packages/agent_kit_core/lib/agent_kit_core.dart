/// The BubbleBuffer agent kit's pure Dart core: view models, the
/// `AgentBackend` port, the event reducer (`reduce`) and `ChatFeed`.
///
/// No Flutter. Widgets in `agent_kit` and the hosts' backend adapters
/// build on this library; the scripted fake backend is in
/// `package:agent_kit_core/fake.dart`.
library;

export 'src/backend.dart';
export 'src/context.dart';
export 'src/events.dart';
export 'src/feed.dart';
export 'src/items.dart';
export 'src/models.dart' hide appendText;
export 'src/providers.dart';
export 'src/reducer.dart';
export 'src/snapshot.dart';
export 'src/value.dart' show Json, KitValue, JsonRead, jsonEquals;
