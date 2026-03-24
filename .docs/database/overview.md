# Database Overview

High-level map of how all tables relate. Grouped by concern.

---

## Groups

| Load Order | Group | Tables | File |
|---|---|---|---|
| 1 | General Lookups | `weapon_types`, `origins` | general.schema.sql |
| 2 | Hero Catalog | `heroes`, `heroes_art`, `hero_stats` | heroes.schema.sql |
| 3 | Skill Catalog | `effect_types`, `skill_effects`, `skills`, `conditions`, `skill_effect_map`, `skill_effect_conditions`, `skill_restrictions` | skills.schema.sql |
| 4 | Junctions | `hero_origins`, `hero_skills`, `skill_hero_locks` | junctions.schema.sql |
| — | Barracks | *(planned)* | barracks.schema.sql |

---

## Full ERD

```mermaid
erDiagram

    %% -------------------------
    %% GENERAL LOOKUPS
    %% -------------------------

    weapon_types {
        int weapon_id PK
        text weapon_type
        text color
    }

    origins {
        int origin_id PK
        text code
        text title
        int series_order
    }

    %% -------------------------
    %% HERO CATALOG
    %% -------------------------

    heroes {
        int hero_id PK
        text name
        text epithet
        int weapon_type_id FK
        text move_type
        text release_date
        text description
    }

    heroes_art {
        int art_id PK
        int hero_id FK
        text art_type
        text portrait_url
        text neutral_url
        text attack_url
        text special_url
        text damage_url
        text voice_actor_jp
        text voice_actor_en
        text artist
    }

    hero_stats {
        int stat_id PK
        int hero_id FK
        int rarity
        text variant
        int hp
        int atk
        int spd
        int def
        int res
    }

    %% -------------------------
    %% SKILL CATALOG
    %% -------------------------

    skills {
        int skill_id PK
        text name
        text slot
        int sp_cost
        text description
        int is_prf
        int is_inheritable
    }

    effect_types {
        int effect_type_id PK
        text name
        text category
    }

    skill_effects {
        int effect_id PK
        int effect_type_id FK
        int is_permanent
        int is_in_combat
        int is_status
        text effect_target
        text effect_area
        text description
    }

    %% -------------------------
    %% SKILL WIRING
    %% -------------------------

    skill_effect_map {
        int map_id PK
        int skill_id FK
        int effect_id FK
        text stat
        int magnitude
    }

    conditions {
        int condition_id PK
        text condition_type
        text subject
        text operator
        text value
        text phase
        text description
    }

    skill_effect_conditions {
        int map_id FK
        int condition_id FK
        int condition_group
    }

    %% -------------------------
    %% SKILL RULES
    %% -------------------------

    skill_restrictions {
        int restriction_id PK
        int skill_id FK
        text restriction_type
        text restriction_value
    }

    %% -------------------------
    %% RELATIONSHIPS
    %% -------------------------

    heroes ||--o{ heroes_art         : "has art"
    heroes ||--o{ hero_stats         : "has stats"
    heroes ||--o{ hero_skills        : "has default kit"
    heroes ||--o{ hero_origins       : "originates from"
    heroes ||--o{ skill_hero_locks   : "owns prf skill"

    origins ||--o{ hero_origins      : "claimed by"

    weapon_types ||--o{ heroes       : "used by"

    skills ||--o{ hero_skills        : "appears in kit"
    skills ||--o{ skill_effect_map   : "broken into effects"
    skills ||--o{ skill_hero_locks   : "locked to hero"
    skills ||--o{ skill_restrictions : "restricted by"

    skill_effects ||--o{ skill_effect_map   : "instantiated by"
    effect_types  ||--o{ skill_effects      : "categorizes"

    skill_effect_map ||--o{ skill_effect_conditions : "activated by"
    conditions       ||--o{ skill_effect_conditions : "applied to"

    %% -------------------------
    %% JUNCTIONS
    %% -------------------------

    hero_origins {
        int hero_id FK
        int origin_id FK
    }

    hero_skills {
        int hero_skill_id PK
        int hero_id FK
        int skill_id FK
        text slot
        int unlock_rarity
    }

    skill_hero_locks {
        int skill_id FK
        int hero_id FK
    }
```

---

## How to read a skill

A `skill` is broken into rows in `skill_effect_map` — one row per stat per effect.
Each of those rows optionally links to one or more `conditions` via `skill_effect_conditions`.

```
skills
  └── skill_effect_map  ← one row per effect per stat (e.g. Atk+9, Spd+9)
        ├── skill_effects   ← what the effect IS (stat boost, in combat, targets unit)
        │     └── effect_types  ← broad category (stat, combat, movement…)
        └── skill_effect_conditions  ← when it activates
              └── conditions  ← reusable conditions (HP >= 50%, partner deployed…)
```

Conditions in the same `condition_group` are **OR**'d.
Different `condition_group` values on the same `map_id` are **AND**'d.

---

## How to read a hero

```
heroes
  ├── weapon_types     ← color + weapon category (e.g. Red Sword)
  ├── hero_origins     ← which FE games the hero comes from (many-to-many)
  ├── heroes_art       ← one row per art set (Standard, Resplendent, Removed)
  ├── hero_stats       ← one row per rarity × variant (Flaw / Neutral / Asset)
  └── hero_skills      ← one row per skill, with the rarity it unlocks at
        └── skills     ← links into the full skill catalog
```
