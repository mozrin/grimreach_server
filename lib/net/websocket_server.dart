import 'dart:io';
import 'package:grimreach_api/message_codec.dart';
import 'package:grimreach_api/messages.dart';
import 'package:grimreach_api/player.dart';
import 'package:grimreach_api/zone.dart';
import 'client_session.dart';

class WebsocketServer {
  final int port;
  final List<ClientSession> sessions = [];
  final MessageCodec _codec = MessageCodec();
  int _nextId = 1;

  WebsocketServer({required this.port});

  Future<void> start() async {
    final httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print("Server running on port $port");

    await for (HttpRequest req in httpServer) {
      if (req.uri.path == '/ws') {
        final socket = await WebSocketTransformer.upgrade(req);

        final id = 'player_$_nextId';
        final zone = _nextId % 2 != 0 ? Zone.safe : Zone.wilderness;
        _nextId++;

        final player = Player(id: id, x: 0, y: 0, zone: zone);
        final session = ClientSession(socket, player);
        sessions.add(session);
        print(
          'Server: Client connected. Assigned ID: $id in Zone: ${zone.name}. Total sessions: ${sessions.length}',
        );

        socket.done.then((_) {
          sessions.remove(session);
          print(
            'Server: Client disconnected. Total sessions: ${sessions.length}',
          );
        });
      } else {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      }
    }
  }

  void broadcast(Message message) {
    if (sessions.isEmpty) return;
    final encoded = _codec.encode(message);
    for (final session in sessions) {
      session.socket.add(encoded);
    }
  }
}
