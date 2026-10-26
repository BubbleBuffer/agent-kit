// Small text helpers of the chrome: ages, durations, token counts and the
// default rail grouping and meta text.

import 'package:agent_kit_core/agent_kit_core.dart';

import 'rail_model.dart';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `n thing` or `n things`.
String plural(int n, String noun) => '$n ${n == 1 ? noun : '${noun}s'}';

/// A duration as the rail and ledger show it: `41s`, `1m 04s`, `12m`,
/// `1h 05m`.
String formatElapsed(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  if (s < 60) return '${s}s';
  final m = s ~/ 60;
  if (m < 10) return '${m}m ${(s % 60).toString().padLeft(2, '0')}s';
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

/// A token count: `812`, `48.2k`, `1.24M`.
String formatTokens(int n) {
  if (n >= 1000000) {
    return '${_trim((n / 1000000).toStringAsFixed(2))}M';
  }
  if (n >= 1000) {
    return '${_trim((n / 1000).toStringAsFixed(n >= 100000 ? 0 : 1))}k';
  }
  return '$n';
}

String _trim(String fixed) => fixed.contains('.')
    ? fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
    : fixed;

/// How long ago [at] was, as the rail shows it: `12m`, `3h`, `Yesterday`,
/// `Mon`, `Sep 4`. Empty when [at] is null.
String chatAge(DateTime? at, DateTime now) {
  if (at == null) return '';
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return '${d.inHours}h';
  if (days == 1) return 'Yesterday';
  if (days < 7) return _days[at.weekday - 1];
  return '${_months[at.month - 1]} ${at.day}';
}

/// The default meta text after a row's status label: the running agents of
/// a running chat, the error of a failed one, the age of the others. A host
/// that knows more ("edit approval") passes its own through
/// `SessionRail.detailFor`.
String? railDetail(ChatSummary chat, DateTime now) {
  if (chat.status == ChatStatus.running) {
    return chat.runningChildren > 0
        ? plural(chat.runningChildren, 'agent')
        : null;
  }
  if (chat.status == ChatStatus.needsYou) return null;
  if (chat.status == ChatStatus.failed && chat.error != null) {
    return chat.error;
  }
  final age = chatAge(chat.updatedAt, now);
  return age.isEmpty ? null : age;
}

/// Splits [chats] into "Today" and "Earlier" by their last change, keeping
/// the given order; empty groups are left out.
List<SessionGroup> groupSessions(List<ChatSummary> chats, DateTime now) {
  bool isToday(ChatSummary c) {
    final at = c.updatedAt;
    return at != null &&
        at.year == now.year &&
        at.month == now.month &&
        at.day == now.day;
  }

  final first = chats.where(isToday).toList();
  final rest = chats.where((c) => !isToday(c)).toList();
  return [
    if (first.isNotEmpty) SessionGroup('Today', first),
    if (rest.isNotEmpty) SessionGroup('Earlier', rest),
  ];
}
