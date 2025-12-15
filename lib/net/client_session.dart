import 'dart:io';
import 'package:grimreach_api/message_codec.dart';
import 'package:grimreach_api/player.dart';
import 'package:grimreach_server/services/logger_service.dart';

class ClientSession {
  final WebSocket socket;
  Player player; // Mutable to allow updates
  final MessageCodec codec = MessageCodec();
  final _logger = LoggerService();
  double direction = 1.0; // Movement direction

  ClientSession(this.socket, this.player) {
    socket.listen(onMessage, onDone: onDisconnect, onError: onError);
  }

  void onMessage(dynamic data) {
    if (data is String) {
      try {
        final message = codec.decode(data);
        _logger.info(
          'Received ${message.type} from ${player.id} in ${player.zone.name}',
        );
        // Echo back
        socket.add(codec.encode(message));
      } catch (e) {
        _logger.error('Error decoding message: $e');
      }
    }
  }

  void onDisconnect() {
    _logger.info('Client disconnected: ${player.id}');
  }

  void onError(dynamic error) {
    _logger.error('Socket error for ${player.id}: $error');
  }
}
