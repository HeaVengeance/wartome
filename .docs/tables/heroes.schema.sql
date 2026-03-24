CREATE TABLE IF NOT EXISTS heroes (
    hero_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    name           TEXT    NOT NULL,
    epithet        TEXT    NOT NULL,
    weapon_type_id INTEGER NOT NULL REFERENCES weapon_types(weapon_id),
    move_type      TEXT    NOT NULL CHECK (move_type IN ('Infantry', 'Cavalry', 'Armored', 'Flying')),
    release_date   TEXT    NOT NULL, -- YYYY-MM-DD
    description    TEXT    NOT NULL
)


CREATE TABLE IF NOT EXISTS heroes_art (
    art_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    hero_id        INTEGER NOT NULL REFERENCES heroes(hero_id) ON DELETE CASCADE,
    type           TEXT    NOT NULL CHECK (type IN ('Standard', 'Resplendent', 'Removed')),
    portrait_url   TEXT,
    neutral_url    TEXT,
    attack_url     TEXT,
    special_url    TEXT,
    damage_url     TEXT,
    voice_actor_jp TEXT,
    voice_actor_en TEXT,
    artist         TEXT
)


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


CREATE TABLE IF NOT EXISTS hero_skills (
    hero_skill_id  INTEGER PRIMARY KEY AUTOINCREMENT,
    hero_id        INTEGER NOT NULL REFERENCES heroes(hero_id)  ON DELETE CASCADE,
    skill_id       INTEGER NOT NULL REFERENCES skills(skill_id),
    slot           TEXT    NOT NULL CHECK (slot IN (
                       'Weapon', 'Assist', 'Special',
                       'A', 'B', 'C', 'X', 'S'
                   )),
    unlock_rarity  INTEGER NOT NULL CHECK (unlock_rarity BETWEEN 1 AND 5),
    UNIQUE (hero_id, skill_id)
);