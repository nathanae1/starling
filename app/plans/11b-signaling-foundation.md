# Plan 11b — Signaling Foundation

Handoff doc. Completes the networking substrate that Plan 16 (voice
chatrooms) builds on, and fixes the iOS link bugs uncovered by today's
first `pod install` after Plan 11a shipped the libp2p direct tier.

Plan 11a is done end-to-end (native crate, iOS xcframework, Android .so,
Dart FFI bridge, inbound stream server, `SignalingDispatcher` scaffold,
flag flipped). But it left two layers inert in production:

1. The signaling plane is mock-only. `signalingServiceProvider` returns
   `MockSignalingService`; the shelf `/ws/signal` handler is unmounted;
   `WsSignalingService.connect()` calls `LanNetworkService.connectToPeer`
   which throws `UnimplementedError`. Result: Plan 11a's
   `Libp2pUpgrader.tryUpgrade` cannot actually deliver the coordination
   message, and Plan 16 voice rooms have no transport for SDP/ICE.
2. The iOS pod link is broken. `pod install` issues two warnings that
   silently drop both arti and libp2p `-force_load` flags; without them
   the linker dead-strips every FFI symbol and `dlsym(lp_init)` returns
   NULL at app start.

Both must land before voice rooms (or any production libp2p signaling)
can work. Decisions confirmed: bundle the iOS fixes in, and apply uniform
`EphemeralEncryptedEvent` encryption to every signaling message
(including Plan 11a's `libp2pConnect`) so the dispatcher's decrypt path
is consistent.

Voice service / WebRTC code (Plan 16 Phases B+) stays out of scope. This
plan delivers only the signaling substrate.

## Status snapshot

**Done in Plan 11a:**
- `SignalingDispatcher` class registered as the single owner of
  `SignalingService.onInboundConnection`.
- `signalingDispatcherProvider` keepAlive in `sync_provider.dart`.
- `LifecycleManager.start()` calls `dispatcher.start()` behind
  `kLibp2pEnabled`.
- `Libp2pUpgrader.handleInboundLibp2pConnect(channel, message)` exists
  and the dispatcher routes `libp2pConnect` messages to it.

**Not done — what this doc covers:**

| # | Task                                                | Blocking? | Where |
|---|-----------------------------------------------------|-----------|-------|
| 1 | iOS CocoaPods link fixes (filename + xcconfig merge) | Yes (iOS only) | `native/libp2p_bridge/`, `app/starling/ios/` |
| 2 | `CryptoService.deriveSignalingKey` + ephemeral AEAD | Yes | `lib/services/crypto/` |
| 3 | Signaling envelope helpers (wrap / unwrap)          | Yes | `lib/services/signaling/signaling_envelope.dart` (new) |
| 4 | Update `Libp2pUpgrader` to wrap outbound + verify inbound | Yes | `lib/sync/libp2p_upgrader.dart` |
| 5 | Update `SignalingDispatcher` to decrypt              | Yes | `lib/services/signaling/signaling_dispatcher.dart` |
| 6 | Refactor `WsSignalingService.connect` to use `PeerConnectionFactory` | Yes | `lib/services/signaling/ws_signaling_service.dart` |
| 7 | Mount shelf `/ws/signal`; bind real `WsSignalingService` | Yes | `lib/server/http_server.dart`, `lib/main.dart` |
| 8 | Widen dispatcher startup gate (drop `kLibp2pEnabled`)| Yes | `lib/services/lifecycle/lifecycle_manager.dart` |

Each task lists representative paths, not exhaustive line numbers. Read
this next to `11a-libp2p-direct-remaining.md` for transport context.

---

## #1 iOS CocoaPods link fixes

**Bug a — `-l<name>` filename mismatch.** CocoaPods derives the link
library name from the xcframework basename (`libp2p_bridge.xcframework`)
and strips a leading `lib`, producing `-l"p2p_bridge"`. The linker then
searches for `libp2p_bridge.a`, but the actual archive inside the
xcframework is `liblibp2p_bridge.a` (cargo prepends `lib` to its
`[lib] name = "libp2p_bridge"`). Verified by inspecting
`Pods-Runner.debug.xcconfig` after `pod install`: `OTHER_LDFLAGS`
contains `-l"p2p_bridge"`, no path matches.

Fix: rename the cargo output. The crate's package name stays
`libp2p_bridge`; only the artifact name changes.

```toml
# native/libp2p_bridge/Cargo.toml
[lib]
name = "p2p_bridge"          # was "libp2p_bridge"
crate-type = ["staticlib", "cdylib"]
```

Cargo will produce `libp2p_bridge.a` / `libp2p_bridge.so`. Downstream
edits:

- `native/libp2p_bridge/build.sh` — every reference to
  `liblibp2p_bridge.{a,so}` → `libp2p_bridge.{a,so}`.
- `app/starling/lib/services/libp2p/ffi_bindings.dart` —
  `DynamicLibrary.open('liblibp2p_bridge.so')` →
  `DynamicLibrary.open('libp2p_bridge.so')`.
- `app/starling/ios/libp2p_bridge.podspec` — drop the
  `user_target_xcconfig` block entirely (bug b moves it). The
  `vendored_frameworks` line is unchanged.
- Rebuild via `./build.sh all`. Confirm
  `app/starling/ios/Runner/libp2p_bridge.xcframework/ios-arm64/libp2p_bridge.a`
  and `app/starling/android/app/src/main/jniLibs/{arm64-v8a,x86_64}/libp2p_bridge.so`
  exist. Delete the stale `liblibp2p_bridge.so` files in `jniLibs/` if
  present (cargo-ndk leaves them).

**Bug b — `OTHER_LDFLAGS[sdk=...]` merge conflict.** Both
`arti_bridge.podspec` and the original `libp2p_bridge.podspec` set
`user_target_xcconfig['OTHER_LDFLAGS[sdk=iphoneos*]']` /
`[sdk=iphonesimulator*]`. CocoaPods treats per-SDK conditionals as
singular settings; when two pods supply different values, **both** are
silently dropped. `pod install` warns:

```
[!] Can't merge user_target_xcconfig for pod targets: ["arti_bridge",
"libp2p_bridge"]. Singular build setting OTHER_LDFLAGS[sdk=iphoneos*]
has different values.
```

Generated `Pods-Runner.debug.xcconfig` confirms neither `-force_load`
landed.

Fix: remove `user_target_xcconfig` from both podspecs, and inject the
`-force_load` flags from `ios/Podfile`'s `post_install` hook directly
onto the Runner xcodeproj (bypassing the Pods-Runner aggregate xcconfig
where the singular-merge check happens). Sketch:

```ruby
# ios/Podfile, inside post_install do |installer| ... end
installer.aggregate_targets.each do |aggregate|
  next unless aggregate.name == 'Pods-Runner'
  aggregate.user_project.targets.each do |t|
    next unless t.name == 'Runner'
    t.build_configurations.each do |config|
      existing = Array(config.build_settings['OTHER_LDFLAGS'] || '$(inherited)')
      config.build_settings['OTHER_LDFLAGS'] = existing + [
        '-force_load "$(SRCROOT)/Runner/arti_bridge.xcframework/$(ARTI_SLICE)/libarti_bridge.a"',
        '-force_load "$(SRCROOT)/Runner/libp2p_bridge.xcframework/$(LIBP2P_SLICE)/libp2p_bridge.a"',
      ]
      config.build_settings['ARTI_SLICE[sdk=iphoneos*]']        = 'ios-arm64'
      config.build_settings['ARTI_SLICE[sdk=iphonesimulator*]']  = 'ios-arm64_x86_64-simulator'
      config.build_settings['LIBP2P_SLICE[sdk=iphoneos*]']       = 'ios-arm64'
      config.build_settings['LIBP2P_SLICE[sdk=iphonesimulator*]']= 'ios-arm64_x86_64-simulator'
    end
    aggregate.user_project.save
  end
end
```

The `$(<SLICE>)` indirection keeps `OTHER_LDFLAGS` itself a plain array
— CocoaPods' singular-setting check fires on the conditional key, not
on the resolved value.

**Acceptance:** `pod install` runs clean (no `Can't merge` warnings).
`xcodebuild -workspace ios/Runner.xcworkspace -target Runner
-showBuildSettings | grep force_load` lists **both** `arti_bridge.a`
and `libp2p_bridge.a`. `flutter build ios --no-codesign --debug`
links. On-device boot, a one-shot debug print confirms
`Libp2pBindings.load()` succeeds.

---

## #2 Pairwise signaling key + ephemeral AEAD

Plan 16 §Encryption pins the derivation:
`crypto_kdf(X25519_DH(my_sk, their_pk), ctx="starlingsig", info=my_pk || their_pk)`.
The existing follow-key path (`PairwiseContentKeyService` /
`SodiumCryptoService.deriveSharedKey`) is the same shape with
`ctx="starlingfk"`; reuse the primitives, swap the salt.

Add to `lib/services/crypto_service.dart` (and `SodiumCryptoService`,
`MockCryptoService`):

```dart
/// Plan 16 — derives the 32-byte pairwise signaling key. Distinct from
/// the feed-key derivation (different ctx); cannot accidentally collide.
Uint8List deriveSignalingKey({
  required Uint8List mySecretKey,   // 64-byte Ed25519 sk
  required Uint8List theirPubkey,   // 32-byte Ed25519 pk
});

/// XChaCha20-Poly1305 over a pairwise signaling key. Nonce is 24 bytes.
Uint8List encryptEphemeral({
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List plaintext,
});

Uint8List decryptEphemeral({
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List ciphertext,
});
```

`SodiumCryptoService` already has `skToCurve25519`, `deriveSharedKey`
(line 171), and XChaCha20-Poly1305 helpers; `deriveSignalingKey` is a
~10-line wrapper.

**Acceptance:** round-trip unit test in
`test/services/sodium_crypto_service_test.dart`: derive key on both
sides from a matched keypair pair, encrypt with one key + nonce, decrypt
with the other, expect equality. Negative: wrong recipient sk → throws.

---

## #3 Signaling envelope helpers

New `lib/services/signaling/signaling_envelope.dart`:

```dart
/// Wrap a [SignalingMessage] in [EphemeralEncryptedEvent] using the
/// pairwise signaling key. Caller passes their identity + the recipient's
/// pubkey (base32 string is decoded via crockfordBase32Decode).
Uint8List wrapSignalingMessage({
  required CryptoService crypto,
  required SignalingMessage message,
  required String myPubkey,
  required Uint8List mySecretKey,
  required String recipientPubkey,
});

/// Inverse: CBOR-decode envelope, verify it's addressed to us, derive
/// pairwise key, decrypt, parse inner SignalingMessage, enforce the ±30s
/// replay window (same constant the WS upgrade handler uses,
/// signaling_handler.dart:45). Throws [SignalingEnvelopeException] on
/// any check failure so the dispatcher can log + drop.
SignalingMessage unwrapSignalingMessage({
  required CryptoService crypto,
  required Uint8List envelopeBytes,
  required String myPubkey,
  required Uint8List mySecretKey,
});
```

Re-uses `crockfordBase32Decode` (`lib/services/crypto/crockford_base32.dart`)
to convert pubkey strings to bytes for DH. `EphemeralEncryptedEvent`
already has `toBytes` / `fromBytes`
(`lib/models/ephemeral_encrypted_event.dart`).

**Acceptance:** new `test/services/signaling_envelope_test.dart` —
wrap → unwrap round-trip; tamper a payload byte → throws;
recipient_pubkey mismatch → throws; expired timestamp → throws.

---

## #4 Update `Libp2pUpgrader` to encrypt

In `lib/sync/libp2p_upgrader.dart`:

- Constructor: inject `crypto: CryptoService` and
  `localSecretKeyLookup: Future<Uint8List?> Function()`. The pubkey is
  already available via `_localPubkeyLookup`.
- Outbound (`_sendConnectMessage` / `_attemptUpgrade`): build the
  `SignalingMessage(type: libp2pConnect, ...)` as today, then call
  `wrapSignalingMessage` and pass envelope bytes to `channel.send`.
- Replying side (`_respondToInbound`): same — wrap the response
  SignalingMessage before send.
- "Await reply with matching nonce" path inside `_attemptUpgrade`:
  replace `SignalingMessage.fromBytes(bytes)` with
  `unwrapSignalingMessage(bytes, …)`. Catch `SignalingEnvelopeException`
  and treat as failure (next pump retries).

`handleInboundLibp2pConnect(channel, message)` signature is unchanged —
the dispatcher hands us an already-decrypted message.

Update `libp2pUpgraderProvider` in `lib/providers/sync_provider.dart` to
pass the new deps (mirror `_loadSecretKey` at `sync_provider.dart:160`).

---

## #5 Update `SignalingDispatcher` to decrypt

In `lib/services/signaling/signaling_dispatcher.dart`:

- Constructor: add `crypto`, `localPubkey`, `localSecretKey`.
- Inside the per-channel `channel.messages.listen` callback: replace
  `SignalingMessage.fromBytes(bytes)` with
  `unwrapSignalingMessage(bytes, …)`. On
  `SignalingEnvelopeException`, log + drop (do not throw — a malformed
  envelope must not tear the channel).

Update `signalingDispatcherProvider` in `lib/providers/sync_provider.dart`
to pass the new deps.

---

## #6 Refactor `WsSignalingService.connect` to use `PeerConnectionFactory`

`LanNetworkService.connectToPeer` throws `UnimplementedError`
unconditionally, so the current `WsSignalingService.connect`'s
`await network.connectToPeer(peer)` call has never worked in production.

Swap the dep:

```dart
class WsSignalingService implements SignalingService {
  WsSignalingService({
    required this.crypto,
    required PeerConnectionFactory peerFactory,   // was: NetworkService
    required this.localPubkey,
    required this.localSecretKey,
  });

  @override
  Future<SignalingChannel> connect(ConnectionCard peer) async {
    final conn = await peerFactory.connectionFor(peer.pubkey);
    if (conn == null) {
      throw StateError('no reachable transport for ${peer.pubkey}');
    }
    if (conn.transport == PeerTransport.libp2pDirect) {
      // Signaling rides LAN HTTP or Tor onion — libp2p is bootstrapped
      // *by* signaling, not used *for* signaling. Fall through to
      // whichever HTTP-style transport bestConnectionFor would pick if
      // we asked it to exclude libp2p. Today the monitor doesn't have
      // an exclude API; in practice the libp2pDirect transport is only
      // promoted after upgrade, so this branch is rare on the cold
      // initiator path.
      throw StateError(
        'signaling cannot ride libp2p for ${peer.pubkey} — '
        'wait for next reachability tick',
      );
    }
    // Existing logic from here: build ws/wss URI from conn.baseUrl,
    // include auth headers, return WebSocketSignalingChannel.
    // ...
  }
}
```

The original `NetworkService` field can be removed; the only consumer
was `connectToPeer`.

---

## #7 Mount `/ws/signal` and bind production `WsSignalingService`

**Mount the shelf route.** Today `_buildSocialRouter` in
`lib/server/http_server.dart` has no signaling endpoint. Add a
`/ws/signal` route and a thread for the inbound-channel callback.

Pattern (same `Lookup` indirection used today for `followService` at
`http_server.dart:198`):

```dart
factory StarlingHttpServer.social({
  ...
  required CryptoService crypto,
  required void Function(SignalingChannel) signalingInboundHandler,
}) { ... }

// inside _buildSocialRouter:
router.get('/ws/signal', signalingHandler(
  crypto: crypto,
  onChannel: signalingInboundHandler,
));
```

In `lib/providers/server_provider.dart`, supply
`signalingInboundHandler: (channel) {
  final svc = ref.read(signalingServiceProvider);
  if (svc is WsSignalingService) svc.handleInbound(channel);
}`.

**Bind production `WsSignalingService`.** Mirror the pattern used today
for `contentKeyServiceProvider` (`main.dart:124-133`) — override the
provider in `main.dart` once identity + secret key are loaded:

```dart
// after identity + secretKey load in main.dart
overrides.add(
  signalingServiceProvider.overrideWithValue(
    WsSignalingService(
      crypto: crypto,
      peerFactory: PeerConnectionFactory(monitor: /* deferred — see below */),
      localPubkey: identity.pubkey,
      localSecretKey: secretKey,
    ),
  ),
);
```

The `PeerConnectionFactory` needs the reachability monitor, which is
constructed inside a provider. Two options:

a. **Lazy lookup** (recommended). Define a `Future<PeerConnection?>
Function(String)` typedef in `WsSignalingService` instead of a direct
`PeerConnectionFactory`. main.dart constructs the service with a closure
that does `(pubkey) => ref.read(peerConnectionFactoryProvider).connectionFor(pubkey)`.
This avoids initializing the factory before the ProviderScope exists.

b. **Move the construction into a `@Riverpod` provider** that reads
identity + secret key inside the provider body. Same shape, but the
provider becomes `FutureProvider<SignalingService>` which ripples to
every consumer (Libp2pUpgrader, SignalingDispatcher). Avoid.

Go with (a).

---

## #8 Widen `SignalingDispatcher` startup gate

In `lib/services/lifecycle/lifecycle_manager.dart::start()`, the
dispatcher is currently behind `if (kLibp2pEnabled)`. Voice rooms need
signaling regardless of libp2p. Widen:

```dart
// Was:
// if (kLibp2pEnabled) {
//   ref.read(signalingDispatcherProvider).start();
// }
// New:
ref.read(signalingDispatcherProvider).start();
```

The dispatcher's own `_started` flag makes it idempotent across resume
events.

---

## Verification

Each step is independently runnable; do not block on any one if it
hangs.

1. **iOS link.** `cd app/starling/ios && pod install` runs clean.
   `xcodebuild ... -showBuildSettings | grep force_load` shows both
   `libarti_bridge.a` and `libp2p_bridge.a`. `flutter build ios
   --no-codesign --debug` links.
2. **Symbol resolution.** Boot the app once on device with a
   throwaway `developer.log` after `Libp2pBindings.load()`. Confirm no
   `dlsym` error.
3. **Crypto + envelope unit tests.** `flutter test
   test/services/sodium_crypto_service_test.dart
   test/services/signaling_envelope_test.dart` (note: prior session
   reported tests hanging; run targeted, don't await the full suite).
4. **`flutter analyze`** stays clean (no new warnings/errors).
5. **Two-phone signaling smoke (LAN).** Phone A and Phone B follow
   each other on the same WiFi. A taps Sync. Filter
   `developer.log` by `libp2p_upgrader` and watch for
   `libp2p upgrade ok pubkey=...`. This proves the full path:
   `/ws/signal` mounted → WS upgrade authed → encrypted envelope
   round-tripped → libp2pConnect dispatched → DCUtR coordinated →
   ping handshake succeeded.

If step 5 succeeds, voice rooms (Plan 16 Phase B) can begin: the
dispatcher's `default` branch in
`lib/services/signaling/signaling_dispatcher.dart` is where room /
SDP / ICE message types attach.

---

## Files of interest

| Concern | Path |
|---|---|
| Plan | `app/plans/16-voice-chatrooms.md` |
| Predecessor | `app/plans/11a-libp2p-direct-remaining.md` |
| Native crate | `app/starling/native/libp2p_bridge/` |
| iOS podspecs | `app/starling/ios/{arti,libp2p}_bridge.podspec`, `Podfile` |
| Crypto | `app/starling/lib/services/crypto/sodium_crypto_service.dart` |
| Signaling envelope (new) | `app/starling/lib/services/signaling/signaling_envelope.dart` |
| WS signaling | `app/starling/lib/services/signaling/ws_signaling_service.dart` |
| Shelf handler | `app/starling/lib/server/handlers/signaling_handler.dart` |
| Dispatcher | `app/starling/lib/services/signaling/signaling_dispatcher.dart` |
| Upgrader | `app/starling/lib/sync/libp2p_upgrader.dart` |
| Server router | `app/starling/lib/server/http_server.dart` |
| Providers | `app/starling/lib/providers/{service_providers,sync_provider,server_provider}.dart` |
| Lifecycle | `app/starling/lib/services/lifecycle/lifecycle_manager.dart` |
| App entry | `app/starling/lib/main.dart` |

## Out of scope

- Plan 16 Phase B (`VoiceService` / `flutter_webrtc`) — separate plan.
- Plan 16 Phase C+ (room state, UI) — separate plans.
- Replacing `MockNetworkService` with a real binding in `main.dart` —
  the abstract `networkServiceProvider` has no consumers in the current
  tree (grep-confirmed); skip.
- Persistent storage of inbound signaling channels across app restart —
  channels are session-scoped per Plan 16 §Ephemeral Events.
