import 'dart:async';

import 'package:sse_processor/src/sse_log.dart';
import 'package:synchronized/synchronized.dart';

/// Basic (non-reentrant) lock, Copy from [BasicLock], on this basic add cancel function code.
class CancelableLock implements Lock {
  static const tag = "CancelableLock";

  bool _cancel = false;

  /// The last running block
  Future<dynamic>? last;

  @override
  bool get locked => last != null;

  @override
  Future<T> synchronized<T>(FutureOr<T> Function() func, {Duration? timeout}) async {
    final prev = last;
    final completer = Completer<void>.sync();
    last = completer.future;
    try {
      // If there is a previous running block, wait for it
      if (prev != null) {
        if (timeout != null) {
          // This could throw a timeout error
          await prev.timeout(timeout);
        } else {
          await prev;
        }
      }
      if (_cancel) {
        _cancel = false;
        return Future<T>.error('lock has canceled');
      }

      // Run the function and return the result
      var result = func();
      if (result is Future) {
        return await result;
      } else {
        return result;
      }
    } finally {
      // Cleanup
      // waiting for the previous task to be done in case of timeout
      void complete() {
        // Only mark it unlocked when the last one complete
        if (identical(last, completer.future)) {
          last = null;
        }
        completer.complete();
      }

      // In case of timeout, wait for the previous one to complete too
      // before marking this task as complete

      if (prev != null && timeout != null) {
        // But we still returns immediately
        // ignore: unawaited_futures
        prev.then((_) {
          complete();
        });
      } else {
        complete();
      }
    }
  }

  @override
  String toString() {
    return 'Lock[${identityHashCode(this)}]';
  }

  @override
  bool get inLock => locked;

  Future<T> synchronizedCancelable<T>(FutureOr<T> Function() func,
      {required FutureOr<T> Function() funcCanceled, Duration? timeout}) async {
    return synchronized(func, timeout: timeout).catchError((e, s) {
      slog.df('lock has been canceled', tag: tag);
      return funcCanceled.call();
    });
  }

  void cancel() {
    _cancel = true;
  }
}
