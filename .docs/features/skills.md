# Skills Feature

Covers the skill catalog, how effects are modeled, activation conditions, inheritance restrictions, and a hero's default skill kit.

---

## Tables Involved

| Table | Purpose |
|---|---|
| `skills` | Every equippable skill in the game |
| `effect_types` | Reference table of broad effect categories |
| `skill_effects` | Reusable effect patterns (what kind, who, where, how) |
| `skill_effect_map` | Ties a skill to its effects with the actual value (+9, etc.) |
| `skill_effect_conditions` | Ties activation conditions to a specific skill-effect row |
| `conditions` | Reusable catalog of activation conditions |
| `skill_move_restrictions` | Which move types cannot inherit a skill |
| `skill_weapon_restrictions` | Which weapon type + color combos cannot inherit a skill |
| `skill_hero_locks` | Prf skills: which hero(es) own it |
| `hero_skills` | A hero's default skill kit (slot + unlock rarity) |

---

## Design Decisions

### The effect chain

The model separates three concerns:

```
skills
  └── skill_effect_map       ← what value? (+9 Atk, +9 Spd)
        ├── skill_effects    ← what pattern? (stat boost, in-combat, targets unit)
        │     └── effect_types  ← broad category (stat, combat, damage, …)
        └── skill_effect_conditions  ← when? (HP ≥ 50%, unit initiated)
              └── conditions   ← reusable condition catalog
```

**Why not just store `Atk+9` as text on `skills`?**
Storing effect descriptions as free text makes the data queryable only by string matching. The normalized model lets you ask: "find all skills that grant the unit Atk+6 or more in combat" with a simple `WHERE stat = 'Atk' AND magnitude >= 6 AND is_in_combat = 1` — no parsing required.

### Why `skill_effects` are reusable patterns

Many skills share the same *type* of effect: "a stat boost, in combat, targeting the unit." Rather than duplicating that pattern row for each skill, one `skill_effects` row is shared across all skills that have the same structural behavior. The UNIQUE constraint on `(effect_type_id, is_permanent, is_in_combat, is_status, effect_target, effect_area)` enforces this — you cannot create two identical effect patterns.

The specific *value* (+6, +9) lives on `skill_effect_map.magnitude`, not on `skill_effects`. Pattern is reused; value is per-skill.

### Why `skill_effect_map` has one row per stat

A skill like Tunnel Vision grants Atk/Spd/Def/Res+9. Storing this as `'Atk/Spd/Def/Res'` in a single column makes it impossible to query "all skills that boost Atk." Instead, four rows share the same `skill_effect_id` with `stat` set individually. Now `WHERE stat = 'Atk' AND magnitude >= 9` works cleanly.

`stat` is nullable for non-stat effects (e.g. Pass, Miracle) that have no specific stat target.

### OR/AND condition logic via `condition_group`

Activation conditions on the same `skill_effect_map_id` can be OR'd or AND'd:

- **Same `condition_group`** → conditions are OR'd (any one is sufficient)
- **Different `condition_group`** → conditions are AND'd (all must be true)

`skill_effect_conditions` uses a surrogate PK (`sec_id`) rather than a composite PK on `(skill_effect_map_id, condition_id)`. The old composite PK prevented the same condition from appearing in two different groups for the same effect row — e.g., "HP ≥ 50%" as part of an OR branch AND a separate AND requirement. The surrogate PK with `UNIQUE (skill_effect_map_id, condition_id, condition_group)` allows this while still preventing exact duplicate rows.

Example — Tunnel Vision's "Attack Twice" has three OR'd conditions (all group 1):
```
(map_id=X, condition_id=1, group=1) → Res > foe's Res
(map_id=X, condition_id=2, group=1) → Partner within 2 spaces
(map_id=X, condition_id=3, group=1) → S+ Partner deployed
```
Any one of these triggers the effect.

Example — a skill requiring BOTH conditions (different groups):
```
(map_id=Y, condition_id=4, group=1) → HP ≥ 50%
(map_id=Y, condition_id=5, group=2) → unit initiated combat
```
Both must be true.

### Why conditions are reusable

"HP ≥ 50%" appears in hundreds of skills. One row in `conditions` covers all of them. Adding a new condition is just an INSERT — the `condition_type` CHECK list is extensible (it's a table, not a hardcoded constraint).

The UNIQUE index on conditions uses `COALESCE(col, '')` on all nullable columns because SQLite treats each NULL as distinct in a plain UNIQUE constraint — two rows with `subject = NULL` would not be caught as duplicates. The COALESCE normalizes NULLs to empty string for comparison.

### Why `skill_effect_map` also uses a COALESCE unique index

Same reason as conditions: `stat` is nullable (non-stat effects like Pass have `stat = NULL`). A plain `UNIQUE (skill_id, skill_effect_id, stat)` would allow multiple NULL-stat rows for the same skill+effect combination. The expression index `COALESCE(stat, '')` catches this.

### `is_prf` and `is_inheritable` both exist

A prf skill is always non-inheritable, so `is_prf = 1` implies `is_inheritable = 0`. Both columns exist because having both makes queries more readable than inferring one from the other. `WHERE is_inheritable = 1` reads as "skills anyone can inherit" without needing `WHERE is_prf = 0`.

### Weapon skills declare their `weapon_type_id`

Weapon-slot skills carry a `weapon_type_id` so you can query "all Swords," "all Blue Tomes," "all Green Daggers" without parsing skill names. A CHECK constraint enforces that weapon-slot skills always have this set, and non-weapon skills never do.

### `hero_skills` slot CHECK

```
'Weapon', 'Assist', 'Special', 'A', 'B', 'C', 'X', 'S'
```

The X slot is a newer addition (skills that occupy an extra combat slot). S is the Sacred Seal slot, which appears in `hero_skills` when a hero's base kit includes a seal recommendation but is treated as a separate equippable category in the `skills` catalog.

---

## Common Queries

### Get a hero's full default kit at 5★

```sql
SELECT s.name, s.slot, hs.unlock_rarity
FROM hero_skills hs
JOIN skills s ON s.skill_id = hs.skill_id
WHERE hs.hero_id = ?
  AND hs.unlock_rarity <= 5
ORDER BY hs.slot, hs.unlock_rarity;
```

### Find all skills that boost Atk in combat

```sql
SELECT DISTINCT s.name, s.slot, sem.magnitude
FROM skills s
JOIN skill_effect_map sem    ON sem.skill_id = s.skill_id
JOIN skill_effects se        ON se.skill_effect_id = sem.skill_effect_id
JOIN effect_types et         ON et.effect_type_id = se.effect_type_id
WHERE et.name = 'stat_boost'
  AND se.is_in_combat = 1
  AND sem.stat = 'Atk'
  AND sem.magnitude >= 6
ORDER BY sem.magnitude DESC;
```

### Find all inheritable B-slot skills for Infantry units

```sql
SELECT s.name
FROM skills s
WHERE s.slot = 'B'
  AND s.is_inheritable = 1
  AND s.skill_id NOT IN (
      SELECT skill_id FROM skill_move_restrictions WHERE move_type = 'Infantry'
  );
```

### Check if a hero can inherit a skill (Infantry Red Tome user, weapon_type_id = 5)

```sql
SELECT
    CASE
        WHEN EXISTS (
            SELECT 1 FROM skill_move_restrictions
            WHERE skill_id = ? AND move_type = 'Infantry'
        ) THEN 'blocked by move type'
        WHEN EXISTS (
            SELECT 1 FROM skill_weapon_restrictions
            WHERE skill_id = ? AND weapon_type_id = 5
        ) THEN 'blocked by weapon type'
        ELSE 'can inherit'
    END AS result;
```

### Get all effects and conditions for a skill

```sql
SELECT
    et.name         AS effect_category,
    se.effect_target,
    se.effect_area,
    se.is_in_combat,
    sem.stat,
    sem.magnitude,
    c.description   AS condition,
    sec.condition_group
FROM skill_effect_map sem
JOIN skill_effects se  ON se.skill_effect_id = sem.skill_effect_id
JOIN effect_types et   ON et.effect_type_id = se.effect_type_id
LEFT JOIN skill_effect_conditions sec ON sec.skill_effect_map_id = sem.skill_effect_map_id
LEFT JOIN conditions c                ON c.condition_id = sec.condition_id
WHERE sem.skill_id = ?
ORDER BY sem.skill_effect_map_id, sec.condition_group, sec.condition_id;
```

### Find prf skills and which heroes own them

```sql
SELECT s.name, h.name AS hero_name, h.epithet
FROM skills s
JOIN skill_hero_locks shl ON shl.skill_id = s.skill_id
JOIN heroes h             ON h.hero_id = shl.hero_id
WHERE s.is_prf = 1
ORDER BY s.name;
```

### Check if two skills share the same effect pattern

```sql
-- Skills that share an effect pattern with skill_id = 42
SELECT DISTINCT s.name
FROM skills s
JOIN skill_effect_map sem   ON sem.skill_id = s.skill_id
WHERE sem.skill_effect_id IN (
    SELECT skill_effect_id FROM skill_effect_map WHERE skill_id = 42
)
  AND s.skill_id != 42;
```

---

## Gotchas

- **`conditions` UNIQUE uses COALESCE index** — when inserting conditions, duplicates are caught even when nullable columns are NULL. Do not rely on `INSERT OR IGNORE` silently passing for NULL-field duplicates.
- **`skill_effect_map` UNIQUE uses COALESCE index** — same as above for the `stat` column.
- **Condition evaluation is per `skill_effect_map_id`**, not per skill. The same skill can have Effect A with condition group logic X, and Effect B with entirely different conditions.
- **`skill_effects` rows are shared** — do not update a `skill_effects` row to "fix" one skill. Changing the pattern affects every skill referencing that row. Instead, insert a new `skill_effects` row.
- **`skill_effect_conditions` has a surrogate PK `sec_id`** — the UNIQUE constraint is `(skill_effect_map_id, condition_id, condition_group)`. The same condition can appear in different groups, but not twice in the same group.
- **`hero_skills` UNIQUE is `(hero_id, skill_id)`** — a hero cannot have the same skill listed twice even at different rarities. If a skill upgrades (Iron Sword → Silver Sword → Prf), those are different `skill_id`s.
- **Restriction tables restrict inheritance**, not equipping. A unit that already has a prf skill equipped is unaffected — restriction rows only apply to the inheritance action.
- **`skill_weapon_restrictions` uses `weapon_type_id`**, not a weapon category string. To restrict "all Tomes" requires four rows (one per Tome color: Red/Blue/Green/Colorless). Check `weapon_types` for IDs.
- **`skill_move_restrictions` PK is `(skill_id, move_type)`** — no surrogate key. Simple composite PK since both columns are always known and non-nullable.
