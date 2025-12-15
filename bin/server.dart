import 'dart:async';
import 'package:grimreach_api/messages.dart';
import 'package:grimreach_api/protocol.dart';
import 'package:grimreach_api/entity.dart';
import 'package:grimreach_api/world_state.dart';
import 'package:grimreach_api/zone.dart';
import 'package:grimreach_server/net/websocket_server.dart';

void main() async {
  final server = WebsocketServer(port: 8080);

  // Start server (this awaits future connections appropriately, but looking at start() impl it awaits 'await for'.
  // However, 'await for' blocks main. So we should run start() in a Future or put tick loop before/concurrently.
  // Actually, await server.start() will block indefinitely. I should put tick loop before await, or not await start() directly if I want code after it.

  // Option 1: Start tick loop first.
  // Create static entities
  final entities = [
    Entity(id: 'ent_1', zone: Zone.safe),
    Entity(id: 'ent_2', zone: Zone.wilderness),
    Entity(id: 'ent_3', zone: Zone.safe),
  ];

  print('Server: Starting tick loop...');
  Timer.periodic(Duration(milliseconds: 100), (timer) {
    final players = server.sessions.map((s) => s.player).toList();
    final state = WorldState(entities: entities, players: players);
    final message = Message(type: Protocol.state, data: state.toJson());
    server.broadcast(message);
  });

  print('Server: Starting HTTP server...');
  await server.start();
}
