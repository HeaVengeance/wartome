CREATE TABLE IF NOT EXISTS heroes (
    hero_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    name           TEXT    NOT NULL,
    epithet        TEXT    NOT NULL,
    weapon_type_id INTEGER NOT NULL REFERENCES weapon_types(weapon_id),
    move_type      TEXT    NOT NULL CHECK (move_type IN ('Infantry', 'Cavalry', 'Armored', 'Flying')),
    release_date   TEXT    NOT NULL, -- YYYY-MM-DD
    description    TEXT,
    UNIQUE (name, epithet)
);

CREATE INDEX IF NOT EXISTS idx_heroes_weapon_type ON heroes(weapon_type_id);


CREATE TABLE IF NOT EXISTS heroes_art (
    art_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    hero_id        INTEGER NOT NULL REFERENCES heroes(hero_id) ON DELETE CASCADE,
    art_type       TEXT    NOT NULL CHECK (art_type IN ('Standard', 'Resplendent', 'Removed')),
    portrait_url   TEXT,
    neutral_url    TEXT,
    attack_url     TEXT,
    special_url    TEXT,
    damage_url     TEXT,
    voice_actor_jp TEXT,
    voice_actor_en TEXT,
    artist         TEXT
);

CREATE INDEX IF NOT EXISTS idx_heroes_art_hero ON heroes_art(hero_id);


CREATE TABLE IF NOT EXISTS hero_stats (
    stat_id  INTEGER PRIMARY KEY AUTOINCREMENT,
    hero_id  INTEGER NOT NULL REFERENCES heroes(hero_id) ON DELETE CASCADE,
    rarity   INTEGER NOT NULL CHECK (rarity BETWEEN 1 AND 5),
    variant  TEXT    NOT NULL CHECK (variant IN ('Flaw', 'Neutral', 'Asset')),
    hp       INTEGER NOT NULL,
    atk      INTEGER NOT NULL,
    spd      INTEGER NOT NULL,
    def      INTEGER NOT NULL,
    res      INTEGER NOT NULL,
    UNIQUE (hero_id, rarity, variant)
);

CREATE INDEX IF NOT EXISTS idx_hero_stats_hero ON hero_stats(hero_id);


-- hero_skills is defined in junctions.schema.sql
-- (depends on both heroes and skills — load order resolved there)