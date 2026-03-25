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
    skill_effect_id INTEGER PRIMARY KEY AUTOINCREMENT,
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
    description    TEXT    NOT NULL,  -- human-readable summary of this effect pattern
    -- prevent duplicate effect patterns — same structural columns = same effect
    UNIQUE (effect_type_id, is_permanent, is_in_combat, is_status, effect_target, effect_area)
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
    weapon_type_id INTEGER REFERENCES weapon_types(weapon_type_id),
    sp_cost        INTEGER,
    description    TEXT    NOT NULL,
    is_prf         INTEGER NOT NULL DEFAULT 0 CHECK (is_prf IN (0, 1)),
    is_inheritable INTEGER NOT NULL DEFAULT 1 CHECK (is_inheritable IN (0, 1)),
    -- weapon skills must declare their weapon type; non-weapon skills must not
    CHECK (
        (slot = 'Weapon' AND weapon_type_id IS NOT NULL) OR
        (slot != 'Weapon' AND weapon_type_id IS NULL)
    ),
    UNIQUE (name, slot)
);

CREATE INDEX IF NOT EXISTS idx_skills_weapon_type ON skills(weapon_type_id);


CREATE INDEX IF NOT EXISTS idx_skills_slot ON skills(slot);
CREATE INDEX IF NOT EXISTS idx_skills_name ON skills(name);

-- skill_hero_locks is defined in junctions.schema.sql
-- (depends on both skills and heroes — load order resolved there)


-- -----------------------------------------------------------------------------
-- SKILL MOVE RESTRICTIONS
-- Which move types cannot inherit a given skill.
-- One row per (skill, move_type) pair.
--
-- Example: a skill restricted to Infantry and Flying only would have two rows:
--   (skill_id=X, move_type='Cavalry')
--   (skill_id=X, move_type='Armored')
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS skill_move_restrictions (
    skill_id  INTEGER NOT NULL REFERENCES skills(skill_id) ON DELETE CASCADE,
    move_type TEXT    NOT NULL CHECK (move_type IN ('Infantry', 'Cavalry', 'Armored', 'Flying')),
    PRIMARY KEY (skill_id, move_type)
);

-- PK covers (skill_id, move_type) — add reverse index for move_type → skills lookups
CREATE INDEX IF NOT EXISTS idx_skill_move_restr_move ON skill_move_restrictions(move_type);


-- -----------------------------------------------------------------------------
-- SKILL WEAPON RESTRICTIONS
-- Which weapon type + color combos cannot inherit a given skill.
-- Uses weapon_type_id FK so restriction is precise: weapon_type_id=5 is Red Tome
-- only, not all Tomes. To restrict all Tomes insert four rows (one per color).
--
-- Why FK to weapon_types instead of free text?
--   The old design used restriction_type='weapon_type' + restriction_value='Tome',
--   which could only target the broad weapon category — all Tome colors or none.
--   By pointing directly at weapon_type_id, a restriction can target e.g.
--   Colorless Tome (id=8) without also blocking Red Tome (id=5) users.
--
-- Example: skill restricted to non-Staff users:
--   Four rows for Staff/Colorless (weapon_type_id=4) only.
-- Example: skill restricted to non-Colorless users:
--   One row each for Colorless Tome, Bow, Dagger, Breath, Beast (ids 8,12,16,20,24).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS skill_weapon_restrictions (
    skill_id       INTEGER NOT NULL REFERENCES skills(skill_id)             ON DELETE CASCADE,
    weapon_type_id INTEGER NOT NULL REFERENCES weapon_types(weapon_type_id) ON DELETE CASCADE,
    PRIMARY KEY (skill_id, weapon_type_id)
);

-- PK covers (skill_id, weapon_type_id) — add reverse for weapon_type_id → skills lookups
CREATE INDEX IF NOT EXISTS idx_skill_weapon_restr_weapon ON skill_weapon_restrictions(weapon_type_id);


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
    subject        TEXT     CHECK (subject IS NULL OR subject IN ('Unit', 'Foe', 'Partner', 'Ally')),
    operator       TEXT     CHECK (operator IS NULL OR operator IN ('>', '<', '>=', '<=', '=', 'within', 'IS', 'IS NOT')),
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

-- Uniqueness on conditions uses a partial-NULL-safe expression index.
-- SQLite UNIQUE treats each NULL as distinct, so two rows with NULL subject
-- would not be caught by a plain UNIQUE constraint. COALESCE('') normalises
-- NULLs so identical conditions are rejected regardless of nullable columns.
CREATE UNIQUE INDEX IF NOT EXISTS uidx_conditions ON conditions (
    condition_type,
    COALESCE(subject,  ''),
    COALESCE(operator, ''),
    COALESCE(value,    ''),
    COALESCE(phase,    '')
);

CREATE INDEX IF NOT EXISTS idx_conditions_type ON conditions(condition_type);


-- -----------------------------------------------------------------------------
-- SKILL EFFECT MAP
-- The junction that ties a skill to its effects, one row per stat per effect.
--
-- Why one row per stat?
--   Tunnel Vision gives Atk/Spd/Def/Res+9. Storing this as 'Atk/Spd/Def/Res'
--   in a single column makes it impossible to query "all skills that boost Atk."
--   Instead, four rows share the same skill_effect_id with stat = Atk, Spd, Def, Res.
--   Now "all skills that boost Atk by 6+" is a simple WHERE.
--
-- stat       → which stat this row targets (nullable for non-stat effects)
-- magnitude  → the numeric value (+9, x5, etc.) (nullable for binary effects
--              like Pass or Miracle that have no magnitude)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS skill_effect_map (
    skill_effect_map_id INTEGER PRIMARY KEY AUTOINCREMENT,
    skill_id            INTEGER NOT NULL REFERENCES skills(skill_id)                    ON DELETE CASCADE,
    skill_effect_id     INTEGER NOT NULL REFERENCES skill_effects(skill_effect_id)      ON DELETE CASCADE,
    stat                TEXT    CHECK (stat IN ('HP', 'Atk', 'Spd', 'Def', 'Res')),
    magnitude           INTEGER -- the +6, +9, x5 value; NULL for effects with no quantity
);

-- Plain UNIQUE on (skill_id, skill_effect_id, stat) would not catch duplicate NULL-stat rows
-- because SQLite treats each NULL as distinct. COALESCE('') normalises NULLs for comparison.
CREATE UNIQUE INDEX IF NOT EXISTS uidx_skill_effect_map
    ON skill_effect_map(skill_id, skill_effect_id, COALESCE(stat, ''));

CREATE INDEX IF NOT EXISTS idx_skill_effect_map_skill   ON skill_effect_map(skill_id);
CREATE INDEX IF NOT EXISTS idx_skill_effect_map_effect  ON skill_effect_map(skill_effect_id);


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
--   (skill_effect_map_id=X, condition_id=1, condition_group=1) → Res > foe's Res
--   (skill_effect_map_id=X, condition_id=2, condition_group=1) → Partner within 2 spaces
--   (skill_effect_map_id=X, condition_id=3, condition_group=1) → S+ Partner deployed
--   All three share condition_group=1, so any one of them is sufficient.
--
-- Example — a skill requiring BOTH above 50% HP AND unit initiated combat:
--   (skill_effect_map_id=Y, condition_id=4, condition_group=1) → HP >= 50%
--   (skill_effect_map_id=Y, condition_id=5, condition_group=2) → unit initiated combat
--   Different groups, so both must be true.
-- -----------------------------------------------------------------------------
-- Surrogate PK replaces the old composite PK(map_id, condition_id).
-- Reason: the old PK prevented the same condition from appearing in two different
-- condition_groups on the same effect (e.g. "HP >= 50%" as part of both an OR group
-- and a separate AND group). The UNIQUE below allows same condition in different groups
-- but still prevents duplicate rows within the same group.
CREATE TABLE IF NOT EXISTS skill_effect_conditions (
    sec_id              INTEGER PRIMARY KEY AUTOINCREMENT,
    skill_effect_map_id INTEGER NOT NULL REFERENCES skill_effect_map(skill_effect_map_id) ON DELETE CASCADE,
    condition_id        INTEGER NOT NULL REFERENCES conditions(condition_id)               ON DELETE CASCADE,
    condition_group     INTEGER NOT NULL DEFAULT 1,
    -- Same condition may appear in different groups (AND branches) but not twice in the same group.
    UNIQUE (skill_effect_map_id, condition_id, condition_group)
);

-- UNIQUE(skill_effect_map_id, condition_id, condition_group) covers skill_effect_map_id prefix lookups.
-- Add reverse index for condition → skill_effect_map lookups.
CREATE INDEX IF NOT EXISTS idx_skill_effect_cond_condition ON skill_effect_conditions(condition_id);
