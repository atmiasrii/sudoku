# Backend Test Suite

Comprehensive deterministic backend tests for Sudoku multiplayer.

## Files

- `tests/sudoku.test.js` - Sudoku generator/solver/validation behavior
- `tests/session.test.js` - Session lifecycle and progress validation
- `tests/matchmaking.test.js` - Rating-based queue and range expansion
- `tests/elo.test.js` - ELO correctness and edge cases
- `tests/websocket.test.js` - Two-player socket flow
- `tests/antiCheat.test.js` - Server-side completion board checks
- `tests/reconnect.test.js` - Grace reconnect and timeout forfeit logic
- `tests/integration.test.js` - End-to-end flow + bonus stress checks
- `tests/_socketHarness.js` - Isolated socket test environment with in-memory DB mocks
- `tests/_runner.js` - Lightweight test runner helpers
- `tests/runAllTests.js` - Aggregated fail-fast runner

## Run

From `backend/`:

- `npm run test:all`
- `npm run test:sudoku`
- `npm run test:session:full`
- `npm run test:matchmaking:full`
- `npm run test:elo:full`
- `npm run test:websocket`
- `npm run test:anticheat`
- `npm run test:reconnect`
- `npm run test:integration`

## Notes

- Socket tests use `socket.io-client` and run against an in-process temporary socket server.
- User/game DB calls are mocked with in-memory stores in socket/integration tests for deterministic behavior.
- Tests are fail-fast and print per-test timing and pass/fail output.
- `Suspicious solve detected` logs are expected in tests that complete quickly by design.
