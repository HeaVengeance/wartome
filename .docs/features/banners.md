# Banners Feature

Covers summoning banners: their types, dates, focus lineups, base pull rates, and the logic for deriving which heroes were in each summoning pool at a given point in time.

---

## Tables Involved

| Table | Purpose |
|---|---|
| `banners` | Each banner event (name, type, dates, version, spark, source) |
| `banner_type_rates` | Base pull rates per (banner_type, pool_tier) — seed data |
| `banner_focus` | Focus hero lineup per banner; marks 4★ focus units |
| `heroes.availability` | Hero's current pool category |
| `heroes.debut_version` | Game version when the hero first became summonable |
| `heroes.pool_4star_special_version` | Version when the hero entered the 4★ special pool |
| `heroes.pool_3_4star_version` | Version when the hero fully demoted to the 3-4★ pool |

---

## Pool Tiers

| Tier | What it contains |
|---|---|
| `5star_focus` | Featured focus units on this banner |
| `5star_off_focus` | Non-focus heroes that are 5★ summonable |
| `4star_focus` | Focus units that also appear at 4★ on select banners |
| `4star_special` | Demoted heroes not yet in the standard 3-4★ pool |
| `3_4star` | Standard 3★ and 4★ pool (fully demoted heroes + originals) |

---

## Design Decisions

### Why pool membership lives on `heroes`, not in a separate table

Pool membership over time could be modeled as a history table: `(hero_id, version, pool_tier)`. But this requires maintaining that history explicitly for every hero across every version — a lot of insert burden with no real query advantage for the primary use case (reconstruct the pool at a given banner's version).

Instead, four columns on `heroes` encode the transition points:
- `debut_version` — when they entered the 5★ summonable pool
- `pool_4star_special_version` — when they left 5★ exclusive and entered 4★ special
- `pool_3_4star_version` — when they left 4★ special and entered the permanent 3-4★ pool

Pass `banner.game_version` as the query parameter `V` and derive the pool at that point. This covers all historical banners without a separate history table.

### Why `debut_version < V` (strict less-than)

On a hero's debut banner, `debut_version = banner.game_version`. If the comparison were `<=`, new heroes would appear in both the focus pool (via `banner_focus`) and the off-focus pool simultaneously — double-counting them on their own banner.

Strict less-than excludes them from off-focus on their debut banner. On every subsequent banner, `debut_version < V` is true, so they enter the off-focus pool correctly.

### Why limited heroes have `availability = '5star_limited'`

Limited heroes (seasonal units, special event exclusives) are never in the standing off-focus pool. They only appear on specific banners via `banner_focus`. Setting `availability = '5star_limited'` makes them invisible to all derived pool queries — you cannot accidentally include them in an off-focus pool by forgetting to exclude them.

### Veteran re-featuring gives double rate naturally

When a hero who is already in the standard 5★ pool gets re-featured on a non-new-heroes banner:
- They appear in `banner_focus` → counted in the focus rate.
- They still satisfy `availability = '5star_exclusive' AND debut_version < V` → counted in the off-focus rate.

No special casing is needed. The double rate (focus + off-focus) is a natural consequence of being in both pools simultaneously — which is correct behavior.

### `game_version` encoding

Stored as `major * 100 + minor`. Examples:
- v8.10 → 810
- v9.0 → 900
- v9.3 → 903

Integer comparison must be used, not string. `'9.3' > '9.10'` alphabetically (wrong), but `903 < 910` numerically (correct). All version columns (`debut_version`, `pool_4star_special_version`, `pool_3_4star_version`, `banners.game_version`) use this encoding.

### `source_banner_id` for reruns

Rerun banners are common and may go by different names than the original (e.g. "Tempest Trials" reruns, New Heroes revival banners). Using a self-referencing FK `source_banner_id` lets you trace any banner back to its original without relying on name parsing. `ON DELETE SET NULL` means deleting an original banner doesn't cascade-delete all its reruns.

### `spark_count` default of 40

Most banners use a 40-summon spark mechanic (free unit pick). Older banners had no spark (`spark_count = 0`). Some newer banners may change this. Stored per-banner so it can be queried for summoning simulation without hardcoding per banner type.

### `banner_type_rates` is seed data only

These rows cover the published base rates for each banner type. They are not expected to change frequently — but if rates change in a future version, an update to the relevant row is all that is needed. No code change required.

Not every `(banner_type, pool_tier)` combination exists — `seasonal` banners have no `5star_off_focus` pool, for example. Querying for a pool tier that isn't seeded will return no rows.

---

## Pool Derivation Queries

All queries take `banner.game_version` as the parameter `V`.

### 5★ focus

```sql
SELECT h.*
FROM banner_focus bf
JOIN heroes h ON h.hero_id = bf.hero_id
WHERE bf.banner_id = ?;
```

### 5★ off-focus

```sql
SELECT h.*
FROM heroes h
WHERE h.availability = '5star_exclusive'
  AND h.debut_version < ?;  -- V = banner.game_version
```

### 4★ focus

```sql
SELECT h.*
FROM banner_focus bf
JOIN heroes h ON h.hero_id = bf.hero_id
WHERE bf.banner_id = ?
  AND bf.has_4star_focus = 1;
```

### 4★ special pool

Heroes who have demoted from 5★ exclusive but have not yet entered the full 3-4★ pool.

```sql
SELECT h.*
FROM heroes h
WHERE h.pool_4star_special_version <= ?           -- V = banner.game_version
  AND (h.pool_3_4star_version IS NULL
       OR h.pool_3_4star_version > ?);            -- both params = V
```

### 3-4★ standard pool

Heroes who were always in the 3-4★ pool, or who have fully demoted.

```sql
SELECT h.*
FROM heroes h
WHERE h.pool_3_4star_version <= ?;  -- V = banner.game_version
```

**Convention:** heroes that launched directly in the 3-4★ pool must have `pool_3_4star_version = debut_version` (not NULL). This means the single `pool_3_4star_version <= V` clause handles both demoted heroes and launch-3-4★ heroes correctly for all historical versions. Do not rely on `availability = '3_4star'` in pool queries — it is a current-state label, not a versioned value, and would cause launch-3-4★ heroes to appear in pools before they existed.

### Full pool for a banner (all tiers labeled)

```sql
-- Focus
SELECT h.hero_id, h.name, h.epithet, '5star_focus' AS pool_tier
FROM banner_focus bf
JOIN heroes h ON h.hero_id = bf.hero_id
WHERE bf.banner_id = :banner_id

UNION ALL

-- Off-focus
SELECT h.hero_id, h.name, h.epithet, '5star_off_focus'
FROM heroes h
WHERE h.availability = '5star_exclusive'
  AND h.debut_version < :game_version

UNION ALL

-- 4★ special
SELECT h.hero_id, h.name, h.epithet, '4star_special'
FROM heroes h
WHERE h.pool_4star_special_version <= :game_version
  AND (h.pool_3_4star_version IS NULL OR h.pool_3_4star_version > :game_version)

UNION ALL

-- 3-4★ (launch-3-4★ heroes must have pool_3_4star_version = debut_version, not NULL)
SELECT h.hero_id, h.name, h.epithet, '3_4star'
FROM heroes h
WHERE h.pool_3_4star_version <= :game_version;
```

---

## Other Common Queries

### Get all banners a hero has been featured on

```sql
SELECT b.name, b.banner_type, b.start_date, bf.has_4star_focus
FROM banner_focus bf
JOIN banners b ON b.banner_id = bf.banner_id
WHERE bf.hero_id = ?
ORDER BY b.start_date;
```

### Get a banner's rates (all tiers)

```sql
SELECT btr.pool_tier, btr.base_rate
FROM banners b
JOIN banner_type_rates btr ON btr.banner_type = b.banner_type
WHERE b.banner_id = ?
ORDER BY btr.base_rate DESC;
```

### Get all reruns of an original banner

```sql
SELECT b.banner_id, b.name, b.start_date
FROM banners b
WHERE b.source_banner_id = ?
ORDER BY b.start_date;
```

### Get all Legendary banners ordered chronologically

```sql
SELECT banner_id, name, start_date, game_version
FROM banners
WHERE banner_type = 'legendary'
ORDER BY start_date;
```

### Get heroes that appeared on both their debut banner and a specific Legendary banner

```sql
-- Heroes whose debut banner is not the legendary banner, but who are focus on it
SELECT h.name, h.epithet, h.debut_version
FROM banner_focus bf
JOIN heroes h ON h.hero_id = bf.hero_id
JOIN banners b ON b.banner_id = bf.banner_id
WHERE b.banner_id = ?
  AND h.debut_version < b.game_version;
```

---

## Gotchas

- **`5star_limited` heroes never appear in derived pool queries.** Only via `banner_focus`. If a limited hero is added to `banner_focus` on a new banner, they will appear as focus. They will never satisfy the off-focus query.
- **New heroes appear in `5star_off_focus` on their second banner onwards**, not their first. `debut_version < V` (strict) ensures this.
- **Double rate for re-featured veterans is intentional.** Do not add exclusion logic to remove them from off-focus when they appear in focus. They appear in both — that is the correct pool behavior.
- **`banner_type_rates` rows are static defaults.** If a specific banner has non-standard rates (e.g. anniversary banners with boosted rates), you would need a banner-level rate override mechanism. This is not currently in the schema — note it for future iteration.
- **`pool_4star_special_version` and `pool_3_4star_version` are NULL until set.** A hero that has never demoted has both as NULL. Always use `IS NULL` checks and not `= NULL`.
- **Grail and Story heroes (`availability IN ('grail', 'story')`) are never in any summoning pool.** They will never satisfy any pool tier query. `debut_version` should be NULL for these heroes.
- **`spark_count = 0` means no spark** on that banner — not "1 summon = 1 spark."
