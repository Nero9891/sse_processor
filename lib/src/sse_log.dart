final slog = SLog();

final class SLog {
  void init({required String fileName, required bool debugAble}) {}

  void df(Object? message, {String? tag, Object? error, StackTrace? stackTrace}) {}

  /// If debug mode will print log content to file, Non-debug mode only print to the console.
  void d(Object? message, {String? tag, Object? error, StackTrace? stackTrace}) {}
}
