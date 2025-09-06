import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:synchronized/synchronized.dart';

import '../../../sse.dart';
import '../../convert/src/sse_adapter.dart';
import '../../sse_log.dart';

/// Responsible open sse stream , Listen sse stream data, Transform sse event, Close stream.
/// Note :
/// There are actually two streams here. One is the Server-Sent Events (SSE) stream sent by the server (of course, it could also be fake stream data simulated locally).
/// The other is the filter stream. The role of the filter stream is to create a new stream by transforming the original stream data.
/// Why not directly call the transform method on the basis of the original stream?
/// Because the filtering process supports asynchronous filtering, the principle is that the original stream reads data and places it in the buffer,
/// and the newly created filtered stream reads the data in the buffer.
///                  (Stream)
///              [streamOriginal]
///                     |
///             [_adapterService]
///                     |                  (Stream)
///                [_sseBuffer]  --->  [_streamFilter]  ---> Deliver sse
///
final class SSECore implements ISSEStream {
  static const tag = "SSECore";
  static const jsonEndTag = ">s";

  static const String bridgeCommend = "trigger";

  StreamSubscription? _sbOriginal;

  StreamSubscription? _sbFilter;

  Stream streamOriginal;

  late Stream _streamFilter;

  late final StreamAdapterService _adapterService;

  SSECore(this.streamOriginal, {required StreamAdapterService adapterService}) {
    _streamFilter = _filterSController.stream;
    _adapterService = adapterService;
  }

  final RxBool _streamTransforming = false.obs; // SSE stream is transforming

  final Queue<ServerSentEvent> _sseBuffer = Queue<ServerSentEvent>();

  final StreamController<String> _filterSController = StreamController<String>();

  final Lock _processLock = Lock();

  bool _isOriginalStreamDone = false;

  @override
  RxBool isTransforming() {
    return _streamTransforming;
  }

  @override
  void open(
      {Function()? onOpened,
      Function()? onSuccess,
      Future<void> Function(List<ServerSentEvent> sseList)? onDone,
      Function(ServerSentEvent event)? onReceive,
      Function(Object error)? onError,
      RequestOptions? requestOptions}) async {
    // Must be invoke transform function before listen to decode utf8 format, if convert utf8 after listen, will throw error when invalid byte sequences are converted.
    // In my opinion, invalid byte sequences are converted in transform will not be consumed, wait for completely format data will be divider to listen callback.
    _sbOriginal = streamOriginal.transform(StreamTransformer<String, ServerSentEvent>.fromHandlers(
        handleData: (String value, EventSink<ServerSentEvent> sink) async {
      if (!_streamTransforming.value) {
        _streamTransforming.value = true;
        await onOpened?.call();
      }
      slog.d("listen start", tag: tag);
      List<ServerSentEvent> sseList = _adapterService.onConvert(value);
      for (var sse in sseList) {
        sink.add(sse);
      }
    })).listen((event) {
      _sseBuffer.addLast(event);
      _filterSController.add(bridgeCommend);
    }, onDone: () {
      _isOriginalStreamDone = true;
      _filterSController.add(bridgeCommend);
    }, onError: (e) {
      _filterSController.addError(e);
    });
    _sbFilter = _streamFilter.listen((event) {
      _processLock.synchronized(() async {
        while (_sseBuffer.isNotEmpty) {
          await onReceive?.call(_sseBuffer.removeFirst());
        }
        if (_isOriginalStreamDone) {
          _filterSController.close();
        }
      });
    }, onDone: () async {
      slog.d("stream done", tag: tag);
      await onDone?.call([]);
      _streamTransforming.value = false;
      _isOriginalStreamDone = false;
      _sseBuffer.clear();
      _adapterService.destroy();
    }, onError: (e) {
      slog.df("stream error while listening ... $e", tag: tag);
      _streamTransforming.value = false;
      _isOriginalStreamDone = false;
      _sseBuffer.clear();
      _adapterService.destroy();
      onError?.call(e);
    });
  }

  @override
  void close() {
    _streamTransforming.value = false;
    _adapterService.destroy();
    _sbOriginal?.cancel();
    _sbFilter?.cancel();
  }

  @override
  void destroy() {
    close();
  }

  @override
  void reset() {
    close();
  }
}
