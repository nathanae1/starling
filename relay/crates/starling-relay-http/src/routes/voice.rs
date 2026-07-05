//! `POST /voice/rooms` — owner-signed, replace-the-set push of blinded
//! voice slots (Plan 20). The body carries the owner's **complete** slot
//! set; missing slots are deleted (mirrors the Plan 15 best-effort +
//! reconcile push posture). The live SFU registry is updated through the
//! supervisor-wired [`crate::SlotRegistrar`] hook only after the DB write
//! commits.

use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use bytes::Bytes;
use starling_relay_storage::{immediate_tx, voice_slots};
use starling_wire::voice::{VoiceSlotPush, VoiceSlotReceipt};

use super::{cbor_ok, internal, now_secs};
use crate::middleware::verify_owner_request;
use crate::OwnerCtx;

/// Sanity bound on one push; a phone has nowhere near this many rooms.
const MAX_SLOTS: usize = 4096;

pub async fn rooms_handler(
    State(ctx): State<OwnerCtx>,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    if let Err((code, msg)) =
        verify_owner_request(&headers, "POST", "/voice/rooms", &body, &ctx.owner_pubkey)
    {
        return (code, msg).into_response();
    }
    let Some(voice) = ctx.voice.clone() else {
        return (StatusCode::NOT_FOUND, "voice hosting disabled").into_response();
    };
    let Some(push) = VoiceSlotPush::parse(&body) else {
        return (StatusCode::BAD_REQUEST, "malformed slot push").into_response();
    };
    if push.slots.len() > MAX_SLOTS {
        return (StatusCode::BAD_REQUEST, "too many slots").into_response();
    }
    for slot in &push.slots {
        if slot.token_hash.len() != 32 {
            return (StatusCode::BAD_REQUEST, "token_hash must be 32 bytes").into_response();
        }
        if let Some(cap) = slot.max_participants {
            if cap < 2 || cap > voice.max_participants {
                return (StatusCode::BAD_REQUEST, "max_participants out of range")
                    .into_response();
            }
        }
    }

    let pubkey = ctx.owner_pubkey;
    let rows: Vec<(Vec<u8>, Option<u16>)> = push
        .slots
        .iter()
        .map(|s| (s.token_hash.clone(), s.max_participants))
        .collect();
    let count = rows.len() as i64;
    let result = ctx
        .db
        .run(move |conn| {
            let tx = immediate_tx(conn)?;
            voice_slots::replace_set(&tx, &pubkey, &rows, now_secs())?;
            tx.commit()?;
            Ok(())
        })
        .await;
    if let Err(e) = result {
        return internal(e);
    }

    // The DB write is the durable truth; mirror it into the live registry.
    (voice.registrar)(push.slots);

    cbor_ok(VoiceSlotReceipt { slots: count }.to_cbor())
}
