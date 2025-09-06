import 'package:get/get.dart';

import '../../cache/src/sse_cache.dart';
import '../../destroyable.dart';
import '../../sse_ex.dart';
import '../../sse_log.dart';
import '../../sse_model.dart';
import '../sse_chain_exposure.dart';

/// SSE chain of responsibility for distribution to the corresponding interceptor
final class SSEChain {
  static const tag = "SSEChain";
  final List<SSEInterceptor> _sseInterceptors;
  int _index = -1;

  /// List of interceptors that have been notified
  List<SSEInterceptor> notifiedInterceptors = [];

  SSEChain(this._sseInterceptors);

  List<SSEInterceptor> getInterceptors() {
    return _sseInterceptors;
  }

  SSEResponse proceed(SSEResponse response) {
    return _proceed(response, false);
  }

  /// [goThrough] past the go through interceptor. reg [SSEInterceptor.goThrough] annotation.
  SSEResponse _proceed(SSEResponse response, bool goThrough) {
    _index++;
    if (_index < _sseInterceptors.length) {
      SSEInterceptor interceptor = _sseInterceptors[_index];
      if (goThrough) {
        if (interceptor.goThrough) {
          interceptor.lifeCycle?.onMatchChain?.call(interceptor.name, response.event.elementType);
          notifiedInterceptors.add(interceptor);
          return interceptor.intercept(this, response);
        } else {
          return _proceed(response, true);
        }
      } else {
        interceptor.lifeCycle?.onMatchChain?.call(interceptor.name, response.event.elementType);
        notifiedInterceptors.add(interceptor);
        return _proceed(interceptor.intercept(this, response), true);
      }
    }
    return response;
  }
}

final class SSEInterceptorManager implements Destroyable {
  static const tag = "InterceptorManagerSSE";

  final List<SSEInterceptor> _interceptors = [];

  /// SSE cache pool will deliver sse that matched [SSEInterceptor.watchEvents] to [SSEInterceptor.intercept]
  /// return result represent is add success, true is added to chain, false is not.
  bool addSSEInterceptor(SSEInterceptor interceptor, {bool isOnly = false}) {
    assert(interceptor.name.isNotEmpty, "sse interceptor name is empty");
    if (isOnly) {
      SSEInterceptor? result = _interceptors.firstWhereOrNull((i) {
        return i.name == interceptor.name;
      });
      if (result != null) {
        return false;
      }
    }
    _interceptors.add(interceptor);
    interceptor.lifeCycle?.onCreate?.call(interceptor.name);
    slog.df("add interceptor $interceptor isOnly $isOnly", tag: tag);
    return true;
  }

  void removeStreamInterceptor() {
    // toList method must be invoke, otherwise will throw [ConcurrentModificationException]
    _interceptors
        .where((e) => (e.autoClearStrategy == AutoClearStrategy.stream))
        .toList()
        .forEach((element) {
      _removeInterceptor(element);
    });
  }

  void removeSSEInterceptor(SSEInterceptor interceptor) {
    _removeInterceptor(interceptor);
  }

  @override
  void destroy() {
    for (var element in _interceptors) {
      if (!element.hasDestroy) {
        element.lifeCycle?.onDestroy?.call(element.name);
      }
    }
    _interceptors.clear();
  }

  @override
  void reset() {
    _interceptors.removeWhere((element) => element.autoClearStrategy != AutoClearStrategy.round);
  }

  /// Deliver cache event steps
  ///
  /// Here, a chain of responsibility will be created, which includes three steps to prepare for the establishment of the chain of responsibility.
  ///
  /// Step 1 : Match those interceptors that have same [ServerSentEvent.elementType] with the [event] argument,
  /// Or it is content matching, which is based on the configuration in the interceptor.
  ///
  /// Step 2 : Sort the interceptors according to their priorities.
  ///
  /// Step 3 : Check whether the event has been notified to this interceptor. If it has been notified, this interceptor needs to be excluded.
  ///
  /// [isPeek] more detail see [SSEInterceptor.isPeek]
  DeliverRep deliver(ServerSentEventCache event, {bool isPeek = false}) {
    // Step 1
    List<SSEInterceptor> matchInterceptors = _interceptors.where((interceptor) {
      return interceptor.watchEvents.where((watchEvent) {
        bool isMatchType = watchEvent.eventType == event.cache.elementType;
        bool isMatchContent = true;
        if (watchEvent.matchContent?.isNotEmpty ?? false) {
          isMatchContent = watchEvent.matchContent == event.cache.result;
        }
        bool commonRule = isMatchType && isMatchContent;
        bool isMatchFinal =
            isPeek ? commonRule && interceptor.isPeek : commonRule && !interceptor.isPeek;
        if (isMatchFinal) {
          interceptor.curWatchEvent = watchEvent;
        } else {
          interceptor.curWatchEvent = null;
        }
        return isMatchFinal;
      }).isNotEmpty;
    }).toList();
    // Step 2
    matchInterceptors.sort((a, b) {
      assert(a.curWatchEvent != null && b.curWatchEvent != null);
      if (a.curWatchEvent!.priority.value > b.curWatchEvent!.priority.value) {
        return -1;
      } else if (a.curWatchEvent!.priority.value == b.curWatchEvent!.priority.value) {
        return 0;
      } else {
        return 1;
      }
    });
    // Step 3
    List<SSEInterceptor> interceptorsReal =
        matchInterceptors.where((element) => !event.notifiedSSEListener.contains(element)).toList();
    slog.d("Deliver Event $event\n", tag: tag);
    interceptorsReal.print(tag);
    SSEChain curChain = SSEChain(interceptorsReal);
    slog.d("proceed event ${event.cache}", tag: tag);
    SSEResponse response = curChain.proceed(SSEResponse(event: event.cache, reqUrl: event.reqUrl));
    return DeliverRep(response, curChain.notifiedInterceptors);
  }

  void _removeInterceptor(SSEInterceptor interceptor) {
    if (!interceptor.hasDestroy) {
      interceptor.lifeCycle?.onDestroy?.call(interceptor.name);
      bool result = _interceptors.remove(interceptor);
      interceptor.hasDestroy = true;
      slog.df("remove interceptor $interceptor result $result", tag: tag);
    }
  }
}

/// Interceptor chain disposed sse will return [SSEResponse] , [SSEResponse] will convert to [DeliverRep], [DeliverRep] will convert to [PopRep].
/// [SSEResponse] -> [DeliverRep] - [PopRep]
/// Each step have a little extra data for bride multiple module.
/// [SSEResponse] : Meaning interceptor disposed result.
/// [DeliverRep] : Meaning interceptor manager disposed result.
/// [PopRep] : Provide to [SSECacheDeliverer]
final class DeliverRep {
  SSEResponse sseResponse;
  List<SSEInterceptor> notifiedInterceptors;

  DeliverRep(this.sseResponse, this.notifiedInterceptors);
}

class SSEResponse {
  /// If remove from cache pool
  bool removeCache;

  /// If remove auto remove from cache pool. (This flag is valid only if [removeCache] is false)
  /// true is automatic remove, according to last consumed time stamp match
  /// false don't automatic remove until interceptor consume it
  bool autoRemove;

  String reqUrl;

  ServerSentEvent event;

  SSEResponse(
      {required this.event, this.removeCache = false, this.autoRemove = true, this.reqUrl = ""});

  @override
  String toString() {
    return 'SSEResponse{removeCache: $removeCache, autoRemove: $autoRemove, event: $event reqUrl: $reqUrl}';
  }
}
