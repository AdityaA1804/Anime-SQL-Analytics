-- Tables for the anime project.
-- The CSV is one wide table with genres/studios packed into comma-separated
-- cells, so I'm splitting those out into their own tables.
-- Producers and licensors are in the CSV too but none of my questions use
-- them, so I left them out.

DROP TABLE IF EXISTS anime_score_dist, anime_studio, anime_genre, studio, genre, anime CASCADE;

CREATE TABLE anime (
    anime_id        INT PRIMARY KEY,          -- MAL_ID from the csv
    name            TEXT NOT NULL,
    english_name    TEXT,
    type            TEXT,                     -- TV / Movie / OVA / ONA / Special / Music
    source          TEXT,                     -- Manga / Original / Light novel ...
    rating          TEXT,                     -- age rating
    episodes        INT,
    aired_from      DATE,
    aired_to        DATE,                     -- null if still airing or unknown
    aired_raw       TEXT,                     -- original string, kept for checking
    premiere_season TEXT,
    premiere_year   INT,
    duration_min    NUMERIC(6,1),             -- minutes, per episode for series
    score           NUMERIC(4,2),             -- null when MAL shows 'Unknown'
    ranked          INT,
    popularity      INT,
    members         INT,
    favorites       INT,
    watching        INT,
    completed       INT,
    on_hold         INT,
    dropped         INT,
    plan_to_watch   INT
);

CREATE TABLE genre (
    genre_id    SERIAL PRIMARY KEY,
    genre_name  TEXT UNIQUE NOT NULL
);

CREATE TABLE studio (
    studio_id   SERIAL PRIMARY KEY,
    studio_name TEXT UNIQUE NOT NULL
);

CREATE TABLE anime_genre (
    anime_id INT REFERENCES anime(anime_id),
    genre_id INT REFERENCES genre(genre_id),
    PRIMARY KEY (anime_id, genre_id)
);

CREATE TABLE anime_studio (
    anime_id  INT REFERENCES anime(anime_id),
    studio_id INT REFERENCES studio(studio_id),
    PRIMARY KEY (anime_id, studio_id)
);

-- The csv has 10 columns Score-10 .. Score-1 with the number of users who
-- gave each score. Easier to work with as rows.
CREATE TABLE anime_score_dist (
    anime_id    INT REFERENCES anime(anime_id),
    score_value INT CHECK (score_value BETWEEN 1 AND 10),
    vote_count  INT,
    PRIMARY KEY (anime_id, score_value)
);

CREATE INDEX ON anime_genre (genre_id);
CREATE INDEX ON anime_studio (studio_id);
CREATE INDEX ON anime (score) WHERE score IS NOT NULL;
CREATE INDEX ON anime (members);
