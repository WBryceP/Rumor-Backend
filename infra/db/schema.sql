-----------------------------------------------------------
-- 0. Extensions & helper objects
-----------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-----------------------------------------------------------
-- 1. ENUM types
-----------------------------------------------------------
CREATE TYPE user_role   AS ENUM ('admin', 'host', 'guest_list_contributor');
CREATE TYPE user_status AS ENUM ('active', 'inactive', 'suspended');
CREATE TYPE rsvp_status AS ENUM ('pending', 'approved', 'rejected');

-----------------------------------------------------------
-- 2. Users
-----------------------------------------------------------
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email       VARCHAR(255) NOT NULL UNIQUE,
    password    BYTEA        NOT NULL, -- Argon2 / PBKDF2 hash bytes
    role        user_role    NOT NULL,
    status      user_status  NOT NULL DEFAULT 'active',
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW(),
    modified_at TIMESTAMP    NOT NULL DEFAULT NOW(),
    modified_by UUID,
    CONSTRAINT fk_user_modified_by FOREIGN KEY (modified_by) REFERENCES users(id)
);

-----------------------------------------------------------
-- 3. Guests
-----------------------------------------------------------
CREATE TABLE guests (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    full_name   VARCHAR(255) NOT NULL,
    email       VARCHAR(255) NOT NULL UNIQUE,
    phone_number VARCHAR(50),
    instagram_handle VARCHAR(100),
    social_follower_count INT,
    engagement_score      REAL,
    created_by  UUID NOT NULL REFERENCES users(id),
    created_at  TIMESTAMP NOT NULL DEFAULT NOW(),
    modified_at TIMESTAMP NOT NULL DEFAULT NOW(),
    modified_by UUID REFERENCES users(id),
    deleted_at  TIMESTAMP -- soft‑delete marker
);

-----------------------------------------------------------
-- 4. Tags & guest‑tag join
-----------------------------------------------------------
CREATE TABLE tags (
    id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE guest_tags (
    id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    guest_id UUID NOT NULL REFERENCES guests(id) ON DELETE CASCADE,
    tag_id   UUID NOT NULL REFERENCES tags(id)   ON DELETE CASCADE,
    UNIQUE (guest_id, tag_id)
);

-----------------------------------------------------------
-- 5. Events
-----------------------------------------------------------
CREATE TABLE events (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title       VARCHAR(255) NOT NULL,
    description TEXT,
    event_date  TIMESTAMP NOT NULL,
    created_by  UUID NOT NULL REFERENCES users(id),
    created_at  TIMESTAMP NOT NULL DEFAULT NOW(),
    modified_at TIMESTAMP NOT NULL DEFAULT NOW(),
    modified_by UUID REFERENCES users(id),
    deleted_at  TIMESTAMP
);

-----------------------------------------------------------
-- 6. RSVPs
-----------------------------------------------------------
CREATE TABLE rsvps (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    guest_id    UUID NOT NULL REFERENCES guests(id),
    host_id     UUID NOT NULL REFERENCES users(id),
    event_id    UUID NOT NULL REFERENCES events(id),
    status      rsvp_status NOT NULL DEFAULT 'pending',
    additional_guests INT NOT NULL DEFAULT 0 CHECK (additional_guests >= 0),
    source      VARCHAR(100),
    notes       TEXT,
    modified_at TIMESTAMP NOT NULL DEFAULT NOW(),
    modified_by UUID REFERENCES users(id),
    UNIQUE (guest_id, event_id)
);

-----------------------------------------------------------
-- 7. Generic audit log (covers any entity)
-----------------------------------------------------------
CREATE TABLE audit_logs (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entity_type TEXT      NOT NULL, -- e.g. 'guest', 'rsvp'
    entity_id   UUID      NOT NULL,
    changed_by  UUID      NOT NULL REFERENCES users(id),
    changed_at  TIMESTAMP NOT NULL DEFAULT NOW(),
    old_val     JSONB,
    new_val     JSONB
);

-----------------------------------------------------------
-- 8. House‑keeping triggers
-----------------------------------------------------------
CREATE OR REPLACE FUNCTION set_modified_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.modified_at := NOW();
    RETURN NEW;
END;
$$;

-- Attach the trigger to every mutating table that has modified_at keeping everything synced
CREATE TRIGGER trg_users_set_modified
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_modified_at();

CREATE TRIGGER trg_guests_set_modified
BEFORE UPDATE ON guests
FOR EACH ROW EXECUTE FUNCTION set_modified_at();

CREATE TRIGGER trg_events_set_modified
BEFORE UPDATE ON events
FOR EACH ROW EXECUTE FUNCTION set_modified_at();

CREATE TRIGGER trg_rsvps_set_modified
BEFORE UPDATE ON rsvps
FOR EACH ROW EXECUTE FUNCTION set_modified_at();

-----------------------------------------------------------
-- 9. Useful indexes
-----------------------------------------------------------
-- For common filters
CREATE INDEX idx_guests_status_follower ON guests (engagement_score, social_follower_count);
CREATE INDEX idx_rsvps_pending ON rsvps (event_id) WHERE status = 'pending';
