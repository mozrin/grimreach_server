import 'dart:async';
import 'package:grimreach_api/messages.dart';
import 'package:grimreach_api/protocol.dart';
import 'package:grimreach_api/entity.dart';
import 'package:grimreach_api/world_state.dart';
import 'package:grimreach_api/zone.dart';
import 'package:grimreach_api/entity_type.dart';
import 'package:grimreach_server/net/websocket_server.dart';

void main() async {
  final server = WebsocketServer(port: 8080);

  // Start server (this awaits future connections appropriately, but looking at start() impl it awaits 'await for'.
  // However, 'await for' blocks main. So we should run start() in a Future or put tick loop before/concurrently.
  // Actually, await server.start() will block indefinitely. I should put tick loop before await, or not await start() directly if I want code after it.

  // Spawn State
  final entities = <Entity>[];
  int spawnTick = 0;
  const int maxPerZone = 5;
  int nextEntityId = 1;

  print('Server: Starting tick loop...');
  Timer.periodic(Duration(milliseconds: 100), (timer) {
    spawnTick++;

    // Spawn Cycle (every 10 ticks = 1 second)
    if (spawnTick % 10 == 0) {
      // Safe Zone Rule (NPCs)
      final safeCount = entities.where((e) => e.zone == Zone.safe).length;
      if (safeCount < maxPerZone) {
        entities.add(
          Entity(
            id: 'spawn_safe_$nextEntityId',
            zone: Zone.safe,
            type: EntityType.npc,
          ),
        );
        nextEntityId++;
      }

      // Wilderness Rule (Resources)
      final wildCount = entities.where((e) => e.zone == Zone.wilderness).length;
      if (wildCount < maxPerZone) {
        entities.add(
          Entity(
            id: 'spawn_wild_$nextEntityId',
            zone: Zone.wilderness,
            type: EntityType.resource,
          ),
        );
        nextEntityId++;
      }
    }
    final players = server.sessions.map((s) => s.player).toList();
    final state = WorldState(entities: entities, players: players);
    final message = Message(type: Protocol.state, data: state.toJson());
    server.broadcast(message);
  });

  print('Server: Starting HTTP server...');
  await server.start();
}
