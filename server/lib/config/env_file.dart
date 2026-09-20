/// Minimal `.env` loader for the funding server.
///
/// Secrets (Razorpay keys, webhook secret, DATABASE_URL) are managed through
/// a git-ignored `.env` file next to the package, with real environment
/// variables always taking precedence so platform-managed secrets (Docker/K8s
/// secrets, CI variables, production hosts) override a checked-in dev file.
///
/// Deliberately dependency-free: the format handled here covers the common
/// `KEY=VALUE` subset used by this project.
library;

import 'dart:io';

/// Returns the effective environment: values parsed from a `.env` file act as
/// defaults and process (or provided) environment values always win.
///
/// When [path] is null the loader probes, in order, `.env` in the current
/// working directory and `.env` in the server package root (derived from the
/// entrypoint script) and uses the first file that exists. When [path] points
/// at a missing file the result is the process environment alone.
Map<String, String> effectiveEnvironment({
  String? path,
  Map<String, String>? platform,
}) {
  final processEnv = platform ?? Platform.environment;
  return {..._parseExplicitOrDefault(path), ...processEnv};
}

/// Parses the file at [explicitPath] when provided, otherwise the first
/// existing default candidate.
Map<String, String> _parseExplicitOrDefault(String? explicitPath) {
  if (explicitPath != null) {
    final file = File(explicitPath);
    return file.existsSync()
        ? _parse(file.readAsStringSync(), sourceName: explicitPath)
        : const {};
  }
  for (final candidate in _defaultCandidates()) {
    final file = File(candidate);
    if (!file.existsSync()) continue;
    return _parse(file.readAsStringSync(), sourceName: candidate);
  }
  return const {};
}

List<String> _defaultCandidates() {
  final cwd = Directory.current.path;
  final candidates = <String>['$cwd/.env'];
  final anchor = _packageAnchor();
  if (anchor != null && anchor != cwd) {
    candidates.add('$anchor/.env');
  }
  return candidates;
}

/// Derives the server package root from the entrypoint script so `.env` is
/// found regardless of the working directory. Returns null when the script is
/// not a `.dart` file (e.g. an AOT snapshot).
String? _packageAnchor() {
  try {
    final script = Platform.script.toFilePath();
    if (!script.endsWith('.dart')) return null;
    return File(script).parent.parent.path;
  } on UnsupportedError {
    return null;
  }
}

/// Parses a `.env` document. Rules:
///  - blank lines and `#` comment lines are ignored;
///  - an optional `export ` prefix is stripped;
///  - values may be wrapped in single or double quotes;
///  - variable interpolation is intentionally not performed.
Map<String, String> _parse(String source, {required String sourceName}) {
  final result = <String, String>{};
  var lineNumber = 0;
  for (final rawLine in source.split('\n')) {
    lineNumber += 1;
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final body = line.startsWith('export ') ? line.substring(7).trim() : line;
    final separator = body.indexOf('=');
    if (separator <= 0) {
      throw FormatException(
        'Invalid .env line in $sourceName:$lineNumber — expected KEY=VALUE.',
      );
    }
    final key = body.substring(0, separator).trim();
    if (key.isEmpty || !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) {
      throw FormatException(
        'Invalid .env key in $sourceName:$lineNumber: "$key".',
      );
    }
    result[key] = _unquote(body.substring(separator + 1).trim());
  }
  return result;
}

String _unquote(String value) {
  if (value.length >= 2) {
    final first = value.codeUnitAt(0);
    final last = value.codeUnitAt(value.length - 1);
    if ((first == 0x22 && last == 0x22) || (first == 0x27 && last == 0x27)) {
      return value.substring(1, value.length - 1);
    }
  }
  return value;
}
