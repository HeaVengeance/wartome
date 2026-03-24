-- =============================================================================
-- SKILLS SCHEMA
-- =============================================================================
-- A skill is broken into its components so we can query relationships between
-- skills, find skills that share effects, and filter by conditions.
--
-- The chain is:
--   skills
--     └── skill_effect_map       (which effects does this skill have?)
--           ├── skill_effects    (what IS the effect — pattern definition)
--           │     └── effect_types (broad category of effect)
--           └── skill_effect_conditions (when does this effect activate?)
--                 └── conditions (the catalog of activation conditions)
--
-- Key design rules:
--   1. skill_effects defines the PATTERN  (stat boost, in combat, targets unit)
--   2. skill_effect_map carries the VALUE (which stat, how much — Atk+6)
--   3. conditions are reusable and linked per effect row, not per skill
--   4. OR conditions share a condition_group; different groups are AND'd
-- =============================================================================


-- -----------------------------------------------------------------------------
-- EFFECT TYPES
-- A reference table so effect_type is never free text.
-- Keeping it as a table (vs CHECK constraint) means adding a new type is just
-- an INSERT — no schema change needed.
--
-- category groups related types so you can query broadly:
--   "all skills with a 'combat' effect" without knowing every type name.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS effect_types (
    effect_type_id INTEGER PRIMARY KEY AUTOINCREMENT,
    name           TEXT    NOT NULL UNIQUE,
    category       TEXT    NOT NULL CHECK (category IN (
                       'stat',       -- stat boosts and penalties
                       'combat',     -- in-combat mechanics (follow-up, counter, etc.)
                       'damage',     -- damage modification
                       'movement',   -- map movement changes
                       'status',     -- granting or inflicting status conditions
                       'special',    -- special charge / cooldown effects
                       'miracle'    -- effects that prevent death
                   ))
);

INSERT INTO effect_types (name, category) VALUES
    -- stat
    ('stat_boost',               'stat'),
    ('stat_penalty',             'stat'),
    -- combat
    ('attack_twice',             'combat'),
    ('guaranteed_followup',      'combat'),
    ('null_followup',            'combat'),
    ('counterattack',            'combat'),   -- Close/Distant Counter
    ('null_counter',             'combat'),   -- Null Close/Distant Counter
    ('desperation',              'combat'),
    ('vantage',                  'combat'),
    ('brave_effect',             'combat'),   -- attacks twice on initiation
    -- damage
    ('damage_boost',             'damage'),
    ('damage_reduction',         'damage'),
    ('true_damage',              'damage'),   -- damage that ignores def/res
    -- movement
    ('pass',                     'movement'), -- move through foes' spaces
    ('warp',                     'movement'), -- teleport to target space
    ('mobility_boost',           'movement'), -- +1 move range
    ('mobility_penalty',         'movement'), -- Gravity, Frozen, etc.
    -- status
    ('status_grant',             'status'),   -- grants a buff status (Potent Follow, etc.)
    ('status_inflict',           'status'),   -- inflicts a debuff (Panic, Guard, etc.)
    ('status_null',              'status'),   -- negates a status
    -- special
    ('special_charge_boost',     'special'),  -- accelerates special cooldown
    ('special_charge_reduction', 'special'),  -- slows foe special cooldown
    ('special_disabled',         'special'),  -- prevents special activation
    -- miracle
    ('miracle',                  'miracle')  -- survive lethal hit with 1 HP
;


-- -----------------------------------------------------------------------------
-- SKILL EFFECTS
-- Defines the PATTERN of an effect — not the specific value.
-- Think of this as a template: "a stat boost, in combat, targeting the unit."
-- The specific stat (+Atk) and magnitude (+6) live on skill_effect_map.
--
-- is_permanent  → always active, no trigger needed (e.g. flat stat boosts)
-- is_in_combat  → only applies during a combat calculation
-- is_status     → grants or inflicts a status condition (has a duration)
--
-- effect_target → who receives the effect
--   Unit, Foe, Ally, All Allies, All Foes, Support Partner
-- effect_area   → spatial range of the effect
--   Self, Adjacent, Within 2, Within 3, Cardinal, Global
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS skill_effects (
    effect_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    effect_type_id INTEGER NOT NULL REFERENCES effect_types(effect_type_id),
    is_permanent   INTEGER NOT NULL DEFAULT 0 CHECK (is_permanent IN (0, 1)),
    is_in_combat   INTEGER NOT NULL DEFAULT 0 CHECK (is_in_combat IN (0, 1)),
    is_status      INTEGER NOT NULL DEFAULT 0 CHECK (is_status IN (0, 1)),
    effect_target  TEXT    NOT NULL CHECK (effect_target IN (
                       'Unit', 'Foe', 'Ally', 'All Allies', 'All Foes', 'Support Partner'
                   )),
    effect_area    TEXT    NOT NULL CHECK (effect_area IN (
                       'Self', 'Adjacent', 'Within 2', 'Within 3', 'Cardinal', 'Global'
                   )),
    description    TEXT    NOT NULL  -- human-readable summary of this effect pattern
);

CREATE INDEX IF NOT EXISTS idx_skill_effects_type ON skill_effects(effect_type_id);


-- -----------------------------------------------------------------------------
-- SKILLS
-- The catalog of every skill in the game.
--
-- slot       → where the skill is equipped
-- is_prf     → locked to specific hero(es), cannot be inherited by anyone else
-- is_inheritable → can be passed to other heroes via inheritance
--   Note: is_prf = 1 always means is_inheritable = 0. Both columns exist
--   because having both makes queries more readable than inferring one from
--   the other (WHERE is_prf = 0 AND is_inheritable = 1 is clearer intent).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS skills (
    skill_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    name           TEXT    NOT NULL,
    slot           TEXT    NOT NULL CHECK (slot IN (
                       'Weapon', 'Assist', 'Special',
                       'A', 'B', 'C', 'S', 'X'
                   )),
    sp_cost        INTEGER,
    description    TEXT    NOT NULL,
    is_prf         INTEGER NOT NULL DEFAULT 0 CHECK (is_prf IN (0, 1)),
    is_inheritable INTEGER NOT NULL DEFAULT 1 CHECK (is_inheritable IN (0, 1)),
    UNIQUE (name, slot)
);


CREATE INDEX IF NOT EXISTS idx_skills_slot ON skills(slot);
CREATE INDEX IF NOT EXISTS idx_skills_name ON skills(name);

-- skill_hero_locks is defined in junctions.schema.sql
-- (depends on both skills and heroes — load order resolved there)


-- -----------------------------------------------------------------------------
-- SKILL RESTRICTIONS
-- For inheritable skills that can't be used by certain unit types.
-- The game shows these as "Cannot be inherited by: Cavalry, Armored" etc.
--
-- restriction_type  → the axis of restriction
-- restriction_value → the specific value being restricted
--
-- Examples:
--   ('move_type',   'Cavalry')   → cavalry units cannot inherit this
--   ('weapon_type', 'Staff')     → staff users cannot inherit this
--   ('color',       'Colorless') → colorless units cannot inherit this
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS skill_restrictions (
    restriction_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    skill_id          INTEGER NOT NULL REFERENCES skills(skill_id) ON DELETE CASCADE,
    restriction_type  TEXT    NOT NULL CHECK (restriction_type IN ('move_type', 'weapon_type', 'color')),
    restriction_value TEXT    NOT NULL,
    CHECK (
        (restriction_type = 'move_type'   AND restriction_value IN ('Infantry', 'Cavalry', 'Armored', 'Flying'))   OR
        (restriction_type = 'weapon_type' AND restriction_value IN ('Sword', 'Lance', 'Axe', 'Staff', 'Tome', 'Bow', 'Dagger', 'Breath', 'Beast')) OR
        (restriction_type = 'color'       AND restriction_value IN ('Red', 'Blue', 'Green', 'Colorless'))
    )
);

CREATE INDEX IF NOT EXISTS idx_skill_restrictions_skill ON skill_restrictions(skill_id);


-- -----------------------------------------------------------------------------
-- CONDITIONS
-- A reusable catalog of activation conditions.
-- Conditions are shared across skills — "HP >= 50%" is one row referenced by
-- every skill that uses that threshold, not duplicated per skill.
--
-- condition_type → what kind of condition this is. Extensible — adding a new
--   type is just an INSERT here, no schema change needed.
--
-- subject  → who the condition is evaluated on (Unit, Foe, Partner, Ally)
-- operator → the comparison operator (>, <, >=, <=, =, within, IS, IS NOT)
-- value    → what is being compared against (50, Res, 2, deployed, S+, etc.)
-- phase    → when in the game loop this is checked
--
-- description → always required as a human-readable fallback for complex
--   conditions that don't fit neatly into subject/operator/value
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conditions (
    condition_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    condition_type TEXT    NOT NULL CHECK (condition_type IN (
                       'hp_threshold',       -- unit/foe HP% above or below X
                       'stat_compare',       -- unit stat vs foe stat (Res > foe Res)
                       'phase',              -- start of player/enemy phase, start of turn
                       'initiated_combat',   -- unit initiated or did not initiate
                       'proximity',          -- unit/ally/foe within X spaces
                       'deployment',         -- partner/ally is or is not on the map
                       'support_rank',       -- support rank with partner (S, S+, A, etc.)
                       'adjacency',          -- unit is adjacent to ally/foe
                       'unit_type',          -- unit is infantry/cavalry/etc.
                       'weapon_type',        -- unit/foe uses a specific weapon type
                       'special_state',      -- special is ready or at X charge
                       'status_active',      -- unit/foe has a specific status
                       'turn_count',         -- current turn number (odd/even, >= X)
                       'ally_count',         -- number of allies within X spaces
                       'consecutive_attacks' -- number of attacks made in current combat
                   )),
    subject        TEXT,    -- Unit, Foe, Partner, Ally (nullable for phase conditions)
    operator       TEXT,    -- >, <, >=, <=, =, within, IS, IS NOT
    value          TEXT,    -- 50 (%), Res, 2 (spaces), deployed, S+, odd, etc.
    phase          TEXT     CHECK (phase IN (
                       'start_of_turn',
                       'start_of_player_phase',
                       'start_of_enemy_phase',
                       'in_combat',
                       'always'
                   )),                         -- nullable: NULL means no phase restriction
    description    TEXT     NOT NULL -- human-readable, always required
);


-- -----------------------------------------------------------------------------
-- SKILL EFFECT MAP
-- The junction that ties a skill to its effects, one row per stat per effect.
--
-- Why one row per stat?
--   Tunnel Vision gives Atk/Spd/Def/Res+9. Storing this as 'Atk/Spd/Def/Res'
--   in a single column makes it impossible to query "all skills that boost Atk."
--   Instead, four rows share the same effect_id with stat = Atk, Spd, Def, Res.
--   Now "all skills that boost Atk by 6+" is a simple WHERE.
--
-- stat       → which stat this row targets (nullable for non-stat effects)
-- magnitude  → the numeric value (+9, x5, etc.) (nullable for binary effects
--              like Pass or Miracle that have no magnitude)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS skill_effect_map (
    map_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    skill_id   INTEGER NOT NULL REFERENCES skills(skill_id)         ON DELETE CASCADE,
    effect_id  INTEGER NOT NULL REFERENCES skill_effects(effect_id) ON DELETE CASCADE,
    stat       TEXT    CHECK (stat IN ('HP', 'Atk', 'Spd', 'Def', 'Res')),
    magnitude  INTEGER, -- the +6, +9, x5 value; NULL for effects with no quantity
    UNIQUE (skill_id, effect_id, stat)
);

CREATE INDEX IF NOT EXISTS idx_skill_effect_map_skill  ON skill_effect_map(skill_id);
CREATE INDEX IF NOT EXISTS idx_skill_effect_map_effect ON skill_effect_map(effect_id);


-- -----------------------------------------------------------------------------
-- SKILL EFFECT CONDITIONS
-- Links conditions to a specific skill-effect row.
-- Conditions are per effect row, not per skill — because the same skill can
-- have Effect A active above 50% HP and Effect B active above 25% HP.
--
-- condition_group → integer used to express OR vs AND logic:
--   Rows sharing the same condition_group are evaluated with OR.
--   Different condition_groups on the same map_id are evaluated with AND.
--
-- Example — Tunnel Vision's "Attack Twice" has three OR'd conditions:
--   (map_id=X, condition_id=1, condition_group=1) → Res > foe's Res
--   (map_id=X, condition_id=2, condition_group=1) → Partner within 2 spaces
--   (map_id=X, condition_id=3, condition_group=1) → S+ Partner deployed
--   All three share condition_group=1, so any one of them is sufficient.
--
-- Example — a skill requiring BOTH above 50% HP AND unit initiated combat:
--   (map_id=Y, condition_id=4, condition_group=1) → HP >= 50%
--   (map_id=Y, condition_id=5, condition_group=2) → unit initiated combat
--   Different groups, so both must be true.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS skill_effect_conditions (
    map_id          INTEGER NOT NULL REFERENCES skill_effect_map(map_id) ON DELETE CASCADE,
    condition_id    INTEGER NOT NULL REFERENCES conditions(condition_id) ON DELETE CASCADE,
    condition_group INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (map_id, condition_id)
);

CREATE INDEX IF NOT EXISTS idx_skill_effect_cond_map       ON skill_effect_conditions(map_id);
CREATE INDEX IF NOT EXISTS idx_skill_effect_cond_condition  ON skill_effect_conditions(condition_id);
