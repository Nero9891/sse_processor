import '../../chain/src/sse_chain.dart';
import '../../chain/sse_chain_exposure.dart';
import '../../sse_log.dart';
import '../../sse_model.dart';
import '../sse_default_exposure.dart';

/// Inner sse interceptor in order to remove [AutoClearStrategy.stream] type interceptor when receive [eventAutoRemoveType] sse.
/// [eventAutoRemoveType] sse create by client when stream [onDone] called.
final class SSEAutoRemoveInterceptor extends SSEInterceptor {
  static const tag = 'AutoRemoveInterceptor';

  static ServerSentEvent genAutoRemoveSSE() {
    return ServerSentEvent(
        elementType: eventAutoRemoveType,
        sessionLogId: eventAutoRemoveLogId,
        result: "client_mock");
  }

  SSEAutoRemoveInterceptor(SSEInterceptorManager sseInterceptorManager)
      : super(name: "auto_remove", {WatchEvent(eventAutoRemoveType, priority: WatchPriority.high)},
            (chain, response) {
          slog.d("receive sse ${response.event}", tag: tag);
          if (eventAutoRemoveType == response.event.elementType) {
            slog.d("auto remove stream interceptors", tag: tag);
            response.removeCache = true;
            sseInterceptorManager.removeStreamInterceptor();
          }
          return chain.proceed(response);
        }, autoClearStrategy: AutoClearStrategy.round);
}
