-- Preserve-and-forward for Envelope item types (F4). The relay is a
-- zero-knowledge store: it must round-trip an item whose `type` it does not
-- understand, not silently relabel everything "event". Existing rows are all
-- events, so the default backfills correctly.
ALTER TABLE served_events ADD COLUMN item_type TEXT NOT NULL DEFAULT 'event';
