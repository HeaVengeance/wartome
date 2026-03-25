# Heroes Feature

Covers everything about the hero catalog: who a hero is, their stats, their art, which games they come from, and their duo/harmonized skill.

---

## Tables Involved

| Table | Purpose |
|---|---|
| `characters` | Canonical identity — one row per real person |
| `heroes` | Every hero entry / alt — one row per summoning entry |
| `hero_stats` | Base stats at each rarity × IV variant |
| `heroes_art` | Art URLs and voice/artist credits per art set |
| `hero_origins` | Which FE games a hero comes from (junction) |
| `hero_duo_skills` | The Duo or Harmonized button skill |
| `weapon_types` | Lookup for weapon + color combos |
| `origins` | Lookup for FE game titles |

---

## Design Decisions

### Why `characters` and `heroes` are separate

A character like Lyn has many hero entries: base Lyn, Brave Lyn, Legendary Lyn, etc. If you linked hero entries directly to each other by `hero_id`, every new alt would require new relationship rows. By pointing all alts at a `character_id`, any new alt is automatically part of the same character without touching existing data.

This also means character-level relationships (parallels, name disambiguation, duo companions) can be stored once on `characters` and apply to all alts automatically.

**Rule:** one row in `characters` per real person; one row in `heroes` per summoning entry.

**Same person, different game name:** Severa (Awakening) and Selena (Fates) are the same character → one `characters` row, `canonical_name = 'Severa'`, both hero entries share the same `character_id`.

**Same name, different people:** Hilda (FE5) and Hilda (FE16) are different characters → two `characters` rows, both with `canonical_name = 'Hilda'`. The `character_relations` table with `relation_type = 'name_shared'` makes the disambiguation explicit and queryable.

### Why `character_id` is nullable on `heroes`

Not every hero entry has a confirmed canonical character identity at insert time (e.g. new seasonals, OC heroes). Nullable allows the hero to exist in the catalog before the character link is resolved, rather than forcing a dummy `characters` row.

### Why stats are broken into `hero_stats` rows

Each rarity (1–5★) and IV variant (Flaw / Neutral / Asset) has its own stat spread. Flattening this into columns on `heroes` would require 15 columns per stat (3 variants × 5 rarities) — 75 columns total, mostly NULL for lower rarities that are rarely queried. Instead, one row per `(hero_id, rarity, variant)` makes queries like "get the neutral 5★ stats for this hero" a simple filter.

### Why `heroes_art` is separate

A hero can have up to three art sets: Standard (launch), Resplendent (premium alt art), and Removed (art that was replaced). Each set has independent URL columns, artist, and voice actor data. Keeping this on a separate table avoids 18 nullable URL/text columns on `heroes`.

The `art_type` CHECK (`Standard`, `Resplendent`, `Removed`) and `UNIQUE (hero_id, art_type)` together ensure each hero has at most one row per art type.

### Why `hero_duo_skills` is separate from `skills`

Duo and Harmonized skills are **not equippable** — they cannot be inherited and don't occupy a skill slot. They are a UI button unique to that specific hero entry. Putting them in the `skills` table would require special-casing them out of every skill query. Keeping them in a dedicated table with a `UNIQUE hero_id` constraint reflects the 1:1 reality.

Whether it's a Duo skill or Harmonized skill is derived from `hero_type_map` (the hero's type) — no extra column is needed here.

### `availability` and version columns

These live on `heroes` to support pool derivation for the banners feature without needing a history table. See `banners.md` for the full pool query logic.

- `availability` — the hero's current (or permanent) pool status.
- `debut_version` — used to exclude the hero from the off-focus pool on their own debut banner (`debut_version < banner.game_version`).
- `pool_4star_special_version` — when they entered the 4★ special pool.
- `pool_3_4star_version` — when they fully demoted to the 3-4★ standard pool.

### `game_version` encoding

Stored as `major * 100 + minor` so integer comparison is correct. v8.10 = 810, v9.0 = 900, v9.3 = 903. String comparison would fail ("9.3" > "9.10" alphabetically, but 903 < 910 numerically — the correct answer).

### Origins ordering

`origins.series_order` follows the in-game FEH display order, not strict game release chronology. FEH (the game itself) is listed first (series_order = 1) because FEH-original heroes are listed first in-game. The `origin_id` matches the game number where applicable (FE7 → id 7) but does not need to be contiguous. TMS (#FE) and Engage use the positions they occupy in the game's title list.

---

## Common Queries

### Get a hero's full card (5★ Neutral stats + Standard art)

```sql
SELECT
    h.name,
    h.epithet,
    wt.weapon_type,
    wt.color,
    h.move_type,
    h.release_date,
    hs.hp, hs.atk, hs.spd, hs.def, hs.res,
    ha.portrait_url,
    ha.artist,
    ha.voice_actor_en
FROM heroes h
JOIN weapon_types wt ON wt.weapon_type_id = h.weapon_type_id
JOIN hero_stats hs   ON hs.hero_id = h.hero_id
    AND hs.rarity = 5 AND hs.variant = 'Neutral'
LEFT JOIN heroes_art ha ON ha.hero_id = h.hero_id
    AND ha.art_type = 'Standard'
WHERE h.hero_id = ?;
```

### Get all alts for a character

```sql
SELECT h.name, h.epithet, h.release_date
FROM heroes h
JOIN characters c ON c.character_id = h.character_id
WHERE c.canonical_name = 'Lyn'
ORDER BY h.release_date;
```

### Get all heroes from a specific game

```sql
SELECT h.name, h.epithet
FROM heroes h
JOIN hero_origins ho ON ho.hero_id = h.hero_id
JOIN origins o       ON o.origin_id = ho.origin_id
WHERE o.code = 'FE7'
ORDER BY h.name;
```

### Get all Flying Sword users

```sql
SELECT h.name, h.epithet
FROM heroes h
JOIN weapon_types wt ON wt.weapon_type_id = h.weapon_type_id
WHERE h.move_type = 'Flying'
  AND wt.weapon_type = 'Sword';
```

### Get stat comparison across rarities for a hero

```sql
SELECT rarity, variant, hp, atk, spd, def, res
FROM hero_stats
WHERE hero_id = ?
ORDER BY rarity, variant;
```

### Get all Harmonized heroes with their duo/harmonized skill

```sql
SELECT h.name, h.epithet, ds.name AS skill_name, ds.description
FROM heroes h
JOIN hero_duo_skills ds    ON ds.hero_id = h.hero_id
JOIN hero_type_map htm     ON htm.hero_id = h.hero_id
JOIN hero_types ht         ON ht.hero_type_id = htm.hero_type_id
WHERE ht.name = 'Harmonized';
```

---

## Gotchas

- **Always enable foreign keys:** `PRAGMA foreign_keys = ON;` at connection time. SQLite does not enforce FKs by default.
- **`hero_duo_skills` is 1:1 with `hero_id`:** `UNIQUE hero_id` is enforced. Insert will fail if you try to add a second skill for the same hero.
- **Stats UNIQUE on `(hero_id, rarity, variant)`:** inserting a duplicate will fail. Use `INSERT OR REPLACE` or upsert if updating existing stats.
- **Harmonized heroes have two `hero_origins` rows** — one per game they span. This is intentional and is used by the app to determine which allies benefit from the Harmonized skill.
- **`character_id` can be NULL** — always LEFT JOIN when querying character data.
- **`art_type = 'Removed'`** — some heroes have had their Standard art replaced. The Removed row is the old art; the current art is still stored as Standard.
