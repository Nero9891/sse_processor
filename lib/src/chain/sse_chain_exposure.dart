import '../../sse.dart';

/// SSE Interceptor lifecycle.
/// onCreate
///    |
/// onMatchChain
///    |
/// onDestroy
class SSEInterceptorLifeCycle {
  /// Callback when created interceptor and add to chain(interceptor list).
  Function(String name)? onCreate;

  /// Callback when interceptor destroyed.
  Function(String name)? onDestroy;

  /// Callback when match event to interceptor. (Currently, it is similar to the intercept function [SSEInterceptor.intercept])
  Function(String name, String? eleType)? onMatchChain;

  SSEInterceptorLifeCycle({this.onDestroy, this.onCreate, this.onMatchChain});
}

class WatchEvent {
  String eventType;

  /// Used to match content in [ServerSentEvent.result] (Both event type and event content matched will be delivered, Not specifying means ignoring content matching)
  String? matchContent;

  /// SSE deliver priority, Multiple interceptors watch a same event, priority distribution to high priority interceptor processing.
  /// For example : A and B interceptor receive C event simultaneously, A interceptor watch C event priority is [Priority.high], but B interceptor watch C event priority is [Priority.middle]
  /// This will be prioritized send event to interceptor A, if A interceptor removed C event from cache pool, C event will not be received in B interceptor.
  /// Default value [Priority.low]
  late WatchPriority priority;

  WatchEvent(this.eventType, {this.matchContent, WatchPriority? priority}) {
    if (priority == null) {
      this.priority = WatchPriority.low;
    } else {
      this.priority = priority;
    }
  }

  @override
  String toString() {
    return 'WatchEvent{eventType: $eventType, matchContent: $matchContent, priority: $priority}';
  }
}

class WatchPriority {
  static WatchPriority high = WatchPriority(100);
  static WatchPriority middle = WatchPriority(50);
  static WatchPriority low = WatchPriority(10);

  int value;

  WatchPriority(this.value);

  @override
  String toString() {
    return 'WatchPriority{value: $value}';
  }
}

/// Interceptor clear strategy
/// [round] At an round interaction process don't automatic destruction (Destruction after reset) [Deprecated].
/// [stream] Automatic destroy interceptor when stream done, this is a relatively recommended way than [full] type.
enum AutoClearStrategy { round, stream }

class SSEInterceptor {
  /// Module name, At present, it is mainly used for troubleshooting
  String name;

  /// Need to watch event set, Events that are not included in the list are not intercept
  Set<WatchEvent> watchEvents;

  /// SSE intercept callback，return:
  /// [SSEResponse]
  SSEResponse Function(SSEChain chain, SSEResponse response) intercept;

  /// Interceptor clear strategy
  AutoClearStrategy autoClearStrategy;

  /// Interceptor lifecycle callback
  SSEInterceptorLifeCycle? lifeCycle;

  /// The event that is currently being processed
  WatchEvent? curWatchEvent;

  bool hasDestroy = false;

  /// Is must be bypass interceptor, If set true even return [SSEResponse] directly in other interceptors in chain also will callback in this interceptor.
  bool goThrough;

  ///         Interceptor (isPeek true)
  ///            /\
  ///            |
  /// (Server) -----> (Cache pool) -----> Interceptor (isPeek false)
  ///
  /// true receive event from server directly deliver, false will deliver by sse cache pool [SSECacheDeliverer]
  ///
  /// *Set this property must be pay attention* [SSEInterceptor] add to chain before open sse stream.
  bool isPeek;

  SSEInterceptor(this.watchEvents, this.intercept,
      {this.autoClearStrategy = AutoClearStrategy.stream,
      this.name = "unknown",
      this.lifeCycle,
      this.goThrough = false,
      this.isPeek = false});

  @override
  String toString() {
    return 'SSEInterceptor{name: $name, watchEvents: $watchEvents, autoClearStrategy: $autoClearStrategy, _curWatchEvent: $curWatchEvent}';
  }
}
