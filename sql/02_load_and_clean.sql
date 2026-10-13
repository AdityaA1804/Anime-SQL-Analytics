-- Load the csv and clean it into the real tables.
--
/* Step 1 loads everything as text into anime_raw,
because the csv uses the word 'Unknown' for missing values even in number columns,
so a direct typed load fails on the first row that has one. */
--
-- IMPORTANT :Change the path in the COPY statement below to where anime.csv
-- Forward slashes work on Windows too.

----------------------------------------------------------------
-- step 1: raw load
----------------------------------------------------------------
DROP TABLE IF EXISTS anime_raw;

CREATE TABLE anime_raw (
    mal_id text, name text, score text, genres text, english_name text,
    japanese_name text, type text, episodes text, aired text, premiered text,
    producers text, licensors text, studios text, source text, duration text,
    rating text, ranked text, popularity text, members text, favorites text,
    watching text, completed text, on_hold text, dropped text, plan_to_watch text,
    score_10 text, score_9 text, score_8 text, score_7 text, score_6 text,
    score_5 text, score_4 text, score_3 text, score_2 text, score_1 text
);

COPY anime_raw FROM 'D:/Projects/Anime_Data/anime-sql/data/anime.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- should be 17562 as per csv
SELECT COUNT(*) FROM anime_raw;

----------------------------------------------------------------
-- step 2: helper functions
----------------------------------------------------------------
/* The Aired column is a free text range
like "Apr 3, 1998 to Apr 24, 1999", "Jul, 2003", "1986", "Oct 5, 2020 to ?"
so I split on " to " and parse each half separately.
When only a month or year is given I default to the start of that period for the from-date
and the end of it for the to-date, otherwise things like "Jan 12, 2010 to 2010" end up ending before they start. */

CREATE OR REPLACE FUNCTION parse_mal_date(s text, is_end boolean DEFAULT false)
RETURNS date
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    d date;
BEGIN
    s := btrim(s);
    IF s IS NULL OR s IN ('?', 'Unknown', '') THEN
        RETURN NULL;
    END IF;

    IF s ~ '^[A-Z][a-z]{2} \d{1,2}, \d{4}$' THEN          -- Apr 3, 1998
        RETURN to_date(s, 'Mon DD, YYYY');

    ELSIF s ~ '^[A-Z][a-z]{2}, \d{4}$' THEN                 -- Apr, 1998
        d := to_date(replace(s, ',', ''), 'Mon YYYY');
        IF is_end THEN d := d + interval '1 month' - interval '1 day'; END IF;
        RETURN d;

    ELSIF s ~ '^\d{4}$' THEN                                -- 1998
        d := to_date(s, 'YYYY');
        IF is_end THEN d := d + interval '1 year' - interval '1 day'; END IF;
        RETURN d;
    END IF;

    RAISE WARNING 'could not parse date: %', s;
    RETURN NULL;
END $$;


-- Duration looks like "24 min. per ep.", "1 hr. 55 min.", "2 hr.", "30 sec."
-- Pull out each unit with a regex and add them up in minutes.
CREATE OR REPLACE FUNCTION parse_mal_duration(s text)
RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN s IS NULL OR s = 'Unknown' THEN NULL
           ELSE coalesce((regexp_match(s, '(\d+) hr'))[1]::numeric, 0) * 60
              + coalesce((regexp_match(s, '(\d+) min'))[1]::numeric, 0)
              + coalesce((regexp_match(s, '(\d+) sec'))[1]::numeric, 0) / 60
           END
$$;

----------------------------------------------------------------
-- step 3: main table
----------------------------------------------------------------
INSERT INTO anime
SELECT
    mal_id::int,
    name,
    nullif(english_name, 'Unknown'),
    type,
    source,
    nullif(rating, 'Unknown'),
    nullif(episodes, 'Unknown')::int,
    parse_mal_date(split_part(nullif(aired, 'Unknown'), ' to ', 1)),
    parse_mal_date(split_part(aired, ' to ', 2), true),
    nullif(aired, 'Unknown'),
    (regexp_match(premiered, '^(Winter|Spring|Summer|Fall)'))[1],
    (regexp_match(premiered, '(\d{4})$'))[1]::int,
    parse_mal_duration(duration),
    nullif(score, 'Unknown')::numeric,
    nullif(ranked, 'Unknown')::numeric::int,     -- comes through as '28.0'
    popularity::int,
    members::int,
    favorites::int,
    watching::int,
    completed::int,
    on_hold::int,
    dropped::int,
    plan_to_watch::int
FROM anime_raw;

----------------------------------------------------------------
-- step 4: genres and studios
----------------------------------------------------------------
-- split the comma separated cell into rows, trim, dedupe

INSERT INTO genre (genre_name)
SELECT DISTINCT btrim(g)
FROM anime_raw, unnest(string_to_array(genres, ',')) AS g
WHERE genres <> 'Unknown';

INSERT INTO anime_genre
SELECT DISTINCT r.mal_id::int, g.genre_id
FROM anime_raw r,
     unnest(string_to_array(r.genres, ',')) AS x
JOIN genre g ON g.genre_name = btrim(x)
WHERE r.genres <> 'Unknown';

-- same thing for studios
INSERT INTO studio (studio_name)
SELECT DISTINCT btrim(s)
FROM anime_raw, unnest(string_to_array(studios, ',')) AS s
WHERE studios <> 'Unknown';

INSERT INTO anime_studio
SELECT DISTINCT r.mal_id::int, s.studio_id
FROM anime_raw r,
     unnest(string_to_array(r.studios, ',')) AS x
JOIN studio s ON s.studio_name = btrim(x)
WHERE r.studios <> 'Unknown';

----------------------------------------------------------------
-- step 5: score distribution
----------------------------------------------------------------
/* unpivot the 10 score columns. A single 'Unknown' next to real numbers just means nobody gave that score,
so treat it as 0. Rows where all ten are Unknown are skipped. */

INSERT INTO anime_score_dist
SELECT r.mal_id::int, v.score_value, coalesce(nullif(v.cnt, 'Unknown')::numeric::int, 0)
FROM anime_raw r,
     LATERAL (VALUES (10, score_10), (9, score_9), (8, score_8), (7, score_7), (6, score_6),
                     (5, score_5),   (4, score_4), (3, score_3), (2, score_2), (1, score_1))
     AS v(score_value, cnt)
WHERE score_10 <> 'Unknown' OR score_9 <> 'Unknown' OR score_8 <> 'Unknown'
   OR score_7  <> 'Unknown' OR score_6 <> 'Unknown' OR score_5 <> 'Unknown'
   OR score_4  <> 'Unknown' OR score_3 <> 'Unknown' OR score_2 <> 'Unknown'
   OR score_1  <> 'Unknown';


----------------------------------------------------------------
-- step 6: Data Summary
----------------------------------------------------------------

SELECT 'anime' AS tbl,            count(*) FROM anime
UNION ALL SELECT 'genre',         count(*) FROM genre
UNION ALL SELECT 'studio',        count(*) FROM studio
UNION ALL SELECT 'anime_genre',   count(*) FROM anime_genre
UNION ALL SELECT 'anime_studio',  count(*) FROM anime_studio
UNION ALL SELECT 'score_dist',    count(*) FROM anime_score_dist;
