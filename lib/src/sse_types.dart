typedef LogCallback = void Function(
  Object? message, {
  String? tag,
  Object? error,
  StackTrace? stackTrace,
  bool? forcePrintFile,
});
