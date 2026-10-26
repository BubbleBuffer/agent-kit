/// A scripted, in-memory backend for galleries and tests, with a
/// deterministic `ManualClock` and the mockups' quota scenario
/// (`quotaReconnectScript`).
library;

export 'src/fake/clock.dart';
export 'src/fake/question_scenario.dart';
export 'src/fake/quota_scenario.dart';
export 'src/fake/scripted_backend.dart';
