import 'dart:async';
import 'package:grimreach_api/messages.dart';
import 'package:grimreach_api/protocol.dart';
import 'package:grimreach_api/entity.dart';
import 'package:grimreach_api/world_state.dart';
import 'package:grimreach_api/zone.dart';
import 'package:grimreach_api/entity_type.dart';
import 'package:grimreach_api/player.dart';
import 'package:grimreach_server/net/websocket_server.dart';
import 'package:grimreach_server/services/logger_service.dart';

void main() async {
  final server = WebsocketServer(port: 8080);
  final logger = LoggerService();

  // Spawn State
  final entities = <Entity>[];
  final lifetimes = <String, int>{}; // ID -> Remaining Ticks
  final entityDirections = <String, double>{}; // ID -> Direction (1.0 or -1.0)
  int spawnTick = 0;
  const int maxPerZone = 5;
  const int defaultLifetime = 50; // 5 seconds
  int nextEntityId = 1;

  logger.info('Starting tick loop...');
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
      // Fix: Clean up direction state to prevent memory leak
      entityDirections.remove(id);
      logger.info('Despawned entity $id');
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

      // Initialize direction if needed
      if (!entityDirections.containsKey(e.id)) {
        entityDirections[e.id] = 1.0;
      }
      var dir = entityDirections[e.id]!;

      var newX = e.x + (dir * 0.5);
      var newDir = dir;

      if (newX >= 10.0) {
        newDir = -1.0;
        newX = 10.0;
      } else if (newX <= -10.0) {
        newDir = 1.0;
        newX = -10.0;
      }
      entityDirections[e.id] = newDir;

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

      // Use direction stored in session
      final dir = session.direction;

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
      session.direction = newDir;

      final newZone = newX < 0 ? Zone.safe : Zone.wilderness;

      // Update Session Player
      session.player = Player(id: p.id, x: newX, y: p.y, zone: newZone);
    }
    final players = server.sessions.map((s) => s.player).toList();

    // 5. Proximity Detection
    final playerProximityCounts = <String, int>{};
    const double proximityRadius = 3.0;

    for (final p in players) {
      int count = 0;
      for (final e in entities) {
        // Simple Euclidean distance (1D since y is 0 for now, but using general formula)
        final dx = p.x - e.x;
        final dy = p.y - e.y;
        final distanceSquared = dx * dx + dy * dy;
        if (distanceSquared <= proximityRadius * proximityRadius) {
          count++;
        }
      }
      playerProximityCounts[p.id] = count;
    }

    // 6. Cluster Detection (Phase 017)
    final zoneClusterCounts = <String, int>{};
    int largestClusterSize = 0;

    if (entities.isNotEmpty) {
      final visited = <int>{};
      const double clusterRadius = 3.0;

      for (int i = 0; i < entities.length; i++) {
        if (visited.contains(i)) continue;

        // Start a new cluster
        final cluster = <int>{i};
        final queue = <int>[i];
        visited.add(i);

        while (queue.isNotEmpty) {
          final current = queue.removeLast();
          final e1 = entities[current];

          for (int j = 0; j < entities.length; j++) {
            if (visited.contains(j)) continue;

            final e2 = entities[j];
            final dist = (e1.x - e2.x).abs(); // 1D distance for now
            if (dist <= clusterRadius) {
              visited.add(j);
              cluster.add(j);
              queue.add(j);
            }
          }
        }

        // Analyze cluster
        if (cluster.length >= 2) {
          final firstEntity = entities[cluster.first];
          final zoneName = firstEntity.zone.name;
          zoneClusterCounts[zoneName] = (zoneClusterCounts[zoneName] ?? 0) + 1;

          if (cluster.length > largestClusterSize) {
            largestClusterSize = cluster.length;
          }
        }
      }
    }

    final state = WorldState(
      entities: entities,
      players: players,
      playerProximityCounts: playerProximityCounts,
      zoneClusterCounts: zoneClusterCounts,
      largestClusterSize: largestClusterSize,
    );
    final message = Message(type: Protocol.state, data: state.toJson());
    server.broadcast(message);
  });

  logger.info('Starting HTTP server...');
  await server.start();
}
