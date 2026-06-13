use starling_relay_storage::accounting::{self, CapCheck};
use starling_relay_storage::{
    creds, events, media, owners, pairings, Db, PairedOwner, PendingPairing, ServedEvent,
    ServedMedia,
};

fn owner(pubkey: u8, port: u16) -> PairedOwner {
    PairedOwner {
        pubkey: vec![pubkey; 32],
        label: Some(format!("phone-{pubkey}")),
        paired_at: 1_700_000_000,
        relay_onion_address: format!("owner{pubkey}.onion"),
        local_port: port,
        storage_cap_bytes: None,
    }
}

#[test]
fn migration_creates_schema_and_owner_roundtrips() {
    let db = Db::open_in_memory().unwrap();
    let conn = db.get().unwrap();
    owners::insert(&conn, &owner(1, 17000)).unwrap();
    let got = owners::get(&conn, &[1u8; 32]).unwrap().unwrap();
    assert_eq!(got.local_port, 17000);
    assert_eq!(got.relay_onion_address, "owner1.onion");
    assert_eq!(owners::list(&conn).unwrap().len(), 1);
}

#[test]
fn unique_local_port_is_enforced() {
    let db = Db::open_in_memory().unwrap();
    let conn = db.get().unwrap();
    owners::insert(&conn, &owner(1, 17000)).unwrap();
    // Second owner reusing the same port must fail (UNIQUE constraint).
    assert!(owners::insert(&conn, &owner(2, 17000)).is_err());
}

#[test]
fn delete_owner_cascades_events_and_media() {
    let db = Db::open_in_memory().unwrap();
    let conn = db.get().unwrap();
    owners::insert(&conn, &owner(1, 17000)).unwrap();

    let inserted = events::insert(
        &conn,
        &ServedEvent {
            pubkey: vec![1u8; 32],
            id: "evt1".into(),
            created_at: 100,
            msg_seq: 1,
            nonce: vec![0u8; 24],
            payload: vec![9u8; 16],
        },
    )
    .unwrap();
    assert!(inserted);
    // Re-push is idempotent.
    assert!(!events::insert(
        &conn,
        &ServedEvent {
            pubkey: vec![1u8; 32],
            id: "evt1".into(),
            created_at: 100,
            msg_seq: 1,
            nonce: vec![0u8; 24],
            payload: vec![9u8; 16],
        },
    )
    .unwrap());

    media::insert(
        &conn,
        &ServedMedia {
            pubkey: vec![1u8; 32],
            hash: "a".repeat(64),
            size: 2048,
            created_at: 100,
            path: "aa/aaaa/...".into(),
        },
    )
    .unwrap();

    assert_eq!(events::count(&conn, &[1u8; 32]).unwrap(), 1);
    assert_eq!(media::total_bytes(&conn, &[1u8; 32]).unwrap(), 2048);

    // Unpair → cascade wipes events + media.
    assert_eq!(owners::delete(&conn, &[1u8; 32]).unwrap(), 1);
    assert_eq!(events::count(&conn, &[1u8; 32]).unwrap(), 0);
    assert_eq!(media::total_bytes(&conn, &[1u8; 32]).unwrap(), 0);
}

#[test]
fn manifest_page_is_newest_first_and_bounded() {
    let db = Db::open_in_memory().unwrap();
    let conn = db.get().unwrap();
    owners::insert(&conn, &owner(1, 17000)).unwrap();
    for (i, ts) in [(1, 100i64), (2, 200), (3, 300)] {
        events::insert(
            &conn,
            &ServedEvent {
                pubkey: vec![1u8; 32],
                id: format!("evt{i}"),
                created_at: ts,
                msg_seq: i,
                nonce: vec![0u8; 24],
                payload: vec![0u8; 4],
            },
        )
        .unwrap();
    }
    let page = events::manifest_page(&conn, &[1u8; 32], None, None, None, 1000).unwrap();
    assert_eq!(page.len(), 3);
    assert_eq!(page[0].created_at, 300); // newest first
    assert_eq!(page[2].created_at, 100);

    // Bare `until` keeps the old inclusive semantics: at/below ts=200.
    let older = events::manifest_page(&conn, &[1u8; 32], None, Some(200), None, 1000).unwrap();
    assert_eq!(older.len(), 2);
    assert_eq!(older[0].created_at, 200);

    // payloads_since is chronological.
    let payloads = events::payloads_since(&conn, &[1u8; 32], Some(200), 1000).unwrap();
    assert_eq!(payloads.len(), 2);
}

#[test]
fn manifest_page_keyset_tiebreaker_pages_same_second_losslessly() {
    let db = Db::open_in_memory().unwrap();
    let conn = db.get().unwrap();
    owners::insert(&conn, &owner(1, 17000)).unwrap();
    // Three events sharing one created_at — the case `until = ts - 1`
    // paging skipped — plus a newer one.
    for (id, ts) in [("evtA", 100i64), ("evtB", 100), ("evtC", 100), ("evtD", 200)] {
        events::insert(
            &conn,
            &ServedEvent {
                pubkey: vec![1u8; 32],
                id: id.into(),
                created_at: ts,
                msg_seq: 0,
                nonce: vec![0u8; 24],
                payload: vec![0u8; 4],
            },
        )
        .unwrap();
    }

    // Walk with limit 2 using the keyset cursor; every id must appear
    // exactly once.
    let mut seen = Vec::new();
    let mut until: Option<i64> = None;
    let mut until_id: Option<String> = None;
    loop {
        let page =
            events::manifest_page(&conn, &[1u8; 32], None, until, until_id.as_deref(), 2)
                .unwrap();
        if page.is_empty() {
            break;
        }
        let last = page.last().unwrap();
        until = Some(last.created_at);
        until_id = Some(last.id.clone());
        seen.extend(page.into_iter().map(|r| r.id));
    }
    assert_eq!(seen, vec!["evtD", "evtC", "evtB", "evtA"]);
}

#[test]
fn events_size_accounting_and_combined_usage() {
    let db = Db::open_in_memory().unwrap();
    let conn = db.get().unwrap();
    owners::insert(&conn, &owner(1, 17000)).unwrap();

    for (id, len) in [("evt1", 16usize), ("evt2", 24)] {
        events::insert(
            &conn,
            &ServedEvent {
                pubkey: vec![1u8; 32],
                id: id.into(),
                created_at: 100,
                msg_seq: 0,
                nonce: vec![0u8; 24],
                payload: vec![9u8; len],
            },
        )
        .unwrap();
    }
    media::insert(
        &conn,
        &ServedMedia {
            pubkey: vec![1u8; 32],
            hash: "a".repeat(64),
            size: 60,
            created_at: 100,
            path: "aa/aaaa/...".into(),
        },
    )
    .unwrap();

    assert_eq!(events::total_bytes(&conn, &[1u8; 32]).unwrap(), 40);
    // Owner usage = events + media combined.
    assert_eq!(accounting::owner_usage(&conn, &[1u8; 32]).unwrap(), 100);
    assert_eq!(accounting::host_usage(&conn).unwrap(), 100);
}

#[test]
fn capacity_check_owner_host_and_unlimited() {
    let db = Db::open_in_memory().unwrap();
    let conn = db.get().unwrap();
    owners::insert(&conn, &owner(1, 17000)).unwrap();
    owners::insert(&conn, &owner(2, 17001)).unwrap();
    media::insert(
        &conn,
        &ServedMedia {
            pubkey: vec![1u8; 32],
            hash: "a".repeat(64),
            size: 90,
            created_at: 100,
            path: "aa/aaaa/...".into(),
        },
    )
    .unwrap();

    // Owner cap: 90 used, +10 fits a 100 cap exactly; +11 busts it.
    assert_eq!(
        accounting::check_capacity(&conn, &[1u8; 32], 10, 100, 0).unwrap(),
        CapCheck::Ok
    );
    assert_eq!(
        accounting::check_capacity(&conn, &[1u8; 32], 11, 100, 0).unwrap(),
        CapCheck::OwnerExceeded
    );
    // Host cap counts other owners' bytes: owner 2 has 0 of its own but the
    // host already holds 90.
    assert_eq!(
        accounting::check_capacity(&conn, &[2u8; 32], 11, 0, 100).unwrap(),
        CapCheck::HostExceeded
    );
    assert_eq!(
        accounting::check_capacity(&conn, &[2u8; 32], 10, 0, 100).unwrap(),
        CapCheck::Ok
    );
    // 0 = unlimited on both axes.
    assert_eq!(
        accounting::check_capacity(&conn, &[1u8; 32], i64::MAX / 2, 0, 0).unwrap(),
        CapCheck::Ok
    );
}

#[test]
fn pairing_token_lifecycle() {
    let db = Db::open_in_memory().unwrap();
    let conn = db.get().unwrap();
    let token = vec![7u8; 32];
    pairings::insert(
        &conn,
        &PendingPairing {
            token: token.clone(),
            created_at: 1000,
            expires_at: 1600,
            consumed_at: None,
            created_by: "cli".into(),
            label: None,
        },
    )
    .unwrap();

    assert!(pairings::get(&conn, &token).unwrap().is_some());
    // First consume succeeds, second is a no-op (single-use).
    assert_eq!(pairings::mark_consumed(&conn, &token, 1100).unwrap(), 1);
    assert_eq!(pairings::mark_consumed(&conn, &token, 1200).unwrap(), 0);

    // Prune removes expired tokens.
    assert_eq!(pairings::prune_expired(&conn, 2000).unwrap(), 1);
    assert!(pairings::get(&conn, &token).unwrap().is_none());
}

#[test]
fn consume_all_unconsumed_invalidates_prior_tokens() {
    let db = Db::open_in_memory().unwrap();
    let conn = db.get().unwrap();
    for (seed, consumed_at) in [(1u8, None), (2u8, None), (3u8, Some(900))] {
        pairings::insert(
            &conn,
            &PendingPairing {
                token: vec![seed; 32],
                created_at: 1000,
                expires_at: 1600,
                consumed_at,
                created_by: "web".into(),
                label: None,
            },
        )
        .unwrap();
    }

    // Both live tokens die; the already-consumed one is untouched.
    assert_eq!(pairings::consume_all_unconsumed(&conn, 1100).unwrap(), 2);
    assert_eq!(pairings::mark_consumed(&conn, &[1u8; 32], 1200).unwrap(), 0);
    assert_eq!(pairings::mark_consumed(&conn, &[2u8; 32], 1200).unwrap(), 0);
    assert_eq!(
        pairings::get(&conn, &[3u8; 32]).unwrap().unwrap().consumed_at,
        Some(900)
    );
}

#[test]
fn admin_creds_upsert() {
    let db = Db::open_in_memory().unwrap();
    let conn = db.get().unwrap();
    assert!(creds::get(&conn).unwrap().is_none());
    creds::set(&conn, "argon2hash-v1", 5000).unwrap();
    creds::set(&conn, "argon2hash-v2", 6000).unwrap();
    let got = creds::get(&conn).unwrap().unwrap();
    assert_eq!(got.password_hash, "argon2hash-v2");
    assert_eq!(got.updated_at, 6000);
}
