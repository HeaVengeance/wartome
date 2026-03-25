# Hero Types Feature

Covers the special hero type classifications (Legendary, Mythic, Duo, etc.), what effects each type provides, and the per-hero data like element, ally boosts, and duel value.

---

## Tables Involved

| Table | Purpose |
|---|---|
| `hero_types` | The 12 type classifications — seed data, rarely changes |
| `elements` | Seasonal elements (Fire/Water/Wind/Earth for Arena; Light/Dark/Astra/Anima for Aether Raids) |
| `type_effects` | Catalog of effects a type provides — shared across all heroes of that type |
| `hero_type_effect_map` | Junction: which effects does each type have? |
| `hero_type_map` | Per-hero type assignment with element, duel value, pair-up flag |
| `hero_ally_boosts` | Per-hero ally stat boosts during their active season |
| `hero_duo_skills` | The Duo or Harmonized button skill (lives in heroes.schema.sql) |

---

## Design Decisions

### Why `type_effects` are shared but `hero_ally_boosts` are per-hero

Every Legendary hero gets the same *kind* of effect: "grants ally stat boosts during season." That pattern is one row in `type_effects` and one row in `hero_type_effect_map` for the Legendary type.

But which stats and how much varies per hero: Legendary Lyn gives Spd/Res, Legendary Marth gives Atk/Def. Those specifics live on `hero_ally_boosts`, one row per stat per `hero_type_map_id`.

**Rule:** the *existence* of an effect belongs to the type; the *magnitude and stat* belong to the hero.

### Why a hero can have multiple types

A Legendary Duo hero is both Legendary and Duo. Each gives different effects — Legendary gives seasonal ally boosts and Arena scoring; Duo gives a Duo Skill button and duel stat total. Modeling these as two rows in `hero_type_map` avoids a combinatorial explosion of composite type names.

The `UNIQUE (hero_id, hero_type_id)` constraint ensures a hero can only have each type once.

### Why `hero_type_map` has a surrogate PK

`hero_ally_boosts` needs to reference a single hero type assignment row. If `hero_type_map` used a composite PK `(hero_id, hero_type_id)`, `hero_ally_boosts` would need both columns as a composite FK — verbose and fragile. The surrogate `hero_type_map_id` keeps the FK clean.

### `element_id` is nullable

Only Legendary, Mythic, and Chosen heroes have a seasonal element. All other types (Duo, Rearmed, etc.) leave `element_id` NULL. Querying seasonal heroes is `WHERE element_id IS NOT NULL`.

### `duel_value` is nullable

Only Duo heroes and Legendary heroes with a Duel effect use `duel_value` (the stat total override for Arena matchmaking). Heroes without it leave it NULL. The `duel_stat_total` type effect row in `hero_type_effect_map` signals that a type has this mechanic; the actual number lives here per hero.

### `has_pair_up` CHECK enforces type logic at the DB level

Pair Up is exclusively a Legendary hero ability (`hero_type_id = 1`). The constraint `CHECK (has_pair_up = 0 OR hero_type_id = 1)` prevents accidentally setting `has_pair_up = 1` on a Mythic or Duo hero row.

### Duo vs Harmonized — distinguished via type, not a column

A hero's duo skill row in `hero_duo_skills` is the same structure regardless of whether it's a Duo or Harmonized skill. The distinction is made by looking at `hero_type_map` — if `hero_type_id = 4` (Duo), it's a Duo Skill; if `hero_type_id = 5` (Harmonized), it's a Harmonized Skill.

For Harmonized heroes, the app determines which allies benefit by checking `hero_origins` — Harmonized allies must share at least one origin with the hero. No extra column is needed on `hero_duo_skills`.

### `elements.element_group` separates Arena vs Aether Raids elements

Even though both groups use the word "element," Legendary/Chosen elements (Fire/Water/Wind/Earth) affect Arena; Mythic elements (Light/Dark/Astra/Anima) affect Aether Raids. The `element_group` column allows a query like "which Legendary heroes are active in the current Fire season?" to filter by `element_group = 'Legendary'` first.

---

## The 12 Types

| ID | Name | Key Effects |
|---|---|---|
| 1 | Legendary | Seasonal ally stat boosts (Arena), optional Pair Up |
| 2 | Mythic | Seasonal ally stat boosts (Aether Raids), raiding party bonus |
| 3 | Chosen | Merge-based stat boosts, Arena scoring, blessed in season |
| 4 | Duo | Duo Skill button, duel stat total for Arena |
| 5 | Harmonized | Harmonized Skill button, Resonant Battles bonus |
| 6 | Ascended | Grants Ascendant Floret (second Asset stat) |
| 7 | Aided | Grants Aide's Essence (+1 all stats), Aide Accessories |
| 8 | Entwined | Support rank up to S+, support stat boosts |
| 9 | Rearmed | Arcane weapon can be passed without consuming the hero |
| 10 | Attuned | Skills can be passed without consuming the hero |
| 11 | Emblem | +1 all stats per merge (up to +10 at +10 merges) |
| 12 | Dance | Can equip Dance/Sing assist skills |

---

## Common Queries

### Get all heroes of a specific type

```sql
SELECT h.name, h.epithet
FROM heroes h
JOIN hero_type_map htm ON htm.hero_id = h.hero_id
JOIN hero_types ht     ON ht.hero_type_id = htm.hero_type_id
WHERE ht.name = 'Legendary'
ORDER BY h.release_date;
```

### Get all Fire Legendary heroes with their ally boosts

```sql
SELECT
    h.name,
    h.epithet,
    hab.stat,
    hab.magnitude
FROM heroes h
JOIN hero_type_map htm ON htm.hero_id = h.hero_id
JOIN hero_types ht     ON ht.hero_type_id = htm.hero_type_id
JOIN elements e        ON e.element_id = htm.element_id
JOIN hero_ally_boosts hab ON hab.hero_type_map_id = htm.hero_type_map_id
WHERE ht.name = 'Legendary'
  AND e.name = 'Fire'
ORDER BY h.name, hab.stat;
```

### Get all Legendary + Mythic heroes active in a given season

```sql
-- Fire season example
SELECT h.name, h.epithet, ht.name AS type, e.name AS element
FROM heroes h
JOIN hero_type_map htm ON htm.hero_id = h.hero_id
JOIN hero_types ht     ON ht.hero_type_id = htm.hero_type_id
JOIN elements e        ON e.element_id = htm.element_id
WHERE e.name = 'Fire';
```

### Get the full type profile for a hero (all types + effects)

```sql
SELECT
    ht.name        AS type_name,
    te.name        AS effect_name,
    te.category,
    te.description,
    e.name         AS element,
    htm.duel_value,
    htm.has_pair_up
FROM hero_type_map htm
JOIN hero_types ht           ON ht.hero_type_id = htm.hero_type_id
LEFT JOIN elements e         ON e.element_id = htm.element_id
JOIN hero_type_effect_map htem ON htem.hero_type_id = ht.hero_type_id
JOIN type_effects te         ON te.type_effect_id = htem.type_effect_id
WHERE htm.hero_id = ?
ORDER BY ht.name, te.name;
```

### Get all Duo/Harmonized heroes with companion characters

```sql
SELECT
    h.name       AS hero_name,
    h.epithet,
    ht.name      AS type,
    c.canonical_name AS companion
FROM heroes h
JOIN hero_type_map htm  ON htm.hero_id = h.hero_id
JOIN hero_types ht      ON ht.hero_type_id = htm.hero_type_id
JOIN hero_relations hr  ON hr.hero_id = h.hero_id
JOIN characters c       ON c.character_id = hr.character_id
WHERE ht.name IN ('Duo', 'Harmonized')
  AND hr.relation_type = 'duo_companion'
ORDER BY h.name;
```

### Get all heroes with Pair Up

```sql
SELECT h.name, h.epithet
FROM heroes h
JOIN hero_type_map htm ON htm.hero_id = h.hero_id
WHERE htm.has_pair_up = 1;
```

---

## Gotchas

- **A hero can appear multiple times in `hero_type_map`** (one row per type). Always join through `hero_type_map` rather than assuming one row per hero.
- **Ally boosts are per `hero_type_map_id`**, not per `hero_id`. A Legendary Duo hero has two `hero_type_map` rows; ally boosts only attach to the Legendary row (type_id = 1), not the Duo row (type_id = 4).
- **`element_id` is NULL for non-seasonal types** — always LEFT JOIN elements when querying general type data.
- **`has_pair_up` CHECK** — the DB will reject `has_pair_up = 1` for any `hero_type_id` other than 1 (Legendary). Do not set this flag on the Duo row of a Legendary Duo hero.
- **`type_effects` rows are shared across types** — `seasonal_stat_boost` (id=1) is used by Legendary, Mythic, and Chosen. Do not delete or change shared effect rows; they affect all three types.
- **Chosen heroes** have `element_group = 'Legendary'` on their element — they use the same Arena seasonal elements as Legendary heroes (Fire/Water/Wind/Earth), not Mythic elements.
