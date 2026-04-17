import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// 消息类型
enum MsgType { action, status, ambient }

/// MQTT 消息体
class TelepathyMessage {
  final MsgType type;
  final String data;
  final String from; // 发送者 ID
  final DateTime timestamp;

  TelepathyMessage({
    required this.type,
    required this.data,
    this.from = '',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String encode(String senderId) => jsonEncode({
        't': type.name,
        'd': data,
        'f': senderId,
        'ts': timestamp.millisecondsSinceEpoch,
      });

  static TelepathyMessage? decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return TelepathyMessage(
        type: MsgType.values.firstWhere((e) => e.name == map['t']),
        data: map['d'] as String,
        from: map['f'] as String? ?? '',
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
      );
    } catch (_) {
      return TelepathyMessage(type: MsgType.action, data: raw);
    }
  }
}

class MqttService {
  late MqttServerClient client;
  final String uid;
  final String topic;

  final _msgController = StreamController<TelepathyMessage>.broadcast();
  Stream<TelepathyMessage> get messages => _msgController.stream;

  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  MqttService({
    required this.uid,
    this.topic = 'desktop0001',
  });

  Future<bool> connect() async {
    client = MqttServerClient('bemfa.com', uid);
    client.port = 9501;
    client.keepAlivePeriod = 60;
    client.logging(on: false);
    client.autoReconnect = true;

    client.onAutoReconnect = () {
      print('[MQTT] 正在重连...');
      _setConnected(false);
    };
    client.onAutoReconnected = () {
      print('[MQTT] 重连成功');
      _setConnected(true);
    };
    client.onDisconnected = () {
      print('[MQTT] 已断开');
      _setConnected(false);
    };

    try {
      await client.connect();
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        print('[MQTT] 连接成功！topic: $topic');
        _setConnected(true);
        client.subscribe(topic, MqttQos.atMostOnce);

        client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
          final recMess = c[0].payload as MqttPublishMessage;
          final payload = MqttPublishPayload.bytesToStringAsString(
              recMess.payload.message);
          final msg = TelepathyMessage.decode(payload);
          if (msg == null) return;
          // 过滤掉自己发的消息
          if (msg.from == uid) return;
          print('[MQTT] 收到对方消息: $payload');
          _msgController.add(msg);
        });
        return true;
      }
    } catch (e) {
      print('[MQTT] 连接失败: $e');
    }
    _setConnected(false);
    return false;
  }

  void _setConnected(bool value) {
    _isConnected = value;
    _connectionController.add(value);
  }

  void send(TelepathyMessage msg) {
    if (!_isConnected) return;
    final builder = MqttClientPayloadBuilder();
    final encoded = msg.encode(uid);
    builder.addString(encoded);
    client.publishMessage(topic, MqttQos.atMostOnce, builder.payload!);
    print('[MQTT] 发送: $encoded');
  }

  /// 快捷发送动作
  void sendAction(String action) {
    send(TelepathyMessage(type: MsgType.action, data: action));
  }

  /// 发送状态
  void sendStatus(String status) {
    send(TelepathyMessage(type: MsgType.status, data: status));
  }

  /// 发送氛围
  void sendAmbient(String ambient) {
    send(TelepathyMessage(type: MsgType.ambient, data: ambient));
  }

  void dispose() {
    client.disconnect();
    _msgController.close();
    _connectionController.close();
  }
}
