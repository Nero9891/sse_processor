import '../../sse.dart';
import '../destroyable.dart';

/// Stream raw data to [ServerSentEvent] data structure when transforming from server.
/// [SSEProcessor] support custom transform process.
/// There is [SSEStreamAdapterDefault] will use if don't set [StreamAdapter] outside.
abstract class StreamAdapter implements Destroyable {
  /// [raw] is raw data from stream, implementer should convert it to sse format.
  List<ServerSentEvent> onConvert(String raw);
}
