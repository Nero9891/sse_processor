import 'package:dio/dio.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';

import '../../sse.dart';
import '../destroyable.dart';

abstract class ISSEStream implements Destroyable {
  /// Open a sse stream
  /// [onOpened] First chunk data received will call it
  /// [onSuccess] Stream open success callback
  /// [onDone] Call back when stream transition done
  /// [onReceive] After receive stream data and transform to [ServerSentEvent] callback
  /// [onError] Open fail or transform process throw error callback
  /// [requestOptions] If stream from network request, This parameter represents its request [RequestOptions]
  /// But is not, it will be null.
  void open(
      {Future<void> Function()? onOpened,
      Function()? onSuccess,
      Future<void> Function(List<ServerSentEvent> sseList)? onDone,
      Future<void> Function(ServerSentEvent event)? onReceive,
      Function(Object error)? onError,
      RequestOptions? requestOptions});

  /// Close sse stream
  void close();

  /// SSE stream is transforming
  RxBool isTransforming();
}
