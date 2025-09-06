/// [connectActive] 连接正常，正在传输数据
/// [connectIdle] 连接正常，超过[SSEClient._idleTimeout]无数据传输
/// [connectException] 连接正常，但是过长时间没有数据传输, 超过[SSEClient._exceptionTimeout]
/// [connectSuspend] 连接正常，被客户端挂起了，没有数据传输，这个和[connectException]做区分，[connectException]无数据传输是异常情况，但是[connectSuspend]不是.
/// [disconnectRepairing] 连接已断开，但是正在进行重试 (保留状态，暂时未使用)
/// [disconnectError] 连接已断开，已超过重试最大次数
/// [disconnectNormal] 连接已断开，非异常断开，可能是临时断开，会由程序尝试重新连接
enum ConnectState {
  connectActive,
  connectIdle,
  connectException,
  connectSuspend,
  disconnectRepairing,
  disconnectError,
  disconnectNormal;

  ///是否异常
  bool isAbnormal() {
    return this == connectException || this == disconnectError;
  }
}

class NotifyPriority {
  static NotifyPriority high = NotifyPriority(100);
  static NotifyPriority middle = NotifyPriority(50);
  static NotifyPriority low = NotifyPriority(10);

  int value;

  NotifyPriority(this.value);

  @override
  String toString() {
    return 'NotifyPriority{value: $value}';
  }
}

/// Connection state observer
/// [name] Tag name，Only used for print troubleshooting in log
/// [priority] Notify priority , Connection state change event will prioritize notify to observers,
/// built in :
/// [NotifyPriority.high]
/// [NotifyPriority.middle]
/// [NotifyPriority.low]
/// You can also custom priority by set [NotifyPriority.value]
/// [onConnectStateChange] More detail value ref [ConnectState], If return true, Don't be sent to subsequent observers, If return false will continue send.
class SSEConnectObserver implements Comparable<SSEConnectObserver> {
  String name;
  NotifyPriority priority;
  bool Function(ConnectState state) onConnectStateChange;

  SSEConnectObserver(this.name, this.priority, this.onConnectStateChange);

  @override
  String toString() {
    return 'SSEConnectObserver{name: $name, priority: $priority}';
  }

  @override
  int compareTo(SSEConnectObserver other) {
    if (priority.value > other.priority.value) {
      return -1;
    } else {
      return 1;
    }
  }
}
