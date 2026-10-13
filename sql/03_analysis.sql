-- Analysis queries. Each block is independent, highlight one and run it.
--
-- Most queries only look at titles with at least 10k members, otherwise the
-- top of every list is some obscure OVA with 200 votes and a 9.0.


-- =====================================================================
-- Q1. Top 5 anime in each genre by score
-- =====================================================================
SELECT 'Q1. Top 5 anime in each genre by score' AS question;
-- row_number inside each genre so I can keep just the first 5

WITH ranked AS (
    SELECT g.genre_name, a.name, a.score, a.members,
           row_number() OVER (PARTITION BY g.genre_id ORDER BY a.score DESC, a.members DESC) AS rn
    FROM anime a
    JOIN anime_genre ag ON ag.anime_id = a.anime_id
    JOIN genre g ON g.genre_id = ag.genre_id
    WHERE a.score IS NOT NULL AND a.members >= 10000
)
SELECT genre_name, rn, name, score, members
FROM ranked
WHERE rn <= 5
  AND genre_name IN ('Action', 'Romance', 'Slice of Life', 'Mystery', 'Sports')  -- remove this line for all genres
ORDER BY genre_name, rn;


-- =====================================================================
-- Q2. Which genres do people drop the most?
-- =====================================================================
SELECT 'Q2. Which genres do people drop the most?' AS question;
/* drop rate = dropped / (completed + dropped), i.e. of the people who reached an end state,
how many gave up. Ignoring 'watching' and 'on hold' since those are still undecided. */

SELECT g.genre_name,
       count(*) AS titles,
       sum(a.completed) AS completed,
       sum(a.dropped) AS dropped,
       round(100.0 * sum(a.dropped) / (sum(a.completed) + sum(a.dropped)), 2) AS drop_rate_pct
FROM anime a
JOIN anime_genre ag ON ag.anime_id = a.anime_id
JOIN genre g ON g.genre_id = ag.genre_id
WHERE a.members >= 10000
GROUP BY g.genre_name
HAVING count(*) >= 30
ORDER BY drop_rate_pct DESC;


-- =====================================================================
-- Q3. How many genres make up 80% of all engagement?
-- =====================================================================
SELECT 'Q3. How many genres make up 80% of all engagement?' AS question;
/* running total of members with a window function. Note a title with 3 genres is counted in all 3,
so this is "share of attention" not "share of users". */

WITH per_genre AS (
    SELECT g.genre_name, sum(a.members) AS members
    FROM anime a
    JOIN anime_genre ag ON ag.anime_id = a.anime_id
    JOIN genre g ON g.genre_id = ag.genre_id
    GROUP BY g.genre_name
)
SELECT genre_name,
       members,
       round(100.0 * members / sum(members) OVER (), 2) AS share_pct,
       round(100.0 * sum(members) OVER (ORDER BY members DESC) / sum(members) OVER (), 2) AS cumulative_pct
FROM per_genre
ORDER BY members DESC;


-- =====================================================================
-- Q4. Are the big studios getting better or worse?
-- =====================================================================
SELECT 'Q4. Are the big studios getting better or worse?' AS question;
/* avg score per year for the 4 studios with the most TV anime,
with a  3 year moving average to smooth out the noise, and change vs last year. */

WITH top_studios AS (
    SELECT s.studio_id, s.studio_name
    FROM studio s
    JOIN anime_studio ast ON ast.studio_id = s.studio_id
    JOIN anime a ON a.anime_id = ast.anime_id
    WHERE a.type = 'TV' AND a.score IS NOT NULL
    GROUP BY s.studio_id, s.studio_name
    ORDER BY count(*) DESC
    LIMIT 4
),
yearly AS (
    SELECT ts.studio_name,
           extract(year FROM a.aired_from)::int AS yr,
           count(*) AS titles,
           round(avg(a.score), 2) AS avg_score
    FROM top_studios ts
    JOIN anime_studio ast ON ast.studio_id = ts.studio_id
    JOIN anime a ON a.anime_id = ast.anime_id
    WHERE a.type = 'TV' AND a.score IS NOT NULL AND a.aired_from IS NOT NULL
    GROUP BY ts.studio_name, 2
)
SELECT studio_name, yr, titles, avg_score,
       round(avg(avg_score) OVER (PARTITION BY studio_name ORDER BY yr ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS moving_avg_3yr,
       round(avg_score - lag(avg_score) OVER (PARTITION BY studio_name ORDER BY yr), 2) AS change_vs_prev_yr
FROM yearly
WHERE yr >= 2010
ORDER BY studio_name, yr;


-- =====================================================================
-- Q5. Does MAL's score actually match the votes?
-- =====================================================================
SELECT 'Q5. Does MAL''s score actually match the votes?' AS question;
/* MAL shows a score, and also how many people gave each 1-10. If I recompute the average from the vote counts it should match. 
It mostly does, but not always. */

WITH recomputed AS (
    SELECT anime_id,
           sum(vote_count) AS votes,
           round(sum(score_value * vote_count)::numeric / sum(vote_count), 2) AS from_votes
    FROM anime_score_dist
    GROUP BY anime_id
    HAVING sum(vote_count) >= 1000
)
SELECT a.name, a.type, a.score AS mal_score, r.from_votes, round(a.score - r.from_votes, 2) AS diff, r.votes
FROM anime a
JOIN recomputed r USING (anime_id)
WHERE a.score IS NOT NULL
  AND abs(a.score - r.from_votes) > 0.15
ORDER BY abs(a.score - r.from_votes) DESC
LIMIT 20;

/* Interesting: Pingu in the City is listed at 6.59 but the votes average 8.15.
MAL's wiki says they use a weighted score that pulls low-vote titles toward the global mean, 
which would explain the small diffs, but not one this big. */

-- =====================================================================
-- Q6. Highly rated / heavily voted genres that people still drop
-- =====================================================================
SELECT 'Q6. Highly rated / heavily voted genres that people still drop' AS question;
/* A genre can score well and still be one people abandon. 
Rank every genre on score, on votes and on drop rate,
then look for ones that are top half on score or votes AND top half on drop rate. */

WITH genre_stats AS (
    SELECT g.genre_name,
           count(*) AS titles,
           round(avg(a.score), 2) AS avg_score,
           sum(a.members) AS members,
           round(100.0 * sum(a.dropped) / (sum(a.completed) + sum(a.dropped)), 2) AS drop_rate_pct
    FROM anime a
    JOIN anime_genre ag ON ag.anime_id = a.anime_id
    JOIN genre g ON g.genre_id = ag.genre_id
    WHERE a.members >= 10000 AND a.score IS NOT NULL
    GROUP BY g.genre_name
    HAVING count(*) >= 30
),
ranked AS (
    SELECT *,
           rank() OVER (ORDER BY avg_score DESC)     AS score_rank,
           rank() OVER (ORDER BY members DESC)       AS votes_rank,
           rank() OVER (ORDER BY drop_rate_pct DESC) AS drop_rank,
           count(*) OVER () AS n
    FROM genre_stats
)
SELECT genre_name, titles, avg_score, members, drop_rate_pct,
       score_rank, votes_rank, drop_rank,
       CASE WHEN score_rank <= n/2 AND drop_rank <= n/2 THEN 'rated well but dropped'
            WHEN votes_rank <= n/2 AND drop_rank <= n/2 THEN 'popular but dropped'
            WHEN drop_rank <= n/2 THEN 'just dropped'
            ELSE 'fine' END AS verdict
FROM ranked
ORDER BY drop_rank;


-- =====================================================================
-- Q7. Does the number of episodes change whether people finish?
-- =====================================================================
SELECT 'Q7. Does the number of episodes change whether people finish?' AS question;
/* bucket TV anime by length. Also showing what % of members are still "watching" since a more episodes leads to reduction in viewers. */

SELECT CASE WHEN episodes <= 13 THEN '01. 1-13 (one cour)'
            WHEN episodes <= 26 THEN '02. 14-26 (two cour)'
            WHEN episodes <= 52 THEN '03. 27-52 (year)'
            WHEN episodes <= 100 THEN '04. 53-100'
            ELSE '05. 100+' END AS length_bucket,
       count(*) AS titles,
       round(avg(score), 2) AS avg_score,
       round(100.0 * sum(dropped) / (sum(completed) + sum(dropped)), 2) AS drop_rate_pct,
       round(100.0 * sum(watching) / sum(members), 2) AS still_watching_pct,
       round(100.0 * sum(favorites) / sum(members), 2) AS favorite_pct
FROM anime
WHERE type = 'TV' AND episodes IS NOT NULL AND score IS NOT NULL AND members >= 10000
GROUP BY 1
ORDER BY 1;


-- =====================================================================
-- Q8. Sequels vs first seasons
-- =====================================================================
SELECT 'Q8. Sequels vs first seasons' AS question;
/* No sequel flag in the data, so I'm guessing from the title: anything with "2nd Season", "Season 3", "Part 2", "II" etc.
Not perfect but catches most of them. 
Expectation: sequels score higher (only fans keep watching) but have fewer members. */

WITH tagged AS (
    SELECT *,
           CASE WHEN name ~* '(\d(nd|rd|th) season|(second|third|fourth) season|season \d|part \d|\m(II|III|IV)\M|2nd|3rd|final season)'
                THEN 'sequel' ELSE 'first season / standalone' END AS kind
    FROM anime
    WHERE type = 'TV' AND score IS NOT NULL AND members >= 10000
)
SELECT kind,
       count(*) AS titles,
       round(avg(score), 2) AS avg_score,
       round(avg(members)) AS avg_members,
       round(100.0 * sum(dropped) / (sum(completed) + sum(dropped)), 2) AS drop_rate_pct,
       round(100.0 * sum(favorites) / sum(members), 2) AS favorite_pct
FROM tagged
GROUP BY kind;

-- and to sanity check the regex, a sample of what got tagged as sequel:
SELECT 'Check to verify few Sequels Manually' AS question;

SELECT name 
FROM anime 
WHERE name ~* '(\d(nd|rd|th) season|(second|third|fourth) season|season \d|part \d|\m(II|III|IV)\M|2nd|3rd|final season)'
ORDER BY random()
LIMIT 20;


-- =====================================================================
-- Q9. Which studios are the most consistent?
-- =====================================================================
SELECT 'Q9. Which studios are the most consistent?' AS question;
/* Highest average is one thing, but a studio that's always 7.5 is more reliable than one that swings between 6 and 9.
Using stddev as the consistency measure. Only studios with 15+ scored TV titles. */

SELECT s.studio_name,
       count(*) AS titles,
       round(avg(a.score), 2) AS avg_score,
       round(stddev_samp(a.score), 2) AS score_stddev,
       min(a.score) AS worst,
       max(a.score) AS best,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY a.score)::numeric, 2) AS median_score
FROM studio s
JOIN anime_studio ast ON ast.studio_id = s.studio_id
JOIN anime a ON a.anime_id = ast.anime_id
WHERE a.type = 'TV' AND a.score IS NOT NULL AND a.members >= 10000
GROUP BY s.studio_name
HAVING count(*) >= 15
ORDER BY score_stddev ASC
LIMIT 15;


-- =====================================================================
-- Q10. Backlog kings: shows everyone plans to watch but hasn't started
-- =====================================================================
SELECT 'Q10. Backlog kings: shows everyone plans to watch but hasn''t started' AS question;
/* plan_to_watch / members. High ratio = lots of people saved it, few actually got round to it.
First version of this was all 2020 releases, which isn't backlog, it's just new.
So only counting things that aired before 2019 and have had time to be watched. */

WITH backlog AS (
    SELECT name, type, score, members, plan_to_watch, aired_from,
           round(100.0 * plan_to_watch / members, 1) AS backlog_pct,
           dense_rank() OVER (PARTITION BY type ORDER BY 1.0 * plan_to_watch / members DESC) AS rnk
    FROM anime
    WHERE members >= 100000 AND score IS NOT NULL
      AND aired_from < '2019-01-01'
)
SELECT type, rnk, name, extract(year FROM aired_from)::int AS year, score, members, plan_to_watch, backlog_pct
FROM backlog
WHERE rnk <= 8 AND type IN ('TV', 'Movie')
ORDER BY type, rnk;
