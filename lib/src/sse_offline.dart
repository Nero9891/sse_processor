import 'package:dio/dio.dart';

import '../sse.dart';

/// This class provides offline SSE distribution functionality.
///
/// Most of the time, SSE is sent from the server side, However , sometimes the client
/// generates some data and wants to use the SSE distribution function of the client side.
abstract class SseOfflineProvider {
  ISSEStream onOfflineStream();
}

extension OfflineRequestOptions on RequestOptions {
  /// Check request is return by offline stream.
  ///
  /// If offlineProvider is here, it proves that the data is obtained from the client and there is no need to make
  /// a network request.
  bool isOfflineStream() {
    return extra['offlineProvider'] != null;
  }

  void putOfflineProvider(SseOfflineProvider offlineProvider) {
    extra['offlineProvider'] = offlineProvider;
  }

  SseOfflineProvider? getOfflineStream() {
    return extra['offlineProvider'];
  }
}
