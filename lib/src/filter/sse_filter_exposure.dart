import '../../sse.dart';

/// Purpose for convert a sse object to multiple sse objects.
/// Client receive server sse maybe is whole message in theater situation,
/// program need to slice it to one after one char to mock printer effect.
abstract class SSEFilter {
  Future<List<ServerSentEvent>> resolve(ServerSentEvent sse);
}
