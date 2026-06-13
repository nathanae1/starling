# Pre-existing Flutter test failures on main (not caused by the S1–S7 fixes)

> **Status: FIXED (2026-06-10).** Both modes diagnosed and resolved — see
> "Resolution" at the bottom. Full suite green.

While verifying the Plan 15 security fixes (`15-relay-review-findings.md`,
S1–S7), the full `flutter test` run showed 12 failures. All 12 reproduce on a
clean checkout of `main` (`3f75152`) with the security work stashed — they
predate it. Logged here so they don't get misattributed to the S1–S7 diff and
so the actual break gets fixed on its own track.

## Symptom

12 failures across three files, two distinct failure modes:

1. **Handshake tests throw `FollowFailure(noEndpoints)`** —
   `test/services/follow_service_test.dart` (4 of the 5 handshake tests) and
   `test/services/crypto/key_rotation_e2e_test.dart`
   ("alice removes bob → carol gets new key, bob does not"):

   ```
   FollowFailure(FollowFailureKind.noEndpoints): our onion is not published
   yet — cannot send follow-request
     package:starling/services/follow_service.dart 163:7
   ```

2. **`test/screens/friends/friends_screen_test.dart` hangs, then fails** —
   in the full-suite log one test sat from 20:04 to 30:05 before erroring
   (≈10 min, the per-test timeout); a clean-main run of just this file plus
   the e2e file ran 30 minutes for `+0 -6`. Looks like a pending-timer /
   `pumpAndSettle` hang, not an assertion failure.

## Cause (mode 1 — confirmed)

`f6299c8` ("🐛 bugfixes", 2026-05-11) added a send-time guard to
`FollowService.sendFollowRequest` (`lib/services/follow_service.dart:162-167`):
it refuses to send a follow request when our own endpoints contain no
`type: 'onion'` entry, because the responder persists our card and dials it on
follow-back — an onion-less card permanently poisons the return path. Correct
production behavior.

The test fixtures were never updated: both `_Peer.connectionCard()` helpers
build cards with only

```dart
endpoints: [Endpoint(type: 'direct', address: _hostFromUrl(baseUrl))]
```

(`test/services/follow_service_test.dart:217`,
`test/services/crypto/key_rotation_e2e_test.dart:327`), so every test that
drives `sendFollowRequest` now throws before reaching the fake transport.

## Cause (mode 2 — needs triage)

Not yet diagnosed. The friends-screen widget tests hang rather than assert,
which smells like a real periodic timer leaking into the widget-test zone —
plausibly the same reachability/onion machinery (`PeerReachabilityMonitor` or
a provider that starts probing) introduced around the same commits. Diagnose
separately; don't assume it shares mode 1's cause.

## Suggested fix (mode 1)

Add an onion endpoint to the `_Peer` fixtures, e.g.

```dart
endpoints: [
  Endpoint(type: 'onion', address: '$label.onion:80'),
  Endpoint(type: 'direct', address: _hostFromUrl(baseUrl)),
]
```

and keep the fake transport/reachability monitor resolving the peer via the
existing baseUrl (the guard only inspects *our own* endpoints' types, so the
fake dial path is unaffected). That preserves the production guard while
restoring the tests' intent.

## Resolution (2026-06-10)

All 12 fixed. The count was actually four modes across five files (4
follow_service + 1 key_rotation_e2e + 5 friends_screen + 2 others that the
original triage lumped into the hang):

**Mode 1 (5 tests)** — fixed exactly as suggested below: added an
`Endpoint(type: 'onion', address: '$label.onion:80')` to both `_Peer`
fixtures. The fake transport still dials via baseUrl; the guard only
inspects our own endpoints.

**Mode 2 (5 tests) — the hang was NOT a pending periodic timer.** An
instrumented run showed the test body completes and `pumpAndSettle`
settles fine; the deadlock is in teardown. `addTearDown` runs LIFO, so

```dart
addTearDown(container.dispose);
addTearDown(storage.dispose);
```

ran `MockStorageService.dispose()` *before* `container.dispose()`.
`dispose()` awaited each broadcast `StreamController.close()`, and a
broadcast `close()` only completes once the done event is delivered to
every listener — but the listeners were Riverpod stream subscriptions
created inside the `testWidgets` FakeAsync zone, which stops being pumped
once the test body returns. The done events never deliver, `dispose()`
never completes, and each test sits until the 10-minute `testWidgets`
timeout. Two fixes:

- `friends_screen_test.dart`: swapped the `addTearDown` registration order
  so the container (and its subscriptions) is disposed first.
- `MockStorageService.dispose()`: no longer awaits the `close()` futures
  (`unawaited`), so no future widget test can trip on this again.

**Mode 3 (1 test)** — `connection_card_parser_test.dart` "rejects
non-starling scheme": the Plan 15 parser rework (relay-pair QR support)
changed the rejection message to `'not a starling invite URL'`; the test
still expected the old `'starling://connect'` text. Updated the
expectation.

**Mode 4 (1 test)** — `vectors_test.dart` "vector 4: feed key ratchet":
the finch→starling rename (`2ed6946`) changed the ratchet domain strings
(`finch-ratchet-v1` → `starling-ratchet-v1`, same for msg-key) and the
sample content, but `test/vectors/index.json` was never regenerated.
Regenerated via `flutter test test/vectors/vectors_gen.dart`.

Full suite after fixes: `+385 ~3` (0 failures), ~11s wall clock — the
suite previously ran 30+ minutes because each friends-screen test burned
its 10-minute teardown timeout.

## Verification trail

- Full suite with S1–S7 changes: `+373 -12` (failures listed above).
- `git stash -u` → `flutter test test/services/follow_service_test.dart` on
  clean main: same 4 failures, same `noEndpoints` error.
- `git stash -u` → friends_screen + key_rotation_e2e on clean main:
  `30:00 +0 -6`, same failures/hang.
- All test files touched by the S1–S7 work pass; the only failures in those
  files are the pre-existing handshake ones (e.g. the new
  `removeFollower clears queued card distributions (S4)` test passes in the
  same file where the handshake tests fail).
