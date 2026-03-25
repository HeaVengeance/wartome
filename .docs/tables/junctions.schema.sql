-- =============================================================================
-- JUNCTIONS SCHEMA
-- =============================================================================
-- All junction tables that cross file boundaries live here.
-- This file must be loaded LAST — after general, heroes, and skills —
-- because every table here references tables defined across those three files.
--
-- Load order:
--   1. general.schema.sql    → weapon_types, origins
--   2. heroes.schema.sql     → heroes, heroes_art, hero_stats, hero_duo_skills
--   3. skills.schema.sql     → effect_types, skill_effects, skills, conditions,
--                              skill_effect_map, skill_effect_conditions,
--                              skill_restrictions
--   4. hero_types.schema.sql → hero_types, elements, type_effects,
--                              hero_type_effect_map
--   5. junctions.schema.sql  (this file)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- HERO ORIGINS
-- A hero can originate from multiple FE games (e.g. a Duo hero spanning two
-- titles). This links heroes to the origins table in general.schema.sql.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hero_origins (
    hero_id   INTEGER NOT NULL REFERENCES heroes(hero_id)   ON DELETE CASCADE,
    origin_id INTEGER NOT NULL REFERENCES origins(origin_id) ON DELETE CASCADE,
    PRIMARY KEY (hero_id, origin_id)
);

-- PK covers (hero_id, origin_id) — add reverse index for origin → heroes lookups
CREATE INDEX IF NOT EXISTS idx_hero_origins_origin ON hero_origins(origin_id);


-- -----------------------------------------------------------------------------
-- HERO SKILLS
-- The default skill kit a hero comes with, broken down by slot and the rarity
-- at which each skill becomes available.
--
-- One row per skill per hero — a hero can have multiple weapons unlocking at
-- different rarities (Iron Sword at 1★, Silver Sword at 3★, Falchion at 5★).
-- Querying the full kit at 4★:
--   WHERE hero_id = X AND unlock_rarity <= 4
--
-- slot          → which slot this skill occupies in the hero's default kit
-- unlock_rarity → the minimum rarity the hero must be to have this skill
--
-- Sacred Seals (S slot) and their A/B counterparts are separate rows in the
-- skills catalog with different slot values — no special handling needed here.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hero_skills (
    hero_skill_id INTEGER PRIMARY KEY AUTOINCREMENT,
    hero_id       INTEGER NOT NULL REFERENCES heroes(hero_id)  ON DELETE CASCADE,
    skill_id      INTEGER NOT NULL REFERENCES skills(skill_id) ON DELETE CASCADE,
    slot          TEXT    NOT NULL CHECK (slot IN (
                      'Weapon', 'Assist', 'Special',
                      'A', 'B', 'C', 'X', 'S'
                  )),
    unlock_rarity INTEGER NOT NULL CHECK (unlock_rarity BETWEEN 1 AND 5),
    UNIQUE (hero_id, skill_id)
);

CREATE INDEX IF NOT EXISTS idx_hero_skills_hero  ON hero_skills(hero_id);
CREATE INDEX IF NOT EXISTS idx_hero_skills_skill ON hero_skills(skill_id);


-- -----------------------------------------------------------------------------
-- SKILL HERO LOCKS
-- Links a prf skill to the specific hero(es) it belongs to.
-- Most prf skills belong to one hero, but some (e.g. variants of the same
-- legendary weapon) may belong to multiple.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS skill_hero_locks (
    skill_id INTEGER NOT NULL REFERENCES skills(skill_id) ON DELETE CASCADE,
    hero_id  INTEGER NOT NULL REFERENCES heroes(hero_id)  ON DELETE CASCADE,
    PRIMARY KEY (skill_id, hero_id)
);

-- PK covers (skill_id, hero_id) — add reverse index for hero → locked skills lookups
CREATE INDEX IF NOT EXISTS idx_skill_hero_locks_hero ON skill_hero_locks(hero_id);


-- -----------------------------------------------------------------------------
-- HERO RELATIONS
-- Links a specific Duo or Harmonized hero to the companion character(s)
-- featured alongside them.
--
-- Links hero → character (not hero → hero) so that any alt of the companion
-- is automatically included. A Duo/Harmonized unit can have multiple companions
-- — each gets its own row.
--
-- Examples:
--   Duo Marth  → Caeda (character)        [1 companion]
--   Harmonized Micaiah & Elincia → Micaiah (character), Elincia (character) [2 companions]
--
-- The companion character is identified via characters.character_id — not by
-- name, so Caeda is Caeda regardless of which alt is being referenced.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hero_relations (
    relation_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    hero_id       INTEGER NOT NULL REFERENCES heroes(hero_id)          ON DELETE CASCADE,
    character_id  INTEGER NOT NULL REFERENCES characters(character_id) ON DELETE CASCADE,
    relation_type TEXT    NOT NULL CHECK (relation_type IN ('duo_companion')),
    UNIQUE (hero_id, character_id, relation_type)
);

CREATE INDEX IF NOT EXISTS idx_hero_relations_hero      ON hero_relations(hero_id);
CREATE INDEX IF NOT EXISTS idx_hero_relations_character ON hero_relations(character_id);


-- -----------------------------------------------------------------------------
-- CHARACTER RELATIONS
-- Stores named relationships between characters (not specific hero entries).
-- Because these link characters rather than heroes, a new alt of either
-- character automatically inherits the relationship.
--
-- parallel    → Different people deliberately designed as echoes of each other
--               across games. Symmetric — store one row, query both directions.
--               (e.g. Caeldori ↔ Cordelia, Rhajat ↔ Tharja)
--
-- name_shared → Same name, entirely unrelated people from different games.
--               Symmetric — surfaces disambiguation in the UI.
--               (e.g. Hilda (FE5) ↔ Hilda (FE16))
--               Note: characters can share a canonical_name — this link makes
--               the disambiguation explicit and queryable.
--
-- possession  → One character inhabits or controls the other within the same
--               story. Symmetric — store one row, query both directions.
--               (e.g. Robin ↔ Grima, Lyon ↔ Fomortiis)
--
-- Symmetry enforcement:
--   character_id < related_character_id is required at insert time.
--   Always put the lower character_id first. Query both columns to find
--   all relations for a given character.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS character_relations (
    char_relation_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    character_id         INTEGER NOT NULL REFERENCES characters(character_id) ON DELETE CASCADE,
    related_character_id INTEGER NOT NULL REFERENCES characters(character_id) ON DELETE CASCADE,
    relation_type        TEXT    NOT NULL CHECK (relation_type IN (
                             'parallel',
                             'name_shared',
                             'possession'
                         )),
    CHECK (character_id < related_character_id),
    UNIQUE (character_id, related_character_id, relation_type)
);

CREATE INDEX IF NOT EXISTS idx_char_relations_character ON character_relations(character_id);
CREATE INDEX IF NOT EXISTS idx_char_relations_related   ON character_relations(related_character_id);


-- -----------------------------------------------------------------------------
-- HERO TYPE MAP
-- Links heroes to their special type classifications.
-- A hero can have multiple types (e.g. a Legendary Duo hero has both).
--
-- Uses a surrogate PK (map_id) so hero_ally_boosts can reference a single
-- column rather than a composite key.
--
-- element_id  → which seasonal element this hero belongs to (nullable —
--               only set for Legendary, Mythic, and Chosen heroes)
-- duel_value  → stat total override for Arena matchmaking (nullable —
--               only set for Duo heroes and Legendary heroes with a Duel effect)
-- has_pair_up → whether this Legendary hero has the Pair Up ability (nullable —
--               only relevant for Legendary heroes)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hero_type_map (
    hero_type_map_id INTEGER PRIMARY KEY AUTOINCREMENT,
    hero_id          INTEGER NOT NULL REFERENCES heroes(hero_id)              ON DELETE CASCADE,
    hero_type_id     INTEGER NOT NULL REFERENCES hero_types(hero_type_id)    ON DELETE CASCADE,
    element_id       INTEGER          REFERENCES elements(element_id) ON DELETE SET NULL,
    duel_value       INTEGER,
    has_pair_up      INTEGER          DEFAULT 0 CHECK (has_pair_up IN (0, 1)),
    -- Pair Up is a Legendary-only ability (hero_type_id = 1). Enforce at DB level.
    CHECK (has_pair_up = 0 OR hero_type_id = 1),
    UNIQUE (hero_id, hero_type_id)
);

CREATE INDEX IF NOT EXISTS idx_hero_type_map_hero ON hero_type_map(hero_id);
CREATE INDEX IF NOT EXISTS idx_hero_type_map_type ON hero_type_map(hero_type_id);


-- -----------------------------------------------------------------------------
-- HERO ALLY BOOSTS
-- The specific stat boosts a Legendary or Mythic hero grants to allies during
-- their active season when allies have matching blessings.
-- One row per stat per hero type entry.
--
-- All Legendary heroes grant HP+3 to allies.
-- All Mythic heroes grant HP+5 to allies.
-- Additional stat boosts vary per hero.
--
-- Example — a Legendary hero with Atk/Spd ally boost:
--   (map_id=X, stat='HP',  magnitude=3)
--   (map_id=X, stat='Atk', magnitude=2)
--   (map_id=X, stat='Spd', magnitude=2)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hero_ally_boosts (
    boost_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    hero_type_map_id INTEGER NOT NULL REFERENCES hero_type_map(hero_type_map_id) ON DELETE CASCADE,
    stat             TEXT    NOT NULL CHECK (stat IN ('HP', 'Atk', 'Spd', 'Def', 'Res')),
    magnitude        INTEGER NOT NULL CHECK (magnitude > 0),
    UNIQUE (hero_type_map_id, stat)
);

CREATE INDEX IF NOT EXISTS idx_hero_ally_boosts_map ON hero_ally_boosts(hero_type_map_id);
