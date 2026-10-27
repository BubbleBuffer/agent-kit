// Interim presentation for sentence titles: a chapter's name and the gist a
// card shows under it. Stored titles and anchors stay raw.

/// Splits a title into the name shown and a gist for the card face. A title of
/// the form "Two to six words: a sentence" gives the words as the name and the
/// sentence as the gist; otherwise the gist is the [summary]'s first sentence.
/// [chapterName] strips the chapter's name from a section title that repeats
/// it as a prefix.
({String name, String gist}) outlineNameGist(
  String title,
  String summary, {
  String? chapterName,
}) {
  var name = title.trim();
  if (chapterName != null && chapterName.isNotEmpty) {
    for (final separator in [': ', ' › ', ' — ', ' – ', ' - ', ' / ']) {
      final prefix = '$chapterName$separator';
      if (name.startsWith(prefix)) {
        name = name.substring(prefix.length).trim();
        break;
      }
    }
  }
  final colon = name.indexOf(': ');
  if (colon > 0) {
    final left = name.substring(0, colon).trim();
    final words = left.split(RegExp(r'\s+')).length;
    final right = name.substring(colon + 2).trim();
    if (words >= 2 && words <= 6 && right.isNotEmpty) {
      return (name: left, gist: right);
    }
  }
  final text = summary.trim();
  final end = text.indexOf(RegExp(r'[.!?](\s|$)'));
  return (name: name, gist: end < 0 ? text : text.substring(0, end + 1));
}

/// The first non-blank decision, or null. Older imported caches lost decision
/// kinds, so their known split labels are skipped.
String? outlineDecision(Iterable<String> decisions) => decisions
    .map((d) => d.trim())
    .where(
      (d) =>
          d.isNotEmpty &&
          !d.startsWith('No context boundary selected from ') &&
          !d.startsWith('Context boundary selected from '),
    )
    .firstOrNull;
