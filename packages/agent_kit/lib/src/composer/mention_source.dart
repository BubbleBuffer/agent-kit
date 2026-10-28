// Mentions: the composer asks a MentionSource what `@query` can mean. The kit
// never knows what a file, page or person is; the host answers with KitRefs.

import 'package:agent_kit_core/agent_kit_core.dart' show KitRef;
import 'package:flutter/widgets.dart' show Widget;

/// Where the composer gets its `@` mentions from.
///
/// While the caret sits in a token that starts with [trigger] (at the start
/// of the text or after whitespace), the composer calls [suggest] with the
/// text typed after it and lists the answer above the field. Picking one
/// inserts `@label` into the text; on send the composer reports each
/// remaining mention as a [KitRef] with its `start` and `end` in the text.
abstract interface class MentionSource {
  /// The character that opens a mention. `@` unless the host wants another.
  String get trigger;

  /// Candidates for [query] (the text after the trigger; empty right after
  /// it), best first. The composer shows at most eight.
  Future<List<KitRef>> suggest(String query);
}

/// A [MentionSource] over a fixed list: keeps the refs whose label contains
/// the query, ignoring case. For tests, the gallery and small hosts.
class StaticMentionSource implements MentionSource {
  /// Creates a source over [refs].
  const StaticMentionSource(this.refs, {this.trigger = '@'});

  /// Everything that can be mentioned.
  final List<KitRef> refs;

  @override
  final String trigger;

  @override
  Future<List<KitRef>> suggest(String query) async {
    final q = query.toLowerCase();
    return [
      for (final r in refs)
        if (r.label.toLowerCase().contains(q)) r,
    ];
  }
}

/// How a suggestion row looks beyond the defaults: a host with page icons or
/// first-line titles returns its own.
class MentionRowLook {
  /// Creates a look.
  const MentionRowLook({this.leading, this.label, this.firstLine = false});

  /// Replaces the kind's icon.
  final Widget? leading;

  /// Replaces the ref's label.
  final String? label;

  /// The label stands in for a missing title: drawn muted and italic.
  final bool firstLine;
}
