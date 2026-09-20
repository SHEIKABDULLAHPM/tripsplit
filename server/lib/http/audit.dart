/// Structured audit logging.
///
/// One JSON line per event on stdout. Events carry a stable [event] name and
/// typed fields. Rules:
///  - never log webhook secrets or raw gateway payloads;
///  - payment identifiers may be logged (they identify the record), signatures
///    never;
///  - security failures are always logged at warn.
library;

import 'dart:convert';
import 'dart:io';

/// Structured event recorder.
class Audit {
  Audit({void Function(String line)? sink}) : _sink = sink ?? (stdout.writeln);

  final void Function(String line) _sink;

  void info(String event, Map<String, Object?> fields) =>
      _emit('info', event, fields);

  void warn(String event, Map<String, Object?> fields) =>
      _emit('warn', event, fields);

  void error(String event, Map<String, Object?> fields) =>
      _emit('error', event, fields);

  void _emit(String level, String event, Map<String, Object?> fields) {
    final line = json.encode({
      'ts': DateTime.now().toUtc().toIso8601String(),
      'level': level,
      'event': event,
      'fields': fields,
    });
    _sink(line);
  }
}