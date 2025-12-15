# grimreach_server

The authoritative simulation host for Grimreach.

See also: [Grimreach Design & Architecture](../grimreach_docs/README.md)

## Core Responsibilities
- Owns deterministic world simulation and tick loop
- Maintains global systems and long-cycle state
- Produces authoritative WorldState messages
- Enforces server-side contracts and invariants

## Architectural Role
The single source of truth for the Grimreach universe. It executes the simulation loop, processes incoming client commands, updates the state, and broadcasts the result. It is self-contained and authoritative.

## Deterministic Contract Surface
- Input: `Protocol.handshake`
- Input: `Protocol.move` / `Protocol.chat`
- Output: `WorldState` (Broadcast)
- Output: `Protocol.state`

## Explicit Non-Responsibilities
- No rendering
- No client-side prediction logic (pure authority)

## Folder/Layout Summary
- `bin/`: Entry points.
  - `server.dart`: Main loop and startup.
- `lib/`: Server logic.
  - `net/`: WebSocket handling and session management.

## Development Notes
Run with `dart bin/server.dart`. Must be running for Client or Census to function.
