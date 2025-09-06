import 'package:sse_processor/src/sse_types.dart';

final slog = SLog();

final class SLog {
  LogCallback? _logCallback;

  void init({required String fileName, required bool debugAble, required LogCallback? onLog}) {
    _logCallback = onLog;
  }

  void _log(Object? message,
      {String? tag, Object? error, StackTrace? stackTrace, bool? forcePrintFile}) {
    if (_logCallback != null) {
      _logCallback!(message,
          tag: tag, error: error, stackTrace: stackTrace, forcePrintFile: forcePrintFile);
    } else {
      print(
          '[SLog - No Logger]: ${tag != null ? "[$tag] " : ""}$message${error != null ? "\nError: $error" : ""}${stackTrace != null ? "\nStackTrace: $stackTrace" : ""}');
    }
  }

  void df(Object? message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(message, tag: tag, error: error, stackTrace: stackTrace, forcePrintFile: true);
  }

  void d(Object? message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(message, tag: tag, error: error, stackTrace: stackTrace, forcePrintFile: false);
  }
}
