-- =============================================================================
-- JUNCTIONS SCHEMA
-- =============================================================================
-- All junction tables that cross file boundaries live here.
-- This file must be loaded LAST — after general, heroes, and skills —
-- because every table here references tables defined across those three files.
--
-- Load order:
--   1. general.schema.sql  → weapon_types, origins
--   2. heroes.schema.sql   → heroes, heroes_art, hero_stats
--   3. skills.schema.sql   → effect_types, skill_effects, skills, conditions,
--                            skill_effect_map, skill_effect_conditions,
--                            skill_restrictions
--   4. junctions.schema.sql (this file)
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
