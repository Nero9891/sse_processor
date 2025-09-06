# SSE Processor
一个纯Dart包，用于Server-Sent Events (SSE)的传递管理。

## 项目介绍
SSE Processor是一个专为Flutter应用设计的SSE处理库，它解决了在处理服务器发送事件流时的一系列问题，包括数据解析、速率控制、分发机制、优先级管理、缓存策略等。

## 为什么需要这个库
在处理AI生成数据的流式传输时，客户端通常会面临以下挑战：

解析问题：如何解析流式数据并转换为客户端可用的数据结构
速率控制：如何控制服务器不规则发送的流数据的展示速率
分发机制：如何将转换后的流数据分发到多个模块进行逻辑处理
优先级管理：如何在分发过程中考虑优先级
缓存策略：如何设计循环缓存池进行定时分发
自动清理：如何简化拦截器的注册和注销操作
分发状态控制：如何暂停/恢复分发和监控分发状态
生命周期管理：如何处理自动清理功能相关的生命周期回调
原生流桥接：如何与原生层的网络组件集成
连接状态管理：如何监控和管理SSE连接状态

## 特性

* 完整的SSE处理流程：从流数据解析到缓存、分发的全流程管理
* 灵活的拦截器机制：支持添加多个拦截器接收不同类型的SSE事件
* 智能缓存管理：提供循环缓存池和定时分发功能
* 连接状态监控：实时监控连接状态并通知观察者
* 拦截器自动清理：避免接收无用的SSE事件
* 自定义协议转换：支持不同业务场景的流数据格式转换
* 流过滤器：支持将单个SSE对象转换为多个SSE对象

## 安装

在pubspec.yaml文件中添加以下依赖：
```
dependencies:
  sse_processor: ^1.0.0
```

然后执行以下命令获取依赖：
```
flutter pub get
```

## 使用指南

### 初始化

```
import 'package:dio/dio.dart';
import 'package:sse_processor/sse.dart';

// 创建Dio实例
final dio = Dio();

// 初始化SSEProcessor
SSEProcessor.init(
  SSEProcessorConfig(
    version: '1.0.0',
    debug: true,
    idleTimeout: 30.0, // 秒
    logFileName: 'sse_processor_log',
    exceptionTimeout: 60, // 秒
    sseBufferExtractInterval: 100, // 毫秒
    // 可选配置
    debugTag: 'MY_APP_SSE',
    eleTypesInInterval: {'text', 'message'},
    unCheckConnectStatePaths: {'/api/stream/health'},
    // 自定义过滤器（可选）
    sseFilter: MyCustomSSEFilter(),
    // 自定义流适配器（可选）
    streamAdapter: MyCustomStreamAdapter(),
  ),
  dio,
);
```

### 添加连接状态观察者

```
// 添加连接状态观察者
sseProcessor.addConnectStateObserver(
  SSEConnectObserver(
    'main_observer',
    NotifyPriority.high, // 高优先级
    (ConnectState state) {
      switch (state) {
        case ConnectState.connectActive:
          print('连接活跃，正在传输数据');
          break;
        case ConnectState.connectIdle:
          print('连接空闲，无数据传输');
          break;
        case ConnectState.connectException:
          print('连接异常');
          break;
        case ConnectState.disconnectError:
          print('连接断开，错误');
          break;
        // 处理其他状态...
        default:
          break;
      }
      return false; // 返回true表示不继续传递给后续观察者
    },
  ),
);
```

```
// 添加SSE拦截器
sseProcessor.addSSEInterceptor(
  SSEInterceptor(
    // 监听的事件类型
    watchEvents: {'message', 'text', 'status'},
    // 是否自动清理
    autoClean: true,
    // 拦截器回调
    intercept: (ServerSentEvent sse, SSEChain chain) {
      // 处理接收到的SSE事件
      print('接收到SSE事件: ${sse.elementType}');
      print('事件内容: ${sse.result}');
      
      // 继续传递给链中的下一个拦截器
      return chain.proceed(sse);
      
      // 或者中断传递并返回响应
      // return SSEResponse(removeCache: true, autoRemove: false);
    },
  ),
);
```

### 控制分发状态

```
// 暂停分发
sseProcessor.setDeliverState(DelivererState.pause);

// 恢复分发
sseProcessor.setDeliverState(DelivererState.active);
```

### 资源释放

在不再需要SSEProcessor时，记得释放资源：

```
// 释放资源
sseProcessor.destroy();
```

## 核心概念
ServerSentEvent

SSE事件的基本数据结构，包含以下字段：

* sessionLogId: 会话日志ID
* elementType: 元素类型
* result: 事件结果内容
* extra: 额外信息
* isHistory: 是否为历史事件

SSEInterceptor

SSE事件的拦截器，用于处理特定类型的SSE事件：

* watchEvents: 监听的事件类型集合
* autoClean: 是否自动清理
* intercept: 拦截处理回调


ConnectState
连接状态枚举，包括以下状态：

* connectActive: 连接正常，正在传输数据
* connectIdle: 连接正常，无数据传输
* connectException: 连接异常
* connectSuspend: 连接被客户端挂起
* disconnectRepairing: 连接断开，正在重试
* disconnectError: 连接断开，超过重试次数
* disconnectNormal: 连接正常断开

## 高级用法

### 自定义SSE过滤器

```
class MyCustomSSEFilter implements SSEFilter {
  @override
  Future<List<ServerSentEvent>> resolve(ServerSentEvent sse) async {
    // 例如，将一个完整的消息分割成多个字符事件，模拟打字机效果
    final events = <ServerSentEvent>[];
    if (sse.elementType == 'message' && sse.result != null) {
      for (int i = 0; i < sse.result!.length; i++) {
        final charEvent = ServerSentEvent()
          ..sessionLogId = sse.sessionLogId
          ..elementType = 'message_char'
          ..result = sse.result![i]
          ..extra = sse.extra;
        events.add(charEvent);
      }
    } else {
      events.add(sse);
    }
    return events;
  }
}
```

### 自定义流适配器
```
class MyCustomStreamAdapter implements StreamAdapter {
  @override
  Future<ServerSentEvent?> adapt(dynamic data) async {
    // 处理自定义格式的流数据，转换为ServerSentEvent
    if (data is Map<String, dynamic>) {
      return ServerSentEvent()
        ..sessionLogId = data['session_id']?.toString() ?? ''
        ..elementType = data['type']?.toString() ?? ''
        ..result = data['content']?.toString() ?? ''
        ..extra = jsonEncode(data['metadata'] ?? {});
    }
    return null;
  }
}
```

## 注意事项

确保使用正确的Dio实例：发起流式请求时，必须使用初始化时传入的Dio实例
及时释放资源：在不再需要SSEProcessor时调用destroy()方法释放资源
处理连接状态变化：通过添加连接状态观察者来监控连接状态变化
合理使用自动清理：对于临时使用的拦截器，建议启用autoClean以避免内存泄漏
日志调试：在开发环境中，可以将debug设置为true来启用详细日志
