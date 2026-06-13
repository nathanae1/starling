-- Event payload byte accounting (D4): caps cover events + media combined,
-- and a SUM(LENGTH(payload)) per push would scan up to cap-sized tables.
ALTER TABLE served_events ADD COLUMN size INTEGER NOT NULL DEFAULT 0;
UPDATE served_events SET size = LENGTH(payload);
