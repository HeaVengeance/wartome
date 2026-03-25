-- =============================================================================
-- HERO TYPES SCHEMA
-- =============================================================================
-- Models the special hero type classifications in FEH and the effects
-- associated with each type.
--
-- Structure:
--   hero_types          → the type catalog (Legendary, Mythic, Duo, etc.)
--   elements            → seasonal elements (Fire/Water/Wind/Earth/Light/Dark/Astra/Anima)
--   type_effects        → catalog of effects a type provides (shared across types)
--   hero_type_effect_map → junction: which effects does each type have?
--
-- Hero-specific type data (element, duel value, ally boosts) lives in
-- junctions.schema.sql via hero_type_map and hero_ally_boosts, since those
-- tables reference both heroes and hero_types.
--
-- Load order: 4 (after general, heroes, skills — before junctions)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- HERO TYPES
-- The catalog of all special hero type classifications.
-- A hero can have multiple types (e.g. a Legendary Duo hero has both).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hero_types (
    hero_type_id INTEGER PRIMARY KEY,
    name         TEXT    NOT NULL UNIQUE,
    description  TEXT    NOT NULL
);

INSERT INTO hero_types (hero_type_id, name, description) VALUES
    (1,  'Legendary',   'Grants allies stat boosts during their season when allies have matching blessings. Affects Arena scoring.'),
    (2,  'Mythic',      'Grants allies stat boosts in Aether Raids during their season when allies have matching blessings.'),
    (3,  'Chosen',      'Provides merge-based stat boosts and Arena scoring effects during their active season.'),
    (4,  'Duo',         'Has an exclusive Duo Skill usable once per map and a Duel effect for Arena scoring.'),
    (5,  'Harmonized',  'Has an exclusive Harmonized Skill usable once per map and provides Resonant Battles score bonuses.'),
    (6,  'Ascended',    'Provides an Ascendant Floret that grants the unit a second Asset.'),
    (7,  'Aided',       'Provides Aide''s Essence granting +1 to all stats permanently, and access to Aide Accessories.'),
    (8,  'Entwined',    'Allows support ranks up to S+ and provides stat boosts for the unit and its support partner.'),
    (9,  'Rearmed',     'Weapon can be passed to other units via Arcane Inheritance without consuming the hero.'),
    (10, 'Attuned',     'Skills can be passed to other units via Elite Inheritance without consuming the hero.'),
    (11, 'Emblem',      'Grants +1 to all stats per merge (up to +10 total at +10 merges).'),
    (12, 'Dance',       'Can equip Dance and Sing assist skills.')
;


-- -----------------------------------------------------------------------------
-- ELEMENTS
-- Seasonal elements tied to Legendary, Mythic, and Chosen hero types.
--
-- element_group → which hero type category this element belongs to
--   'Legendary' → used by Legendary and Chosen heroes
--   'Mythic'    → used by Mythic heroes
--
-- game_mode → which game mode the element's season affects
--   'Arena'        → Legendary / Chosen (Fire, Water, Wind, Earth)
--   'Aether Raids' → Mythic (Light, Dark, Astra, Anima)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS elements (
    element_id    INTEGER PRIMARY KEY,
    name          TEXT    NOT NULL UNIQUE CHECK (name IN (
                      'Fire', 'Water', 'Wind', 'Earth',
                      'Light', 'Dark', 'Astra', 'Anima'
                  )),
    game_mode     TEXT    NOT NULL CHECK (game_mode IN ('Arena', 'Aether Raids')),
    element_group TEXT    NOT NULL CHECK (element_group IN ('Legendary', 'Mythic'))
);

INSERT INTO elements (element_id, name, game_mode, element_group) VALUES
    (1, 'Fire',  'Arena',        'Legendary'),
    (2, 'Water', 'Arena',        'Legendary'),
    (3, 'Wind',  'Arena',        'Legendary'),
    (4, 'Earth', 'Arena',        'Legendary'),
    (5, 'Light', 'Aether Raids', 'Mythic'),
    (6, 'Dark',  'Aether Raids', 'Mythic'),
    (7, 'Astra', 'Aether Raids', 'Mythic'),
    (8, 'Anima', 'Aether Raids', 'Mythic')
;


-- -----------------------------------------------------------------------------
-- TYPE EFFECTS
-- Catalog of effects that hero types provide. Modeled similarly to
-- skill_effects — defines the PATTERN of an effect, not the hero-specific
-- value (e.g. "grants ally stat boost" without specifying which stats or how
-- much — those live on hero_ally_boosts per hero).
--
-- Effects that are shared across types (e.g. seasonal_stat_boost applies to
-- Legendary, Mythic, and Chosen) are one row here referenced by all three.
--
-- category:
--   'scoring'     → affects score in game modes (Arena, Aether Raids, Resonant)
--   'stat'        → grants or boosts stats
--   'inheritance' → special skill/weapon inheritance mechanics
--   'special_skill' → grants a unique skill slot (Duo, Harmonized)
--   'item'        → grants a single-use item
--   'support'     → modifies support rank or support-related mechanics
--   'assist'      → unlocks or modifies assist skill access
--
-- is_seasonal → effect is only active during the hero's corresponding season
-- game_mode   → which game mode is affected (NULL = all modes / universal)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS type_effects (
    type_effect_id INTEGER PRIMARY KEY,
    name           TEXT    NOT NULL UNIQUE,
    category       TEXT    NOT NULL CHECK (category IN (
                       'scoring', 'stat', 'inheritance',
                       'special_skill', 'item', 'support', 'assist'
                   )),
    is_seasonal    INTEGER NOT NULL DEFAULT 0 CHECK (is_seasonal IN (0, 1)),
    game_mode      TEXT    CHECK (game_mode IN ('Arena', 'Aether Raids', 'Resonant Battles')), -- NULL = universal, bypasses CHECK naturally
    description    TEXT    NOT NULL
);

INSERT INTO type_effects (type_effect_id, name, category, is_seasonal, game_mode, description) VALUES
    -- Shared across Legendary, Mythic, Chosen
    (1,  'seasonal_stat_boost',  'stat',          1, NULL,              'Grants stat boosts to allies with matching blessings during the hero''s active season.'),
    (2,  'ally_stat_boost',      'stat',          1, NULL,              'Boosts specific stats for allies. The stats and magnitude vary per hero (see hero_ally_boosts).'),
    -- Legendary / Chosen
    (3,  'arena_scoring',        'scoring',       0, 'Arena',           'Affects Arena matchmaking and scoring. Duel value overrides the hero''s stat total.'),
    (4,  'pair_up',              'special_skill', 0, NULL,              'Allows the hero to Pair Up with an ally in supported game modes.'),
    -- Mythic
    (5,  'aether_raids_bonus',   'scoring',       1, 'Aether Raids',    'Provides Raiding Party or Defensive Team bonus and call slots in Aether Raids.'),
    -- Chosen-specific
    (6,  'merge_stat_boost',     'stat',          1, NULL,              'Grants stat boosts based on the hero''s merge count in the same order as Dragonflowers.'),
    (7,  'blessed_in_arena',     'scoring',       1, 'Arena',           'Treated as having the blessing of their element type during their active season.'),
    (8,  'arena_combat_boost',   'scoring',       1, 'Arena',           'If unit has weapon-triangle advantage, boosts damage by 20 and reduces damage taken by 20 during combat (excluding AoE Specials).'),
    -- Duo / Harmonized
    (9,  'duo_skill',            'special_skill', 0, NULL,              'Grants an exclusive Duo Skill usable once per map (may be refreshed by Duo''s Indulgence).'),
    (10, 'duel_stat_total',      'scoring',       0, 'Arena',           'Hero is treated as having a specific stat total for Arena matchmaking regardless of actual stats.'),
    (11, 'harmonized_skill',     'special_skill', 0, NULL,              'Grants an exclusive Harmonized Skill usable once per map (may be refreshed by Duo''s Indulgence).'),
    (12, 'resonant_battles_bonus', 'scoring',     0, 'Resonant Battles','Provides bonus points in Resonant Battles based on number deployed and total merges (up to 20).'),
    -- Ascended
    (13, 'second_asset',         'stat',          0, NULL,              'Unit receives an Ascendant Floret (single use) that grants a second Asset stat.'),
    -- Aided
    (14, 'stat_permanent_boost', 'stat',          0, NULL,              'Unit receives Aide''s Essence (single use) granting +1 to all stats permanently.'),
    (15, 'accessory_unlock',     'item',          0, NULL,              'Unit can equip exclusive Aide Accessories.'),
    -- Entwined
    (16, 'support_rank_boost',   'support',       0, NULL,              'Allows support ranks up to S+ (one tier above the standard S rank maximum).'),
    (17, 'support_stat_boost',   'stat',          0, NULL,              'Grants stat boosts to the unit and its support partner.'),
    -- Rearmed / Attuned (same mechanic, different names)
    (18, 'arcane_inheritance',   'inheritance',   0, NULL,              'Hero''s weapon (Arcane weapon) can be passed to other units without consuming the hero.'),
    (19, 'elite_inheritance',    'inheritance',   0, NULL,              'Hero''s skills can be passed to other units without consuming the hero.'),
    -- Emblem
    (20, 'merge_all_stat_boost', 'stat',          0, NULL,              'Grants +1 to all stats per merge, up to +10 total at +10 merges (+2 per stat).'),
    -- Dance
    (21, 'dance_assist_unlock',  'assist',        0, NULL,              'Unit can equip Dance and Sing assist skills, allowing an adjacent ally to move again.')
;


-- -----------------------------------------------------------------------------
-- HERO TYPE EFFECT MAP
-- Junction linking each hero type to the effects all heroes of that type share.
-- Effects that vary per hero (ally boost stats, duel value, element) are stored
-- on hero_type_map and hero_ally_boosts in junctions.schema.sql.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hero_type_effect_map (
    hero_type_id   INTEGER NOT NULL REFERENCES hero_types(hero_type_id)        ON DELETE CASCADE,
    type_effect_id INTEGER NOT NULL REFERENCES type_effects(type_effect_id)    ON DELETE CASCADE,
    PRIMARY KEY (hero_type_id, type_effect_id)
);

-- PK covers (hero_type_id, type_effect_id) — add reverse index for effect → types lookups
CREATE INDEX IF NOT EXISTS idx_hero_type_effect_map_effect ON hero_type_effect_map(type_effect_id);

-- hero_duo_skills is defined in heroes.schema.sql
-- (depends only on heroes — moved there so load order is clean)


INSERT INTO hero_type_effect_map (hero_type_id, type_effect_id) VALUES
    -- Legendary (1): seasonal boost, ally boost, arena scoring
    (1,  1), (1,  2), (1,  3),
    -- Mythic (2): seasonal boost, ally boost, aether raids bonus
    (2,  1), (2,  2), (2,  5),
    -- Chosen (3): seasonal boost, arena scoring, merge stat boost, blessed in arena, arena combat boost
    (3,  1), (3,  3), (3,  6), (3,  7), (3,  8),
    -- Duo (4): duo skill, duel stat total
    (4,  9), (4, 10),
    -- Harmonized (5): harmonized skill, resonant battles bonus
    (5, 11), (5, 12),
    -- Ascended (6): second asset
    (6, 13),
    -- Aided (7): permanent stat boost, accessory unlock
    (7, 14), (7, 15),
    -- Entwined (8): support rank boost, support stat boost
    (8, 16), (8, 17),
    -- Rearmed (9): arcane inheritance
    (9, 18),
    -- Attuned (10): elite inheritance
    (10, 19),
    -- Emblem (11): merge all stat boost
    (11, 20),
    -- Dance (12): dance assist unlock
    (12, 21)
;
