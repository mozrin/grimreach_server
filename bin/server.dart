import 'package:grimreach_api/world_state.dart';

void main() {
  final state = WorldState(entities: [], players: []);
  print(
    'Server: API linked. State created with ${state.players.length} players.',
  );
}
