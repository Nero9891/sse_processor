import 'package:sse_processor/sse.dart';

final class SSEProcessorConfig {
  String version; //版本号
  String logFileName; //日志文件名
  String? debugTag; //用于调试的标签，体现在日志上
  double idleTimeout; //判断sse活跃态超时时间
  int exceptionTimeout; //异常连接状态
  int sseBufferExtractInterval; // sse字符缓存提取时间间隔
  Set<String>? eleTypesInInterval; // 只有在这个集合指定的事件类型才会进行间隔分发
  bool debug; //是否是debug模式（debug模式会输出日志）
  SSEFilter? sseFilter; //流转换成SSE首先会经过它
  StreamAdapter? streamAdapter; //外部定义Stream转换SSE过程
  Set<String>? unCheckConnectStatePaths; //指定不做连接状态检查的流式请求地址（有的流式请求不含展示数据，需要排出状态检查）

  SSEProcessorConfig(
      {required this.version,
      required this.debug,
      required this.idleTimeout,
      required this.logFileName,
      required this.exceptionTimeout,
      required this.sseBufferExtractInterval,
      this.sseFilter,
      this.debugTag,
      this.eleTypesInInterval,
      this.unCheckConnectStatePaths,
      this.streamAdapter});

  @override
  String toString() {
    return 'SSEProcessorConfig{version: $version, logFileName: $logFileName, debugTag: $debugTag, idleTimeout: $idleTimeout, exceptionTimeout: $exceptionTimeout, sseBufferExtractInterval: $sseBufferExtractInterval, eleTypesInInterval: $eleTypesInInterval, debug: $debug, sseFilter: $sseFilter, noCheckConnectStateUrls: $unCheckConnectStatePaths}';
  }
}
