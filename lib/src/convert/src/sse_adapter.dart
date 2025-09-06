import '../../../sse.dart';
import '../../destroyable.dart';
import '../../sse_log.dart';

/// More details reference to [StreamAdapter], There just switch them according to priority.
class StreamAdapterService implements Destroyable {
  StreamAdapter? _adapter;
  final StreamAdapter _default = StreamAdapterDefault();

  set adapter(StreamAdapter? adapter) {
    _adapter = adapter;
  }

  List<ServerSentEvent> onConvert(String value) {
    if (_adapter != null) {
      return _adapter!.onConvert(value);
    } else {
      return _default.onConvert(value);
    }
  }

  @override
  void destroy() {
    _default.destroy();
    _adapter?.destroy();
  }

  @override
  void reset() {
    _default.reset();
    _adapter?.reset();
  }
}

class StreamAdapterDefault extends StreamAdapter {
  static const tag = "StreamAdapterDefault";

  static const jsonEndTag = ">s";

  /// A buffer for receive stream data, In order to transform a integrally [ServerSentEvent]
  StringBuffer _rawBuffer = StringBuffer();

  @override
  List<ServerSentEvent> onConvert(String raw) {
    slog.d("onConvert value $raw", tag: tag);
    // First step parse data from stream to string buffer, protocol according chatGpt.
    List<String> list = raw.split(RegExp(r'\s*\n'));
    for (String str in list) {
      if (str
          .replaceAll('\n', '')
          .replaceAll('data:', '')
          .replaceAll('event:stop', '')
          .replaceAll('\r', '')
          .isNotEmpty) {
        slog.df("add to eventBuffer: $str", tag: tag);
        _rawBuffer.write(str);
      }
    }
    List<ServerSentEvent> adpSSEList = [];
    // Second step parse string buffer data according contract with server developer.
    String checkStr = _rawBuffer.toString();
    while (checkStr.contains(jsonEndTag)) {
      int jsonEndIndex = checkStr.indexOf(jsonEndTag, 0);
      String json = checkStr.substring(0, jsonEndIndex);
      slog.d("ready to parse json $json", tag: tag);
      ServerSentEvent event = ServerSentEvent.fromJson(json.replaceAll('data:', ''));
      if (event.isLegal()) {
        _rawBuffer = StringBuffer(checkStr.replaceRange(0, jsonEndIndex + jsonEndTag.length, ""));
        slog.df("divider event $event current event buffer $_rawBuffer", tag: tag);
        adpSSEList.add(event);
        checkStr = _rawBuffer.toString();
      } else {
        slog.df("parse event illegal : $event", tag: tag);
        break;
      }
    }
    return adpSSEList;
  }

  @override
  void destroy() {
    _rawBuffer.clear();
  }

  @override
  void reset() {
    _rawBuffer.clear();
  }
}
