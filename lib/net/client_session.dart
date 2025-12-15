import 'dart:io';
import 'package:grimreach_api/message_codec.dart';

class ClientSession {
  final WebSocket socket;
  final MessageCodec codec = MessageCodec();

  ClientSession(this.socket) {
    socket.listen(onMessage, onDone: onDisconnect);
  }

  void onMessage(dynamic data) {
    if (data is String) {
      try {
        final message = codec.decode(data);
        print('Server: Received ${message.type}');
        // Echo back
        socket.add(codec.encode(message));
      } catch (e) {
        print('Server: Error decoding message: $e');
      }
    }
  }

  void onDisconnect() {
    print('Server: Client disconnected');
  }
}
