-- =============================================================================
-- IMPORTANT: SQLite does not enforce foreign keys by default.
-- The following pragma must be enabled at connection time:
--   PRAGMA foreign_keys = ON;
-- With Drizzle + better-sqlite3, set this in your db client config.
-- =============================================================================


-- Weapons
CREATE TABLE IF NOT EXISTS weapon_types (
    weapon_id   INTEGER PRIMARY KEY,
    weapon_type TEXT NOT NULL,
    color       TEXT NOT NULL,
    UNIQUE (weapon_type, color),
    CHECK (
        (weapon_type = 'Sword'  AND color = 'Red')      OR
        (weapon_type = 'Lance'  AND color = 'Blue')     OR
        (weapon_type = 'Axe'   AND color = 'Green')     OR
        (weapon_type = 'Staff' AND color = 'Colorless') OR
        (weapon_type IN ('Tome', 'Bow', 'Dagger', 'Breath', 'Beast')
            AND color IN ('Red', 'Blue', 'Green', 'Colorless'))
    )
);

INSERT INTO weapon_types (weapon_id, weapon_type, color) VALUES
    (1,  'Sword',  'Red'),
    (2,  'Lance',  'Blue'),
    (3,  'Axe',   'Green'),
    (4,  'Staff',  'Colorless'),
    (5,  'Tome',   'Red'),
    (6,  'Tome',   'Blue'),
    (7,  'Tome',   'Green'),
    (8,  'Tome',   'Colorless'),
    (9,  'Bow',    'Red'),
    (10, 'Bow',    'Blue'),
    (11, 'Bow',    'Green'),
    (12, 'Bow',    'Colorless'),
    (13, 'Dagger', 'Red'),
    (14, 'Dagger', 'Blue'),
    (15, 'Dagger', 'Green'),
    (16, 'Dagger', 'Colorless'),
    (17, 'Breath', 'Red'),
    (18, 'Breath', 'Blue'),
    (19, 'Breath', 'Green'),
    (20, 'Breath', 'Colorless'),
    (21, 'Beast',  'Red'),
    (22, 'Beast',  'Blue'),
    (23, 'Beast',  'Green'),
    (24, 'Beast',  'Colorless')
;

-- Origins (FE games / series)
CREATE TABLE IF NOT EXISTS origins (
    origin_id    INTEGER PRIMARY KEY,
    code         TEXT NOT NULL UNIQUE, -- short code e.g. FE1, FE7, FEH
    title        TEXT NOT NULL,
    series_order INTEGER            -- for sorting chronologically
);

INSERT INTO origins (origin_id, code, title, series_order) VALUES
    (2,  'FE2',  'Gaiden / Echoes: Shadows of Valentia', 2),
    (4,  'FE4',  'Genealogy of the Holy War',            4),
    (5,  'FE5',  'Thracia 776',                          5),
    (6,  'FE6',  'The Binding Blade',                    6),
    (7,  'FE7',  'The Blazing Blade',                    7),
    (8,  'FE8',  'The Sacred Stones',                    8),
    (9,  'FE9',  'Path of Radiance',                     9),
    (10, 'FE10', 'Radiant Dawn',                         10),
    (11, 'FE11', 'Shadow Dragon / New Mystery of the Emblem', 1),
    (13, 'FE13', 'Awakening',                            13),
    (14, 'FE14', 'Fates',                                14),
    (16, 'FE16', 'Three Houses',                         16),
    (17, 'FE17', 'Engage',                               17),
    (18, 'FEH',  'Heroes',                               18),
    (19, 'TMS',  'Tokyo Mirage Sessions #FE Encore',     NULL)
;

-- hero_origins is defined in junctions.schema.sql
-- (depends on both heroes and origins — load order resolved there)
