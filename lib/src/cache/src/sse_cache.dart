import 'dart:async';

import 'package:synchronized/synchronized.dart';

import '../../chain/sse_chain_exposure.dart';
import '../../destroyable.dart';
import '../../sse_log.dart';
import '../../sse_model.dart';
import '../sse_cache_exposure.dart';

/// Manage sse cache pool, put sse cache to [_sseCache] when receive [ServerSentEventCache] then loop in interval time deliver to interceptors until removed.
///
/// About [_ssePeekCache]
/// There is another cache pool for peek type. About peek style more check [SSEInterceptor.isPeek] property.
/// Maybe open sse stream and register peek type [SSEInterceptor] not same time, so will occur [SSEInterceptor] can't receive interesting sse completely.
/// In order guarantee peek type [SSEInterceptor] must be received all interesting sse, create a [_ssePeekCache] cache them firstly.
/// Loop [_ssePeekCache] dispatch to them when add peek type [SSEInterceptor].
/// Another opportunity dispatch is stream done, sometimes register [SSEInterceptor] before stream done, peek type interceptors also loss interesting sse
///
///                  Interceptor (isPeek true)     Interceptor (isPeek false)
///                           /\                            /\
///                     (loop directly)                (loop interval)
///                           |                             |
/// (SSE Stream) ------(Peek cache pool)---------------> (Cache pool)
///
final class SSECacheDeliverer implements Destroyable {
  static const tag = "SSECacheLooper";

  final List<ServerSentEventCache> _sseCache = [];
  final List<ServerSentEventCache> _ssePeekCache = [];

  DelivererState _state = DelivererState.active;

  Function? idleObserver;

  Timer? _idleChecker;

  int _pauseCount = 0;

  final Lock _pollLock = Lock();

  final Lock _pollLockPeek = Lock();

  bool _breakLoop = false;

  bool _hasDestroyed = false;

  /// For cache see pool tag, If in idle timer check loop the value is equal [_sseIdleLength], Indicates that the connection is idle state.
  int _sseIdleLength = 0;

  /// A flag represent sse cache loop is dispatching event to sse interceptor.
  bool _isDelivering = false;

  bool get isDelivering {
    return _isDelivering;
  }

  /// This flag determines whether some locked operations can be performed, because the current locking operations do not support cancellation.
  bool _canRunLockedTask = true;

  int sseBufferExtractInterval;

  /// Interval distribution will only be carried out for the event types specified in this set.
  Set<String>? eleTypesInInterval;

  SSECacheDeliverer({this.eleTypesInInterval, required this.sseBufferExtractInterval});

  @override
  void destroy() {
    slog.df("destroy...", tag: tag);
    _hasDestroyed = true;
    reset();
  }

  @override
  void reset() {
    slog.df("reset invoke", tag: tag);
    _breakLoop = true;
    _canRunLockedTask = true;
    _pollLock.synchronized(() => _sseCache.clear());
    _pollLockPeek.synchronized(() => _ssePeekCache.clear());
    _idleChecker?.cancel();
    idleObserver = null;
  }

  void clearCache() {
    _breakLoop = true;
    _canRunLockedTask = false;
    _pollLock.synchronized(() => _sseCache.clear());
    _pollLockPeek.synchronized(() => _ssePeekCache.clear());
  }

  void replace(bool Function(ServerSentEventCache element) test, ServerSentEvent event) {
    _breakLoop = true;
    _sseCache.removeWhere(test);
    _sseCache.insert(0, ServerSentEventCache(event, 'replace_sse'));
    slog.df("remove after $_sseCache", tag: tag);
  }

  /// Set deliver state in cache pool
  /// [DelivererState.active] Active deliver
  /// [DelivererState.pause] Pause deliver
  /// Each set state will record switch times, prevent incorrect set state. For example : A module set [DelivererState.pause] then B module set [DelivererState.pause], must be both
  /// module set to [DelivererState.active] will switch to [DelivererState.active].
  /// [isForce] Support to skip count check.
  void setState(DelivererState state, {bool isForce = false}) {
    if (_state != state) {
      slog.df("set deliver state $state isForce $isForce", tag: tag);
      if (isForce) {
        _pauseCount = 0;
        _state = state;
      } else {
        switch (state) {
          case DelivererState.pause:
            _pauseCount++;
            _state = DelivererState.pause;
            break;
          case DelivererState.active:
            _pauseCount--;
            if (_pauseCount == 0) {
              _state = DelivererState.active;
            }
            break;
        }
      }
      switch (_state) {
        case DelivererState.pause:
          if (_idleChecker?.isActive ?? false) {
            _idleChecker?.cancel();
          }
          break;
        case DelivererState.active:
          if (_idleChecker?.isActive ?? false) {
            return;
          }
          _idleChecker = _executeIdleCheck();
          break;
      }
      slog.df("final state $_state _pauseCount $_pauseCount", tag: tag);
    }
  }

  get state {
    return _state;
  }

  /// Trigger idle state event, when [_sseIdleLength] not change for periodic time.
  void setIdleObserver(Function? idle) {
    idleObserver = idle;
    if (_idleChecker?.isActive ?? false) {
      _idleChecker?.cancel();
    }
    _idleChecker = _executeIdleCheck();
  }

  /// Put to sse peek cache pool.
  void putPeek(Iterable<ServerSentEvent> events, {required String reqUrl}) {
    _pollLockPeek.synchronized(
      () {
        if (_hasDestroyed || !_canRunLockedTask) {
          return;
        }
        _ssePeekCache.addAll(
          events.map(
            (ele) {
              return ServerSentEventCache(ele, reqUrl);
            },
          ),
        );
      },
    );
  }

  /// Clear sse peek cache pool.
  void clearPeek() {
    _pollLockPeek.synchronized(() => _ssePeekCache.clear());
  }

  /// Flush Cache and launch loop deliver for [_ssePeekCache].
  void flushPeek({required Function(ServerSentEventCache event) pop}) {
    _pollLockPeek.synchronized(() {
      for (var element in _ssePeekCache) {
        pop.call(element);
      }
    });
  }

  /// Put sse list to cache pool.
  void put(Iterable<ServerSentEvent> events,
      {required String reqUrl, required PopRep Function(ServerSentEventCache event) pop}) {
    _pollLock.synchronized(
      () async {
        if (_hasDestroyed || !_canRunLockedTask) return;
        _sseCache.addAll(
          events.map(
            (ele) {
              return ServerSentEventCache(ele, reqUrl);
            },
          ),
        );
        await _poll((event) => pop.call(event));
        slog.df(
            "cache size ${_sseCache.length} content : ${_sseCache.map((e) => e.cache.elementType)}",
            tag: tag);
      },
    );
  }

  /// Flush Cache and launch loop deliver.
  /// [isIntervalPoll] Is interval poll then deliver to interceptor.
  /// [breakLoop] Is break loop, sometimes invoke flush is polling, will result pool by flush trigger can't run instantly. If hope pool run instantly, set true.
  void flush({required PopRep Function(ServerSentEventCache event) pop, bool breakLoop = false}) {
    // break loop flag must be set before invoke synchronized function, if set break loop flag is true after invoke synchronized function will might cause break invoke synchronized this time.
    if (breakLoop && _pollLock.locked) {
      _breakLoop = true;
    }
    _pollLock.synchronized(
      () async {
        if (_hasDestroyed || !_canRunLockedTask) return;
        await _poll(
          (event) => pop.call(event),
        );
      },
    );
  }

  Timer _executeIdleCheck() {
    return Timer.periodic(Duration(milliseconds: sseBufferExtractInterval), (timer) {
      if (_sseCache.isNotEmpty && _sseIdleLength != _sseCache.length) {
        _sseIdleLength = _sseCache.length;
      } else {
        idleObserver?.call();
      }
    });
  }

  Future _poll(PopRep Function(ServerSentEventCache event) pop) async {
    if (_state == DelivererState.pause || _hasDestroyed) {
      return;
    }
    _breakLoop = false;
    _isDelivering = true;
    for (var value in _sseCache) {
      if (_breakLoop) {
        break;
      }
      PopRep disposeInfo = pop.call(value);
      value.isDirty = disposeInfo.isConsumed;
      value.autoRemove = disposeInfo.autoRemove;
      value.notifiedSSEListener.addAll(disposeInfo.notifiedInterceptors);
      bool shouldInterval = false;
      if (eleTypesInInterval?.isNotEmpty == true) {
        shouldInterval = eleTypesInInterval!.contains(value.cache.elementType);
      }
      if (shouldInterval) {
        await Future.delayed(Duration(milliseconds: sseBufferExtractInterval));
      }
      if (_breakLoop) {
        break;
      }
    }
    _isDelivering = false;
    _sseCache.removeWhere((value) {
      return value.isDirty;
    });
    _breakLoop = false;
    // slog.d("sseCache length ${_sseCache.length} content ${_sseCache.map((e) => e.cache.elementType).toList()}", tag: tag);
  }
}

/// Cache event dispose result.
class PopRep {
  bool isConsumed;

  bool autoRemove;

  /// Each through interceptor will add to this list.
  List<SSEInterceptor> notifiedInterceptors;

  PopRep(this.isConsumed, this.autoRemove, this.notifiedInterceptors);
}
