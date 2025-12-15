import 'dart:io';
import 'package:grimreach_api/message_codec.dart';
import 'package:grimreach_api/player.dart';

class ClientSession {
  final WebSocket socket;
  Player player; // Mutable to allow updates
  final MessageCodec codec = MessageCodec();

  ClientSession(this.socket, this.player) {
    socket.listen(onMessage, onDone: onDisconnect);
  }

  void onMessage(dynamic data) {
    if (data is String) {
      try {
        final message = codec.decode(data);
        print(
          'Server: Received ${message.type} from ${player.id} in ${player.zone.name}',
        );
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
