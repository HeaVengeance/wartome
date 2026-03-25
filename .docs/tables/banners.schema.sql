-- =============================================================================
-- BANNERS SCHEMA
-- =============================================================================
-- Models summoning banners: their type, date range, focus lineup, and the
-- base rates for each pool tier per banner type.
--
-- Structure:
--   banner_types      → lookup table of valid banner type identifiers
--   banner_type_rates → base pull rates per (banner_type, pool_tier)
--   banners           → each banner event (name, type, dates, version, spark)
--   banner_focus      → which heroes are focus units on a given banner
--
-- Hero pool derivation uses columns on heroes (availability, debut_version,
-- pool_4star_special_version, pool_3_4star_version) — see heroes.schema.sql.
-- Pass banner.game_version as the query parameter to reconstruct any historical pool.
--
-- Pool query reference (banner.game_version = V):
--   5★ focus:       banner_focus WHERE banner_id = X
--   5★ off-focus:   availability = '5star_exclusive' AND debut_version < V
--   4★ focus:       banner_focus WHERE banner_id = X AND has_4star_focus = 1
--   4★ special:     pool_4star_special_version <= V
--                   AND (pool_3_4star_version IS NULL OR pool_3_4star_version > V)
--   3-4★ standard:  pool_3_4star_version <= V
--                   (launch-3-4★ heroes must have pool_3_4star_version = debut_version)
--
-- Notes:
--   - '5star_limited' heroes are invisible to all derived pool queries.
--     They only appear via banner_focus.
--   - A veteran focus unit on a non-new-heroes banner satisfies both the focus
--     query AND the off-focus query → double rate. No special casing needed.
--   - New heroes have debut_version = banner.game_version so they are excluded
--     from the off-focus pool on their own debut banner (strict < comparison).
--
-- Load order: 6 (after general, heroes, skills, hero_types, junctions)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- BANNER TYPES
-- Single source of truth for valid banner type identifiers.
-- Both banners and banner_type_rates FK into this table, so adding a new type
-- requires only one INSERT here — both tables pick it up via FK enforcement.
--
-- Without this table, the CHECK list in banners and banner_type_rates would be
-- maintained separately and could silently diverge.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS banner_types (
    banner_type TEXT PRIMARY KEY
);

INSERT INTO banner_types (banner_type) VALUES
    ('new_heroes'),
    ('legendary'),
    ('mythic'),
    ('revival'),
    ('remix'),
    ('seasonal'),
    ('hero_fest'),
    ('special')
;


-- -----------------------------------------------------------------------------
-- BANNER TYPE RATES
-- Base pull rates for each pool tier, keyed by banner type.
-- These are the published rates before pity adjustment.
-- One row per (banner_type, pool_tier) combination — not all combinations exist
-- for every banner type (e.g. 'legendary' has no off-focus pool).
--
-- pool_tier values:
--   '5star_focus'     → featured focus heroes
--   '5star_off_focus' → non-focus 5★ summonables
--   '4star_focus'     → 4★ focus heroes (select banners only)
--   '4star_special'   → demoted heroes not yet in the 3-4★ pool
--   '3_4star'         → standard 3★ and 4★ pool
--
-- Note on 4star_focus (new_heroes / revival / remix / hero_fest):
--   When a banner has 4★ focus units (has_4star_focus = 1 in banner_focus),
--   they pull from the '4star_focus' tier at 3% base rate. This comes from
--   the 3-4★ allocation, which drops from 0.91 → 0.88 on those banners.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS banner_type_rates (
    banner_type TEXT NOT NULL REFERENCES banner_types(banner_type),
    pool_tier   TEXT NOT NULL CHECK (pool_tier IN (
                    '5star_focus', '5star_off_focus',
                    '4star_focus', '4star_special', '3_4star'
                )),
    base_rate   REAL NOT NULL CHECK (base_rate > 0),
    PRIMARY KEY (banner_type, pool_tier)
);

-- New heroes: 3% focus, 3% off-focus, 3% 4★ focus, 3% 4★ special, 88% 3-4★
INSERT INTO banner_type_rates (banner_type, pool_tier, base_rate) VALUES
    ('new_heroes', '5star_focus',     0.03),
    ('new_heroes', '5star_off_focus', 0.03),
    ('new_heroes', '4star_focus',     0.03),
    ('new_heroes', '4star_special',   0.03),
    ('new_heroes', '3_4star',         0.88);

-- Legendary / Mythic: 8% focus, no off-focus pool, 92% 3-4★
INSERT INTO banner_type_rates (banner_type, pool_tier, base_rate) VALUES
    ('legendary', '5star_focus', 0.08),
    ('legendary', '3_4star',     0.92);

INSERT INTO banner_type_rates (banner_type, pool_tier, base_rate) VALUES
    ('mythic', '5star_focus', 0.08),
    ('mythic', '3_4star',     0.92);

-- Revival: same structure as new_heroes (reruns of old new heroes banners)
INSERT INTO banner_type_rates (banner_type, pool_tier, base_rate) VALUES
    ('revival', '5star_focus',     0.03),
    ('revival', '5star_off_focus', 0.03),
    ('revival', '4star_focus',     0.03),
    ('revival', '4star_special',   0.03),
    ('revival', '3_4star',         0.88);

-- Remix: same structure as new_heroes
INSERT INTO banner_type_rates (banner_type, pool_tier, base_rate) VALUES
    ('remix', '5star_focus',     0.03),
    ('remix', '5star_off_focus', 0.03),
    ('remix', '4star_focus',     0.03),
    ('remix', '4star_special',   0.03),
    ('remix', '3_4star',         0.88);

-- Seasonal: 3% focus, no off-focus or 4★ special pool, 97% 3-4★
INSERT INTO banner_type_rates (banner_type, pool_tier, base_rate) VALUES
    ('seasonal', '5star_focus', 0.03),
    ('seasonal', '3_4star',     0.97);

-- Hero Fest: 5% focus, 3% off-focus, 3% 4★ focus, 3% 4★ special, 86% 3-4★
INSERT INTO banner_type_rates (banner_type, pool_tier, base_rate) VALUES
    ('hero_fest', '5star_focus',     0.05),
    ('hero_fest', '5star_off_focus', 0.03),
    ('hero_fest', '4star_focus',     0.03),
    ('hero_fest', '4star_special',   0.03),
    ('hero_fest', '3_4star',         0.86);

-- Special (e.g. anniversary, Feh Pass): 3% focus, 97% 3-4★
INSERT INTO banner_type_rates (banner_type, pool_tier, base_rate) VALUES
    ('special', '5star_focus', 0.03),
    ('special', '3_4star',     0.97);


-- -----------------------------------------------------------------------------
-- BANNERS
-- One row per banner event.
--
-- game_version → the game version when this banner was active.
--   Stored as major * 100 + minor so numeric comparison is correct.
--   Example: v8.10 = 810, v9.0 = 900, v9.3 = 903.
--   Used to derive which heroes were in each pool at that point in time.
--
-- spark_count → number of summons required to trigger the spark (free pick).
--   Default 40. Set to 0 if the banner has no spark mechanic.
--
-- source_banner_id → for rerun banners, the original banner being rerun.
--   NULL for original banners. ON DELETE SET NULL so deleting the original
--   banner doesn't cascade-delete all its reruns.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS banners (
    banner_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    name             TEXT    NOT NULL,
    banner_type      TEXT    NOT NULL REFERENCES banner_types(banner_type),
    start_date       TEXT    NOT NULL CHECK (date(start_date) IS NOT NULL),  -- YYYY-MM-DD
    end_date         TEXT             CHECK (end_date IS NULL OR date(end_date) IS NOT NULL),
    game_version     INTEGER NOT NULL CHECK (game_version > 0),  -- major*100+minor, e.g. v8.10=810
    spark_count      INTEGER NOT NULL DEFAULT 40 CHECK (spark_count >= 0),
    source_banner_id INTEGER REFERENCES banners(banner_id) ON DELETE SET NULL,
    CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_banners_type         ON banners(banner_type);
CREATE INDEX IF NOT EXISTS idx_banners_start_date   ON banners(start_date);
CREATE INDEX IF NOT EXISTS idx_banners_game_version ON banners(game_version);
CREATE INDEX IF NOT EXISTS idx_banners_source       ON banners(source_banner_id);


-- -----------------------------------------------------------------------------
-- BANNER FOCUS
-- Links a banner to its focus heroes.
--
-- has_4star_focus → this hero also appears as a 4★ focus unit on this banner.
--   Most banners: 0. Select new_heroes/revival/remix/hero_fest banners: 1 for
--   chosen heroes. A 4★ focus hero is counted in the '4star_focus' rate tier;
--   at 5★ they still contribute to '5star_focus'. The split is handled at the
--   application query layer.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS banner_focus (
    banner_id       INTEGER NOT NULL REFERENCES banners(banner_id) ON DELETE CASCADE,
    hero_id         INTEGER NOT NULL REFERENCES heroes(hero_id)    ON DELETE CASCADE,
    has_4star_focus INTEGER NOT NULL DEFAULT 0 CHECK (has_4star_focus IN (0, 1)),
    PRIMARY KEY (banner_id, hero_id)
);

-- PK covers (banner_id, hero_id) — add reverse index for hero → banner lookups
CREATE INDEX IF NOT EXISTS idx_banner_focus_hero ON banner_focus(hero_id);
