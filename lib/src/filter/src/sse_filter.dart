import 'package:sse_processor/src/filter/sse_filter_exposure.dart';

import '../../cache/src/sse_cache.dart';
import '../../destroyable.dart';
import '../../sse_log.dart';
import '../../sse_model.dart';

/// SSE stream filter purpose : each converted sse from stream will get through [SSEFilterService] filter firstly.
/// Process by [SSEFilter] then put to [SSECacheDeliverer].
/// The main purpose is decouple logic to outside, sse split (split means one to more) or process way decide by application layer.
final class SSEFilterService extends Destroyable {
  static const tag = "SSEFilterService";

  /// [_filterPermanent] is persistent existence, but [_filterPermanent] support remove by call [reset] function.
  SSEFilter? _filterTransitory;
  SSEFilter? _filterPermanent;

  void setFilter(SSEFilter filter, {bool permanent = false}) {
    if (permanent) {
      _filterPermanent = filter;
    } else {
      _filterTransitory = filter;
    }
  }

  Future<List<ServerSentEvent>> resolve(ServerSentEvent sse) {
    if (_filterTransitory != null) {
      slog.d("resolve sse $sse by filter", tag: tag);
      return _filterTransitory!.resolve(sse);
    } else {
      if (_filterPermanent != null) {
        slog.d("resolve sse $sse by filterPermanent", tag: tag);
        return _filterPermanent!.resolve(sse);
      }
      return Future.value([sse]);
    }
  }

  @override
  void destroy() {
    _filterTransitory = null;
    _filterPermanent = null;
  }

  @override
  void reset() {
    slog.d("reset", tag: tag);
    _filterTransitory = null;
  }
}
