import 'package:dio/dio.dart';

import 'chain/sse_chain_exposure.dart';
import 'destroyable.dart';
import 'sse_log.dart';

extension ChainEx on List<SSEInterceptor> {
  void print(String tag) {
    if (length > 0) {
      StringBuffer logSb = StringBuffer();
      logSb.write(
          "\n╔═════════════════════════════════════════════════════════════════════════════════════════\n");
      asMap().forEach((index, element) {
        logSb.write("($index) $element\n");
      });
      logSb.write(
          "╚═════════════════════════════════════════════════════════════════════════════════════════\n");
      slog.d(logSb.toString(), tag: tag);
    }
  }
}

extension ReleaseAbleEx on List<Destroyable> {
  void destroy() {
    forEach((element) {
      element.destroy();
    });
  }

  void reset() {
    forEach((element) {
      element.reset();
    });
  }
}

extension RequestOptionsEx on RequestOptions {
  /// Note that this function only prove request is streaming data , and not doesn't mean return is streaming data.
  bool isStream() {
    return headers["Accept"] == 'text/event-stream';
  }
}
