import 'dart:async';
import 'package:grimreach_api/messages.dart';
import 'package:grimreach_api/protocol.dart';
import 'package:grimreach_api/entity.dart';
import 'package:grimreach_api/world_state.dart';
import 'package:grimreach_api/zone.dart';
import 'package:grimreach_api/entity_type.dart';
import 'package:grimreach_api/player.dart';
import 'package:grimreach_server/net/websocket_server.dart';

void main() async {
  final server = WebsocketServer(port: 8080);

  // Start server (this awaits future connections appropriately, but looking at start() impl it awaits 'await for'.
  // However, 'await for' blocks main. So we should run start() in a Future or put tick loop before/concurrently.
  // Actually, await server.start() will block indefinitely. I should put tick loop before await, or not await start() directly if I want code after it.

  // Spawn State
  final entities = <Entity>[];
  final lifetimes = <String, int>{}; // ID -> Remaining Ticks
  final playerDirections = <String, double>{}; // ID -> Direction (1.0 or -1.0)
  int spawnTick = 0;
  const int maxPerZone = 5;
  const int defaultLifetime = 50; // 5 seconds
  int nextEntityId = 1;

  print('Server: Starting tick loop...');
  Timer.periodic(Duration(milliseconds: 100), (timer) {
    spawnTick++;

    // 1. Despawn Cycle
    final expiredIds = <String>[];
    for (final id in lifetimes.keys) {
      lifetimes[id] = lifetimes[id]! - 1;
      if (lifetimes[id]! <= 0) {
        expiredIds.add(id);
      }
    }

    for (final id in expiredIds) {
      entities.removeWhere((e) => e.id == id);
      lifetimes.remove(id);
      print('Server: Despawned entity $id');
    }

    // 2. Spawn Cycle (every 10 ticks = 1 second)
    if (spawnTick % 10 == 0) {
      // Safe Zone Rule (NPCs)
      final safeCount = entities.where((e) => e.zone == Zone.safe).length;
      if (safeCount < maxPerZone) {
        final id = 'spawn_safe_$nextEntityId';
        entities.add(
          Entity(
            id: id,
            x: -5.0,
            y: 0.0,
            zone: Zone.safe,
            type: EntityType.npc,
          ),
        );
        lifetimes[id] = defaultLifetime;
        nextEntityId++;
      }

      // Wilderness Rule (Resources)
      final wildCount = entities.where((e) => e.zone == Zone.wilderness).length;
      if (wildCount < maxPerZone) {
        final id = 'spawn_wild_$nextEntityId';
        entities.add(
          Entity(
            id: id,
            x: 5.0,
            y: 0.0,
            zone: Zone.wilderness,
            type: EntityType.resource,
          ),
        );
        lifetimes[id] = defaultLifetime;
        nextEntityId++;
      }
    }

    // 3. Entity Movement Simulation
    // Since Entity is immutable, we must rebuild the list
    for (int i = 0; i < entities.length; i++) {
      final e = entities[i];

      // Initialize direction if needed (reuse playerDirections logic or separate?)
      // We need a separate map for entities as IDs might collide or just for clarity.
      // But map is String->double so it's fine if IDs are unique.
      // Entity IDs are 'spawn_safe_N', Player IDs 'player_N'. They are unique.
      if (!playerDirections.containsKey(e.id)) {
        // Initial direction: away from center? or right?
        playerDirections[e.id] = 1.0;
      }
      var dir = playerDirections[e.id]!;

      var newX = e.x + (dir * 0.5);
      var newDir = dir;

      if (newX >= 10.0) {
        newDir = -1.0;
        newX = 10.0;
      } else if (newX <= -10.0) {
        newDir = 1.0;
        newX = -10.0;
      }
      playerDirections[e.id] = newDir;

      final newZone = newX < 0 ? Zone.safe : Zone.wilderness;

      if (newX != e.x || newZone != e.zone) {
        entities[i] = Entity(
          id: e.id,
          x: newX,
          y: e.y,
          zone: newZone,
          type: e.type,
        );
      }
    }

    // 4. Player Movement Simulation
    for (final session in server.sessions) {
      final p = session.player;

      // Determine direction
      if (!playerDirections.containsKey(p.id)) {
        playerDirections[p.id] = 1.0;
      }
      final dir = playerDirections[p.id]!;

      // Calculate new state
      var newX = p.x + (dir * 0.5);
      var newDir = dir;

      if (newX >= 10.0) {
        newDir = -1.0;
        newX = 10.0; // Clamp
      } else if (newX <= -10.0) {
        newDir = 1.0;
        newX = -10.0; // Clamp
      }
      playerDirections[p.id] = newDir;

      final newZone = newX < 0 ? Zone.safe : Zone.wilderness;

      // Update Session Player
      session.player = Player(id: p.id, x: newX, y: p.y, zone: newZone);
    }
    final players = server.sessions.map((s) => s.player).toList();
    final state = WorldState(entities: entities, players: players);
    final message = Message(type: Protocol.state, data: state.toJson());
    server.broadcast(message);
  });

  print('Server: Starting HTTP server...');
  await server.start();
}
