// How the kit reads a file path: one separator rule for every display.

/// The non-empty segments of [path], split on `/` and on `\` (a Windows path
/// such as `C:\repo\src\mod.rs` has the drive as its first segment).
///
/// Each caller keeps its own display policy on top (how many segments, which
/// of `.` and `..` to drop).
List<String> pathSegments(String path) =>
    path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
