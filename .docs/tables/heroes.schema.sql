-- -----------------------------------------------------------------------------
-- CHARACTERS
-- The canonical identity of a person across all their hero entries and alts.
-- One row per real character — not per hero entry.
--
-- Why this exists:
--   Heroes can have many alts (Brave, Legendary, seasonal, etc.). Linking alts
--   by hero_id would require creating new relationship rows every time a new
--   alt is released. Instead, every hero points to a character, and the
--   relationship is automatic.
--
-- Disambiguation:
--   Hilda (FE5) and Hilda (FE16) are DIFFERENT characters → two rows here,
--   both named "Hilda" but with different character_ids.
--
-- Same person, different name:
--   Severa and Selena (Fates) are the SAME character → one row here,
--   both hero entries share the same character_id.
--
-- canonical_name → the most recognised name for this character.
--   For Severa/Selena, this would be 'Severa'.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS characters (
    character_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    canonical_name TEXT    NOT NULL,
    description    TEXT
);

CREATE INDEX IF NOT EXISTS idx_characters_name ON characters(canonical_name);


-- availability → which summoning pool (or non-pool category) a hero belongs to.
--   '5star_exclusive' → obtainable only at 5★ via summoning (standard or focus)
--   '5star_limited'   → 5★ only, never in the standard off-focus pool;
--                       only appears via banner_focus on select banners
--   '3_4star'         → demoted into the permanent 3★/4★ standard pool
--   'grail'           → obtainable via Hero Merit / Grails only (not summonable)
--   'story'           → obtainable via story maps / other means (not summonable)
--
-- debut_version → game version when the hero first became available.
--   Stored as major*100+minor (e.g. v8.10 = 810). Used to exclude new heroes
--   from the off-focus pool on their own debut banner (debut_version < banner_version).
--   NULL for grail/story heroes that were never in the summoning pool.
--
-- pool_4star_special_version → version when the hero entered the 4★ special pool
--   (post-5★ exclusive demotion). NULL = not yet demoted or never demoted.
--
-- pool_3_4star_version → version when the hero entered the permanent 3-4★ pool.
--   For heroes that LAUNCHED in the 3-4★ pool (never went through 5★ exclusive),
--   set this to debut_version — do NOT leave it NULL.
--   NULL means the hero has never been in the 3-4★ pool (still 5★ exclusive/limited).
--   This convention is required for historically accurate pool queries:
--   'pool_3_4star_version <= V' handles both launch-3-4★ and demoted heroes
--   correctly across all banner versions without special-casing availability.
CREATE TABLE IF NOT EXISTS heroes (
    hero_id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    character_id              INTEGER          REFERENCES characters(character_id) ON DELETE SET NULL, -- nullable: set when character is known
    name                      TEXT    NOT NULL,
    epithet                   TEXT    NOT NULL,
    weapon_type_id            INTEGER NOT NULL REFERENCES weapon_types(weapon_type_id),
    move_type                 TEXT    NOT NULL CHECK (move_type IN ('Infantry', 'Cavalry', 'Armored', 'Flying')),
    release_date              TEXT    NOT NULL CHECK (date(release_date) IS NOT NULL), -- YYYY-MM-DD
    description               TEXT,
    availability              TEXT    NOT NULL CHECK (availability IN (
                                  '5star_exclusive', '5star_limited', '3_4star', 'grail', 'story'
                              )),
    debut_version             INTEGER,  -- major*100+minor; NULL for grail/story heroes
    pool_4star_special_version INTEGER, -- NULL = not yet in 4★ special pool
    pool_3_4star_version       INTEGER, -- NULL = never been in 3-4★ pool; set to debut_version for launch-3-4★ heroes
    UNIQUE (name, epithet),
    -- Version columns must be non-decreasing when both are set.
    -- Violating this would silently corrupt pool derivation queries.
    CHECK (pool_4star_special_version IS NULL OR debut_version IS NULL
           OR pool_4star_special_version >= debut_version),
    CHECK (pool_3_4star_version IS NULL OR pool_4star_special_version IS NULL
           OR pool_3_4star_version >= pool_4star_special_version),
    -- Grail and story heroes are never summoned — debut_version must be NULL.
    CHECK (availability NOT IN ('grail', 'story') OR debut_version IS NULL)
);

CREATE INDEX IF NOT EXISTS idx_heroes_character    ON heroes(character_id);
CREATE INDEX IF NOT EXISTS idx_heroes_weapon_type  ON heroes(weapon_type_id);
CREATE INDEX IF NOT EXISTS idx_heroes_move_type    ON heroes(move_type);
CREATE INDEX IF NOT EXISTS idx_heroes_name         ON heroes(name);
CREATE INDEX IF NOT EXISTS idx_heroes_release_date ON heroes(release_date);
-- Composite index for pool derivation queries: availability = X AND debut_version < V
CREATE INDEX IF NOT EXISTS idx_heroes_pool ON heroes(availability, debut_version);


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
    artist         TEXT,
    UNIQUE (hero_id, art_type)
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
    UNIQUE (hero_id, rarity, variant),
    CHECK (hp > 0 AND atk > 0 AND spd > 0 AND def > 0 AND res > 0)
);

CREATE INDEX IF NOT EXISTS idx_hero_stats_hero ON hero_stats(hero_id);


-- -----------------------------------------------------------------------------
-- HERO DUO SKILLS
-- Stores the Duo or Harmonized skill for a hero. These are NOT equippable
-- skills — they cannot be inherited and are permanently tied to one hero.
-- They occupy the Duo/Harmonized button on the unit UI, separate from the
-- standard skill slots.
--
-- One row per hero (a hero can only have one Duo or Harmonized skill).
-- The distinction between Duo and Harmonized is derived from hero_type_map
-- in junctions.schema.sql.
--
-- Duo Skills        → can affect any ally
-- Harmonized Skills → affect allies sharing the hero's game origins.
--                     A Harmonized hero has 2 origins in hero_origins.
--                     The app filters eligible allies from those origins —
--                     no extra column needed here.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hero_duo_skills (
    duo_skill_id INTEGER PRIMARY KEY AUTOINCREMENT,
    hero_id      INTEGER NOT NULL UNIQUE REFERENCES heroes(hero_id) ON DELETE CASCADE,
    name         TEXT    NOT NULL,
    description  TEXT    NOT NULL
);

-- idx_hero_duo_skills_hero omitted: UNIQUE on hero_id already creates an implicit index in SQLite.


-- hero_skills is defined in junctions.schema.sql
-- (depends on both heroes and skills — load order resolved there)