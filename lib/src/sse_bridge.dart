import 'dart:async';
import 'dart:typed_data';

import 'package:built_collection/built_collection.dart';
import 'package:flutter/cupertino.dart';

import 'destroyable.dart';
import 'sse_log.dart';

/// It's used to cache bytes stream from native, [bytesBuffer] is cache real data from native stream.
/// [StreamBundle] corresponding to streamId which is native stream and flutter bridge stream relationship unique id.
/// StreamId and [StreamBundle] related to [SSEBridge.streamBufferMaps].
/// [isEnd] is flag that represent native stream end. Which set ture when receive a string [SSEBridge.streamEndFlag] from native stream.
/// [isError] is flag represent native stream throw error when transforming.
class StreamBundle {
  bool isEnd = false;
  bool isError = false;
  List<int> bytesBuffer = [];

  StreamBundle copy() {
    StreamBundle copy = StreamBundle()
      ..isEnd = isEnd
      ..isError = isError
      ..bytesBuffer = bytesBuffer;
    bytesBuffer = [];
    return copy;
  }

  @override
  String toString() {
    return 'StreamBundle{isEnd: $isEnd, isError: $isError, bytesBuffer: $bytesBuffer}';
  }
}

/// Native to Flutter Stream Cache
final class SSEBridge extends ChangeNotifier implements Destroyable {
  static const String _tag = "SSEBridge";
  static const String streamEndFlag = "StreamEnd";
  static const String streamErrorFlag = "StreamError";

  late final Map<String, StreamBundle> streamBufferMaps = {};

  Completer? waitBufferCompleter;

  bool _working = false;

  String? debugTag;

  SSEBridge({this.debugTag});

  bool get isWorking {
    return _working;
  }

  @override
  void destroy() {
    removeListener(_onBufferChanged);
    streamBufferMaps.clear();
    waitBufferCompleter = null;
    _working = false;
  }

  @override
  void reset() {
    streamBufferMaps.clear();
    _working = false;
  }

  void init() {
    addListener(_onBufferChanged);
  }

  void work() {
    slog.d("[Debug Tag $debugTag] work", tag: _tag);
    _working = true;
  }

  void offWork() {
    slog.d("[Debug Tag $debugTag] offWork", tag: _tag);
    _working = false;
    streamBufferMaps.clear();
  }

  /// This receive stream data from native, put them in [streamBufferMaps]
  void receive(Map map) {
    if (!_working) {
      slog.d("[Debug Tag $debugTag] _enable is false, so return", tag: _tag);
      return;
    }
    slog.d("[Debug Tag $debugTag] receive stream map $map", tag: _tag);
    if (map.containsKey("streamId") && map.containsKey("data")) {
      String streamId = map["streamId"];
      if (map["data"] != null && map["data"] is Iterable) {
        _receive(streamId, (map["data"] as Iterable).map((e) => e as int).toBuiltList(),
            isEnd: map["state"] == streamEndFlag || map["state"] == streamErrorFlag,
            isError: map["state"] == streamErrorFlag);
      } else {
        slog.d("[Debug Tag $debugTag] streamId $streamId data format error", tag: _tag);
      }
    } else {
      slog.d("[Debug Tag $debugTag] receive wrong data", tag: _tag);
    }
  }

  /// This function used to read from [streamBufferMaps] in stream format.
  /// Create a new stream that transform stream from native.
  Stream<Uint8List> nativeStream(String streamId) async* {
    StreamBundle? streamBundle = extract(streamId);
    if (streamBundle != null) {
      yield Uint8List.fromList(streamBundle.bytesBuffer);
    }
    slog.d("[Debug Tag $debugTag] get stream bundle first step : $streamBundle working $_working",
        tag: _tag);
    if (streamBundle?.isEnd ?? false) {
      slog.d("[Debug Tag $debugTag] native stream end by extract exist content", tag: _tag);
      return;
    } else {
      while (true && _working) {
        waitBufferCompleter = Completer();
        await waitBufferCompleter!.future;
        streamBundle = extract(streamId);
        slog.d("[Debug Tag $debugTag] get stream bundle second step : $streamBundle", tag: _tag);
        if (streamBundle != null) {
          yield Uint8List.fromList(streamBundle.bytesBuffer);
        }
        if (streamBundle?.isError ?? false) {
          throw Exception('native stream abnormal stop');
        }
        if (streamBundle?.isEnd ?? false) {
          slog.d("[Debug Tag $debugTag] native stream end by completer", tag: _tag);
          break;
        }
      }
    }
  }

  void _onBufferChanged() {
    if (!(waitBufferCompleter?.isCompleted ?? false)) {
      waitBufferCompleter?.complete();
    }
  }

  void _receive(String streamId, BuiltList<int> bytes, {bool isEnd = false, bool isError = false}) {
    slog.d(
        "[Debug Tag $debugTag] _receive stream streamId $streamId bytes $bytes isEnd $isEnd isError $isError",
        tag: _tag);
    streamBufferMaps.putIfAbsent(streamId, () => StreamBundle());
    StreamBundle sb = streamBufferMaps[streamId]!;
    sb.isEnd = isEnd;
    sb.isError = isError;
    sb.bytesBuffer.addAll(bytes);
    notifyListeners();
  }

  StreamBundle? extract(String streamId) {
    if (streamBufferMaps.containsKey(streamId)) {
      StreamBundle sb = streamBufferMaps[streamId]!;
      // slog.d("real extract content $contentBytes streamBufferMaps $streamBufferMaps", tag: _tag);
      return sb.copy();
    } else {
      return null;
    }
  }
}

/// A router that responsible for route stream data from native (Android or Ios) to corresponding [SSEBridge] object in [registers].
/// Because stream data depend native platform transforming, flutter end don't know which is which for multiple [SSEBridge] exist.
/// It is possible to know how to distribute to the corresponding [SSEBridge] through the [NativeStreamRouter].
class NativeStreamRouter {
  static const String tag = "NativeStreamRouter";

  NativeStreamRouter._();

  static final NativeStreamRouter _instance = NativeStreamRouter._();

  factory NativeStreamRouter() {
    return _instance;
  }

  List<SSEBridge> registers = [];

  void register(SSEBridge bridge) {
    registers.add(bridge);
  }

  void unRegister(SSEBridge bridge) {
    registers.remove(bridge);
  }

  /// Very simple route strategy, will optimize this function later.
  void receive(Map map) {
    for (var obj in registers) {
      // just given data to working bridge
      if (obj.isWorking) {
        obj.receive(map);
      }
    }
  }
}
