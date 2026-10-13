# Anime ratings & retention — a PostgreSQL project

<!-- 2-3 sentences in your own words. Why anime, why this dataset, what you
     wanted to find out. Something like: "I watch a lot of anime and always
     wondered whether the shows everyone rates highly are actually the ones
     people finish. This project uses the MyAnimeList dataset to find out." -->

Dataset: MyAnimeList catalogue from Kaggle (~17.5k titles, 35 columns).
Database: PostgreSQL 18, pgAdmin.

## The data problem

The CSV is one wide table and every column is text. Missing values are the literal word `Unknown`,
even in number columns. Genres and studios are packed into comma separated cells.
Air dates are free text in three different formats (`Apr 3, 1998`, `Jul, 2003`, `1986`) and sometimes open ended (`Oct 5, 2020 to ?`).
Duration mixes `24 min. per ep.` with `1 hr. 55 min.`

So before any analysis the load script splits that into six tables:

```
anime ──< anime_genre >── genre
  │
  ├──< anime_studio >── studio
  │
  └──< anime_score_dist      (one row per title per score 1-10)
```

Everything is done in SQL: regex functions for the dates and durations,
`unnest(string_to_array(...))` to explode the genre lists, and a
`LATERAL (VALUES ...)` to unpivot the ten score columns into rows.

## Questions

1. Top 5 anime in each genre
2. Which genres do people drop the most?
3. How many genres make up 80% of all engagement?
4. Are the big studios getting better or worse over time?
5. Does MAL's displayed score actually match the vote counts?
6. Are there genres that are rated highly or watched heavily, but still dropped a lot?
7. Does episode count change whether people finish a show?
8. Sequels vs first seasons
9. Which studios are the most consistent (not just the highest rated)?
10. Backlog kings — shows everyone saves but nobody starts

## What I found

<!-- Pick the 4-5 that surprised you. Write them as sentences, not a table.
     Below are the numbers from my run so you have them; rewrite in your own
     words and delete the ones you don't care about. -->

- Drop rate is a genre property. Military and Thriller have the lowest
  (~3.7%), Shoujo Ai and Josei the highest (8.5%, 7.1%).
- Q6: Samurai and Historical are top-3 on score and still top-10 on drop
  rate. Ecchi is the opposite — bottom-5 on score, top-15 on members,
  top-10 on drops.
- Shows with 100+ episodes have the highest average score (7.66) *and* the
  highest drop rate (10.8%). Long shows filter their audience both ways.
- Sequels score 0.55 higher than first seasons and are dropped a third as
  often (2.2% vs 6.5%). Only people who already like the show are watching.
- MAL's displayed score is not the average of the votes. *Pingu in the City*
  shows 6.59, but its 21k votes average 8.15.
- Mononoke, Planetes, Kaiba, Gankutsuou — all rated 8+, all 15+ years old,
  and over half the people who added them still haven't started.

<!-- add your own screenshot(s) of the result grid for your favourite
     query: ![Q6 results](screenshots/q6.png) -->

## Running it

1. Create a database, open the Query Tool on it.
2. Run `sql/01_create_tables.sql`.
3. Open `sql/02_load_and_clean.sql`, change the path on the `COPY` line to
   where `data/anime.csv` is on your machine, run it. If `COPY` complains
   about permissions, right-click `anime_raw` → Import/Export Data instead.
4. `sql/03_analysis.sql` — highlight one question block at a time and run it.
5. `sql/04_checks.sql` — every row should be 0 except the two marked expected.
