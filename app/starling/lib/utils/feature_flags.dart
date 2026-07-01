/// Compile-time feature flags.
///
/// Used by Plan 11a (libp2p direct-connect tier) and future opt-in transports
/// to gate code paths before the supporting native bridge is shipped. Each
/// call site that depends on libp2p MUST short-circuit on `kLibp2pEnabled`
/// being false so the rest of the app continues to function on LAN + Tor
/// while the bridge is in development.
///
/// Plan 11a has shipped end-to-end (native crate, iOS xcframework, Android
/// .so, Dart FFI bridge, inbound stream server, signaling dispatcher);
/// flipped to `true` 2026-05-23. Manual two-phone smoke test is the next
/// gate before any production users come online.
const bool kLibp2pEnabled = true;

/// Plan 16 — voice chatrooms. Gates the room-manager startup (inbound invite
/// listening) and the voice UI entry points. A kill-switch: the signaling
/// substrate it rides on is always present, so flipping this false simply
/// stops the app from joining/offering calls.
const bool kVoiceEnabled = true;

/// Plan 17 — durable chatrooms. Gates the room lifecycle/messaging services
/// and the chatroom UI entry points. A kill-switch like [kVoiceEnabled]: the
/// storage and sync substrate it rides on is always present, so flipping this
/// false simply hides the durable-room features. Starts false until the Plan
/// 17 test matrix + a two-device smoke test pass.
const bool kChatroomsEnabled = false;
