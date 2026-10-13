-- Sanity checks after loading. Run the whole thing,
-- every row should be 0 except the ones marked "expected" which are quirks in the source data.

SELECT 'rows lost between raw and anime' AS check_name,
       (SELECT count(*) FROM anime_raw) - (SELECT count(*) FROM anime) AS bad_rows
UNION ALL
SELECT 'aired text present but from-date did not parse',
       count(*) FROM anime WHERE aired_raw IS NOT NULL AND aired_from IS NULL
UNION ALL
SELECT 'duration text present but minutes did not parse',
       count(*) FROM (SELECT * FROM anime a JOIN anime_raw r ON r.mal_id::int = a.anime_id
                      WHERE r.duration <> 'Unknown' AND a.duration_min IS NULL) t
UNION ALL
SELECT 'titles with genres in csv but no rows in anime_genre',
       count(*) FROM anime_raw r
       WHERE r.genres <> 'Unknown'
         AND NOT EXISTS (SELECT 1 FROM anime_genre ag WHERE ag.anime_id = r.mal_id::int)
UNION ALL
SELECT 'score_dist titles without exactly 10 rows',
       count(*) FROM (SELECT anime_id FROM anime_score_dist GROUP BY 1 HAVING count(*) <> 10) t
UNION ALL
SELECT 'score outside 1-10',
       count(*) FROM anime WHERE score NOT BETWEEN 1 AND 10
UNION ALL
SELECT 'status counts add up to more than members',
       count(*) FROM anime WHERE watching + completed + on_hold + dropped + plan_to_watch > members
UNION ALL
SELECT 'aired_to before aired_from  (expected: 6, reversed in the source)',
       count(*) FROM anime WHERE aired_to < aired_from
UNION ALL
SELECT 'duplicate names  (expected: 3, different MAL ids with same title)',
       count(*) FROM (SELECT name FROM anime GROUP BY name HAVING count(*) > 1) t;
