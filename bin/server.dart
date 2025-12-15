import 'dart:async';
import 'package:grimreach_api/messages.dart';
import 'package:grimreach_api/protocol.dart';
import 'package:grimreach_api/entity.dart';
import 'package:grimreach_api/world_state.dart';
import 'package:grimreach_api/zone.dart';
import 'package:grimreach_api/entity_type.dart';
import 'package:grimreach_api/player.dart';
import 'package:grimreach_api/faction.dart';
import 'package:grimreach_server/net/websocket_server.dart';
import 'package:grimreach_server/services/logger_service.dart';

void main() async {
  final server = WebsocketServer(port: 8080);
  final logger = LoggerService();

  // Spawn State
  final entities = <Entity>[];
  final lifetimes = <String, int>{}; // ID -> Remaining Ticks
  final entityDirections = <String, double>{}; // ID -> Direction (1.0 or -1.0)
  // Phase 021: Persistent Influence Map
  final zoneInfluence = <String, Map<Faction, double>>{};
  for (final zone in Zone.values) {
    zoneInfluence[zone.name] = {
      Faction.neutral: 0.0,
      Faction.order: 0.0,
      Faction.chaos: 0.0,
    };
  }
  // Phase 022: Zone Control Persistence
  final zoneControl = <String, Faction>{};
  for (final zone in Zone.values) {
    zoneControl[zone.name] = Faction.neutral;
  }
  // Phase 023: Faction Morale  // Persistent State (Phase 023)
  final factionMorale = <Faction, double>{
    Faction.neutral: 50.0,
    Faction.order: 50.0,
    Faction.chaos: 50.0,
  };

  // Persistent State (Phase 025)
  final factionPressure = <Faction, double>{
    Faction.neutral: 50.0,
    Faction.order: 50.0,
    Faction.chaos: 50.0,
  };
  final zoneSpawnCooldowns = <Zone, int>{Zone.safe: 0, Zone.wilderness: 0};
  final zoneCooldowns = <String, int>{}; // Zone -> Ticks remaining
  final zoneSaturation = <String, String>{
    Zone.safe.name: 'normal',
    Zone.wilderness.name: 'normal',
  };

  const int maxPerZone = 20;
  const int defaultLifetime = 50; // 5 seconds
  int nextEntityId = 1;

  logger.info('Starting tick loop...');
  Timer.periodic(Duration(milliseconds: 100), (timer) {
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

    // 2. Spawn Cycle (Pressure-Driven Phase 025)

    // Decrement Cooldowns
    zoneSpawnCooldowns.updateAll((key, value) => value > 0 ? value - 1 : 0);

    // Safe Zone Rule (NPCs) -> Faction Order
    if (zoneSpawnCooldowns[Zone.safe]! <= 0) {
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
            faction: Faction.order,
          ),
        );
        lifetimes[id] = defaultLifetime;
        nextEntityId++;

        // Set Cooldown based on Order Pressure
        double pressure = factionPressure[Faction.order] ?? 50.0;
        double mult = 0.5 + (pressure / 100.0); // 0.5 to 1.5

        // Saturation Check
        String saturation = zoneSaturation[Zone.safe.name] ?? 'normal';
        if (saturation == 'overcrowded') {
          // Suppress spawn, but maybe reset cooldown slightly to check again soon?
          // Or just don't spawn and keep cooldown 0?
          // If we don't spawn, cooldown stays 0, will check next tick.
          // But we want to suppress. So we assume we "failed" to spawn.
          // Let's set a short cooldown to avoid checking every tick if crowded
          zoneSpawnCooldowns[Zone.safe] = 10;
          logger.info('Spawn Suppressed (Safe Zone Overcrowded)');
        } else {
          // Spawn Proceed
          final id = 'spawn_safe_$nextEntityId';
          entities.add(
            Entity(
              id: id,
              x: -5.0,
              y: 0.0,
              zone: Zone.safe,
              type: EntityType.npc,
              faction: Faction.order,
            ),
          );
          lifetimes[id] = defaultLifetime;
          nextEntityId++;

          int delay = (20 / mult).round();
          if (saturation == 'crowded') {
            delay *= 2; // Slow down
            logger.info('Spawn Slowed (Safe Zone Crowded)');
          }
          zoneSpawnCooldowns[Zone.safe] = delay;
          logger.info(
            'Spawned Safe Entity (Order). Pressure: $pressure, Next in $delay ticks',
          );
        }
      }
    }

    // Wilderness Rule (Resources) -> Faction Chaos
    if (zoneSpawnCooldowns[Zone.wilderness]! <= 0) {
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
            faction: Faction.chaos,
          ),
        );
        lifetimes[id] = defaultLifetime;
        nextEntityId++;

        // Set Cooldown based on Chaos Pressure
        double pressure = factionPressure[Faction.chaos] ?? 50.0;
        double mult = 0.5 + (pressure / 100.0); // 0.5 to 1.5

        // Saturation Check
        String saturation = zoneSaturation[Zone.wilderness.name] ?? 'normal';
        if (saturation == 'overcrowded') {
          zoneSpawnCooldowns[Zone.wilderness] = 10;
          logger.info('Spawn Suppressed (Wilderness Overcrowded)');
        } else {
          final id = 'spawn_wild_$nextEntityId';
          entities.add(
            Entity(
              id: id,
              x: 5.0,
              y: 0.0,
              zone: Zone.wilderness,
              type: EntityType.resource,
              faction: Faction.chaos,
            ),
          );
          lifetimes[id] = defaultLifetime;
          nextEntityId++;

          int delay = (20 / mult).round();
          if (saturation == 'crowded') {
            delay *= 2;
            logger.info('Spawn Slowed (Wilderness Crowded)');
          }
          zoneSpawnCooldowns[Zone.wilderness] = delay;
          logger.info(
            'Spawned Wilderness Entity (Chaos). Pressure: $pressure, Next in $delay ticks',
          );
        }
      }
    }

    // 3. Entity Grouping & Migration (Phase 018)
    // We group by Type and Proximity
    final entityGroups = <int, int>{}; // Entity Index -> Group ID
    final groupVelocities = <int, double>{}; // Group ID -> Direction
    int nextGroupId = 1;

    // Detect Groups
    final visitedForGrouping = <int>{};
    const double groupRadius = 2.0;

    for (int i = 0; i < entities.length; i++) {
      if (visitedForGrouping.contains(i)) continue;

      final group = <int>[i];
      final queue = <int>[i];
      visitedForGrouping.add(i);

      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        final currentEntity = entities[current];

        for (int j = 0; j < entities.length; j++) {
          if (visitedForGrouping.contains(j)) continue;

          final otherEntity = entities[j];
          // Rule: Must be SAME TYPE
          if (currentEntity.type != otherEntity.type) continue;

          final dist = (currentEntity.x - otherEntity.x).abs();
          if (dist <= groupRadius) {
            visitedForGrouping.add(j);
            group.add(j);
            queue.add(j);
          }
        }
      }

      if (group.length >= 2) {
        final groupId = nextGroupId++;
        for (final index in group) {
          entityGroups[index] = groupId;
        }
        // Deterministic Migration Pattern: ID based direction (even=right, odd=left)
        groupVelocities[groupId] = groupId % 2 == 0 ? 0.3 : -0.3;
      }
    }

    // 4. Entity Movement (Updated for Migration)
    // Since Entity is immutable, we must rebuild the list
    for (int i = 0; i < entities.length; i++) {
      final e = entities[i];

      // Default movement or Group Migration?
      // Use Group Velocity if in a group, otherwise individual wander
      var dir = 0.0;

      if (entityGroups.containsKey(i)) {
        // Group Migration
        dir = groupVelocities[entityGroups[i]] ?? 0.0; // Should exist
        // No "cleanup" needed for groupVelocities as they are recalculated every tick
      } else {
        // Individual Wander (Phase 016 logic)
        if (!entityDirections.containsKey(e.id)) {
          entityDirections[e.id] = 1.0;
        }
        dir = entityDirections[e.id]! * 0.5; // Scale to match previous speed
      }

      var newX = e.x + dir;

      // Bounds check - if hit bounds, bounce individual or group?
      // For groups, if one hits, what happens? "Simple" -> check individually
      // If individual wander, we flip direction.
      // If group migration, we flip direction?
      // To keep it simple and deterministic: We just bounce the position calculation.
      // Modifying the velocity map for the next tick would require state persistence.
      // Phase 018 requirements say "recomputed every tick". So pure function of ID/Type?
      // If simply bouncing X, we don't need persistent group state.

      if (newX >= 10.0) {
        newX = 10.0;
        if (!entityGroups.containsKey(i)) entityDirections[e.id] = -1.0;
      } else if (newX <= -10.0) {
        newX = -10.0;
        if (!entityGroups.containsKey(i)) entityDirections[e.id] = 1.0;
      }

      // NOTE: For persistent wandering bouncing to work, we need to update entityDirections.
      // For groups, since we re-determine groups every tick, the velocity is re-calculated based on ID.
      // A pure ID-based velocity won't bounce nicely (it will stick to wall).
      // However, "determinism" requirement allows stateless logic.
      // Better: "Groups move according to a deterministic pattern".
      // Let's stick to simple ID-based velocity for groups. If they hit wall, they stick.
      // Individual logic remains as is.

      final newZone = newX < 0 ? Zone.safe : Zone.wilderness;

      if (newX != e.x || newZone != e.zone) {
        entities[i] = Entity(
          id: e.id,
          x: newX,
          y: e.y,
          zone: newZone,
          type: e.type,
          faction: e.faction, // Propagate faction
        );
      }
    }

    // Calc grouping stats
    final groupCount = nextGroupId - 1;
    final totalGroupedEntities = entityGroups.length;
    final avgGroupSize = groupCount > 0
        ? totalGroupedEntities / groupCount
        : 0.0;

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
      session.player = Player(
        id: p.id,
        x: newX,
        y: p.y,
        zone: newZone,
        faction: p.faction, // Propagate
      );
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

    // 7. Zone Influence & Control (Phase 022)
    final recentShifts = <String>{};

    // Prepare counters: Zone Name -> Faction -> Count
    final presence = <String, Map<Faction, int>>{};

    // Initialize zones
    for (final zone in Zone.values) {
      presence[zone.name] = {
        Faction.neutral: 0,
        Faction.order: 0,
        Faction.chaos: 0,
      };
    }

    // Count Entities
    for (final e in entities) {
      presence[e.zone.name]?[e.faction] =
          (presence[e.zone.name]?[e.faction] ?? 0) + 1;
    }

    // Count Players
    for (final p in players) {
      presence[p.zone.name]?[p.faction] =
          (presence[p.zone.name]?[p.faction] ?? 0) + 1;
    }

    // 7. Zone Influence & Control (Phase 022) with Modifiers (Phase 024)
    final factionGainMult = <Faction, double>{};
    final factionDecayMult = <Faction, double>{};

    // Calculate Modifiers based on Morale
    factionMorale.forEach((faction, morale) {
      double ratio = morale / 100.0;
      factionGainMult[faction] = 0.5 + ratio; // 0.5 to 1.5
      factionDecayMult[faction] = 1.5 - ratio; // 1.5 to 0.5
    });

    // Exposed Map for WorldState
    final factionInfluenceModifiers = Map<Faction, double>.from(
      factionGainMult,
    );

    zoneInfluence.forEach((zoneName, factionScores) {
      final factionCounts =
          presence[zoneName]!; // Should exist per initialization

      // A. Update Influence Scores (Gain/Decay)
      factionScores.keys.toList().forEach((faction) {
        final count = factionCounts[faction] ?? 0;

        final gainMult = factionGainMult[faction] ?? 1.0;
        final decayMult = factionDecayMult[faction] ?? 1.0;

        double gain = count * 1.0 * gainMult;
        double decay = 0.1 * decayMult;

        double newScore = factionScores[faction]! + gain - decay;
        if (newScore > 100.0) newScore = 100.0;
        if (newScore < 0.0) newScore = 0.0;

        factionScores[faction] = newScore;
      });

      // B. Evaluate Zone Control
      if ((zoneCooldowns[zoneName] ?? 0) > 0) {
        zoneCooldowns[zoneName] = zoneCooldowns[zoneName]! - 1;
      } else {
        // Find Top 2 Factions
        var entries = factionScores.entries.toList();
        entries.sort((a, b) => b.value.compareTo(a.value)); // Descending

        final top = entries[0];
        final runnerUp = entries.length > 1 ? entries[1] : null;

        final maxScore = top.value;
        final secondScore = runnerUp?.value ?? 0.0;

        // Rules: Threshold 50, Lead 20
        if (maxScore >= 50.0 && (maxScore - secondScore) >= 20.0) {
          final currentOwner = zoneControl[zoneName];
          final newOwner = top.key;

          if (currentOwner != newOwner) {
            // FLIP!
            zoneControl[zoneName] = newOwner;
            recentShifts.add(zoneName);
            // Set Cooldown (5 seconds = 50 ticks)
            zoneCooldowns[zoneName] = 50;

            logger.info(
              'Zone Flip: $zoneName taken by ${newOwner.name} (Score: ${maxScore.toStringAsFixed(1)})',
            );
          }
        }
      }
    });

    // 8. Faction Morale (Phase 023)
    factionMorale.forEach((faction, score) {
      // Gain: +0.5 per controlled zone
      int controlledZones = 0;
      zoneControl.forEach((k, v) {
        if (v == faction) controlledZones++;
      });

      double gain = controlledZones * 0.5;
      double decay = 0.05;

      double newScore = score + gain - decay;
      if (newScore > 100.0) newScore = 100.0;
      if (newScore < 0.0) newScore = 0.0;

      factionMorale[faction] = newScore;
    });

    // 9. Faction Pressure (Phase 025)
    factionPressure.forEach((faction, score) {
      if (faction == Faction.neutral) {
        return;
      } // Neutral doesn't build pressure usually? Or 50 constant?

      double morale = factionMorale[faction] ?? 50.0;
      double gain = (morale / 100.0) * 0.5; // Up to +0.5
      double decay = 0.2; // Constant drain

      double newScore = score + gain - decay;
      if (newScore > 100.0) {
        newScore = 100.0;
      }
      if (newScore < 0.0) {
        newScore = 0.0;
      }

      factionPressure[faction] = newScore;
    });

    // 10. Zone Saturation (Phase 026)
    for (final zoneName in Zone.values.map((z) => z.name)) {
      final zone = Zone.values.firstWhere((z) => z.name == zoneName);
      int count = entities.where((e) => e.zone == zone).length;
      Faction owner = zoneControl[zoneName] ?? Faction.neutral;
      double pressure = factionPressure[owner] ?? 50.0;

      // Calculate Thresholds driven by Pressure
      // Base: Crowded 10, Limit 20.
      // Mod: ((Pressure - 50) / 5).round() -> -10 to +10.
      int mod = ((pressure - 50.0) / 5.0).round();
      int effectiveLimit = 20 + mod;
      int effectiveCrowded = 10 + mod;

      // Safety Clamp
      if (effectiveLimit < 10) effectiveLimit = 10;
      if (effectiveCrowded < 5) effectiveCrowded = 5;

      String state = 'normal';
      if (count >= effectiveLimit) {
        state = 'overcrowded';
      } else if (count >= effectiveCrowded) {
        state = 'crowded';
      }

      zoneSaturation[zoneName] = state;
    }

    final state = WorldState(
      entities: entities,
      players: players,
      playerProximityCounts: playerProximityCounts,
      zoneClusterCounts: zoneClusterCounts,
      largestClusterSize: largestClusterSize,
      groupCount: groupCount,
      averageGroupSize: avgGroupSize,
      zoneControl: zoneControl,
      zoneInfluence: zoneInfluence,
      recentShifts: recentShifts,
      factionMorale: factionMorale,
      factionPressure: factionPressure,
      factionInfluenceModifiers: factionInfluenceModifiers,
      zoneSaturation: zoneSaturation,
    );
    final message = Message(type: Protocol.state, data: state.toJson());
    server.broadcast(message);
  });

  logger.info('Starting HTTP server...');
  await server.start();
}
