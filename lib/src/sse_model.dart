import 'dart:convert';

import 'chain/sse_chain_exposure.dart';

final class ServerSentEvent<T> {
  String? sessionLogId;
  String? elementType;
  String? result;
  String? extra;
  bool isHistory = false;

  ServerSentEvent({this.sessionLogId, this.elementType, this.result, this.extra});

  static ServerSentEvent fromJson(String json) {
    try {
      Map map = jsonDecode(json);
      return ServerSentEvent()
        ..elementType = map['elementType'].toString()
        ..sessionLogId = map['sessionLogId'].toString()
        ..result = map['result']?.toString() ?? ''
        ..extra = jsonEncode(map['extra'])
        ..isHistory = map["isHistory"] ?? false;
    } catch (e) {
      return ServerSentEvent()
        ..elementType = ''
        ..sessionLogId = ''
        ..extra = null
        ..result = '';
    }
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sessionLogId': sessionLogId,
      'elementType': elementType,
      'result': result,
      'isHistory': isHistory
    };
  }

  bool isIllegal() {
    return sessionLogId == null ||
        sessionLogId!.isEmpty ||
        elementType == null ||
        elementType!.isEmpty;
  }

  bool isLegal() {
    return sessionLogId != null &&
        sessionLogId!.isNotEmpty &&
        elementType != null &&
        elementType!.isNotEmpty;
  }

  @override
  String toString() {
    return 'ServerSentEvent{sessionLogId: $sessionLogId, elementType: $elementType, result: $result, extra: $extra, isHistory: $isHistory}';
  }
}

final class ServerSentEventCache {
  ServerSentEvent cache;
  int timeStamp = 0;
  bool isDirty = false;

  /// Whether to automatically remove from the cache, true is to automatically remove,
  /// based on the timeline match of the last consumption,
  /// false will not automatically remove and need to wait until the consumption is blocked)
  bool autoRemove = true;

  /// A notified listening, to prevent duplicate notifications
  Set<SSEInterceptor> notifiedSSEListener = {};

  /// SSE api request url
  String reqUrl;

  ServerSentEventCache(this.cache, this.reqUrl) {
    timeStamp = DateTime.now().microsecondsSinceEpoch;
  }

  @override
  String toString() {
    return 'ServerSentEventCache{cache: $cache, timeStamp: $timeStamp, isDirty: $isDirty, autoRemove: $autoRemove, notifiedSSEListener: $notifiedSSEListener}';
  }
}
