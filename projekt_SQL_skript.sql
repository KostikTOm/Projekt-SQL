-- ============================================================
-- PROJEKT Z SQL – Dostupnost základních potravin v ČR
-- ============================================================
-- POZOR: Nahraďte "jmeno_prijmeni" svým skutečným jménem a příjmením.
-- Například: t_jan_novak_project_SQL_primary_final
-- ============================================================


-- ============================================================
-- ČÁST 1: PRIMÁRNÍ TABULKA
-- Spojení dat o mzdách a cenách potravin za shodná období v ČR
-- ============================================================

CREATE OR REPLACE TABLE t_jmeno_prijmeni_project_SQL_primary_final AS
WITH
    -- Roční průměry mezd podle odvětví
    -- (přepočtení zaměstnanci, průměrná hrubá mzda)
    wages_annual AS (
        SELECT
            cp.payroll_year                 AS year,
            cp.industry_branch_code,
            cpib.name                       AS industry_branch_name,
            ROUND(AVG(cp.value), 2)         AS avg_wages
        FROM czechia_payroll cp
        JOIN czechia_payroll_industry_branch cpib
            ON cp.industry_branch_code = cpib.code
        WHERE cp.value_type_code = 1        -- průměrná hrubá mzda na zaměstnance
          AND cp.calculation_code = 100     -- přepočtený stav zaměstnanců
        GROUP BY
            cp.payroll_year,
            cp.industry_branch_code,
            cpib.name
    ),

    -- Roční průměry cen potravin podle kategorie (celostátní průměr)
    prices_annual AS (
        SELECT
            YEAR(cp.date_from)              AS year,
            cp.category_code,
            cpc.name                        AS food_category_name,
            cpc.price_value                 AS food_price_value,
            cpc.price_unit                  AS food_price_unit,
            ROUND(AVG(cp.value), 2)         AS avg_price
        FROM czechia_price cp
        JOIN czechia_price_category cpc
            ON cp.category_code = cpc.code
        WHERE cp.region_code IS NULL        -- celostátní průměr (bez rozlišení krajů)
        GROUP BY
            YEAR(cp.date_from),
            cp.category_code,
            cpc.name,
            cpc.price_value,
            cpc.price_unit
    )

-- Průnik let, pro která existují obě datové sady zároveň
SELECT
    w.year,
    w.industry_branch_code,
    w.industry_branch_name,
    w.avg_wages,
    p.category_code         AS food_category_code,
    p.food_category_name,
    p.food_price_value,
    p.food_price_unit,
    p.avg_price
FROM wages_annual w
INNER JOIN prices_annual p ON w.year = p.year
ORDER BY
    w.year,
    w.industry_branch_name,
    p.food_category_name;


-- ============================================================
-- ČÁST 2: SEKUNDÁRNÍ TABULKA
-- HDP, GINI a populace evropských zemí za shodné období
-- ============================================================

CREATE OR REPLACE TABLE t_jmeno_prijmeni_project_SQL_secondary_final AS
SELECT
    e.country,
    c.capital_city,
    c.currency_name,
    c.region_in_world,
    e.year,
    e.GDP,
    e.gini,
    e.population,
    e.taxes
FROM economies e
JOIN countries c ON e.country = c.country
WHERE c.continent = 'Europe'
  AND e.GDP IS NOT NULL
  AND e.year BETWEEN (
        SELECT MIN(year) FROM t_jmeno_prijmeni_project_SQL_primary_final
      )
      AND (
        SELECT MAX(year) FROM t_jmeno_prijmeni_project_SQL_primary_final
      )
ORDER BY e.country, e.year;


-- ============================================================
-- VÝZKUMNÁ OTÁZKA 1:
-- Rostou mzdy ve všech odvětvích, nebo v některých klesají?
-- ============================================================

WITH distinct_wages AS (
    -- Deduplikace – každé odvětví a rok jednou
    SELECT DISTINCT
        year,
        industry_branch_code,
        industry_branch_name,
        avg_wages
    FROM t_jmeno_prijmeni_project_SQL_primary_final
),
wage_changes AS (
    SELECT
        year,
        industry_branch_code,
        industry_branch_name,
        avg_wages,
        LAG(avg_wages) OVER (
            PARTITION BY industry_branch_code
            ORDER BY year
        ) AS prev_avg_wages,
        ROUND(
            (avg_wages
                - LAG(avg_wages) OVER (PARTITION BY industry_branch_code ORDER BY year))
            / LAG(avg_wages) OVER (PARTITION BY industry_branch_code ORDER BY year)
            * 100,
        2) AS yoy_change_pct
    FROM distinct_wages
)
SELECT
    year,
    industry_branch_name,
    avg_wages,
    prev_avg_wages,
    yoy_change_pct,
    CASE
        WHEN yoy_change_pct < 0 THEN 'Pokles'
        WHEN yoy_change_pct = 0 THEN 'Beze změny'
        ELSE 'Nárůst'
    END AS trend
FROM wage_changes
WHERE prev_avg_wages IS NOT NULL
ORDER BY industry_branch_name, year;


-- ============================================================
-- VÝZKUMNÁ OTÁZKA 2:
-- Kolik litrů mléka a kilogramů chleba si bylo možné koupit
-- v prvním a posledním srovnatelném roce?
-- ============================================================

WITH first_last_years AS (
    SELECT
        MIN(year) AS first_year,
        MAX(year) AS last_year
    FROM t_jmeno_prijmeni_project_SQL_primary_final
),
avg_wage_per_year AS (
    -- Celostátní průměr mezd přes všechna odvětví
    SELECT DISTINCT
        year,
        ROUND(AVG(avg_wages) OVER (PARTITION BY year), 2) AS national_avg_wage
    FROM t_jmeno_prijmeni_project_SQL_primary_final
),
milk_bread_prices AS (
    SELECT DISTINCT
        year,
        food_category_name,
        food_price_unit,
        avg_price
    FROM t_jmeno_prijmeni_project_SQL_primary_final
    WHERE food_category_name LIKE '%mléko%'
       OR food_category_name LIKE '%Chléb%'
       OR food_category_name LIKE '%chléb%'
)
SELECT
    w.year,
    w.national_avg_wage                                 AS avg_monthly_wage_czk,
    m.food_category_name,
    m.avg_price                                         AS price_per_unit,
    m.food_price_unit,
    ROUND(w.national_avg_wage / m.avg_price, 0)        AS quantity_affordable
FROM avg_wage_per_year w
JOIN milk_bread_prices m   ON w.year = m.year
JOIN first_last_years  fl  ON w.year = fl.first_year
                           OR w.year = fl.last_year
ORDER BY w.year, m.food_category_name;


-- ============================================================
-- VÝZKUMNÁ OTÁZKA 3:
-- Která kategorie potravin zdražuje nejpomaleji?
-- (nejnižší průměrný meziroční percentuální nárůst)
-- ============================================================

WITH distinct_prices AS (
    SELECT DISTINCT
        year,
        food_category_code,
        food_category_name,
        avg_price
    FROM t_jmeno_prijmeni_project_SQL_primary_final
),
price_changes AS (
    SELECT
        year,
        food_category_code,
        food_category_name,
        avg_price,
        LAG(avg_price) OVER (
            PARTITION BY food_category_code
            ORDER BY year
        ) AS prev_avg_price,
        ROUND(
            (avg_price
                - LAG(avg_price) OVER (PARTITION BY food_category_code ORDER BY year))
            / LAG(avg_price) OVER (PARTITION BY food_category_code ORDER BY year)
            * 100,
        2) AS yoy_change_pct
    FROM distinct_prices
)
SELECT
    food_category_name,
    ROUND(AVG(yoy_change_pct), 2)  AS avg_annual_growth_pct
FROM price_changes
WHERE yoy_change_pct IS NOT NULL
GROUP BY food_category_code, food_category_name
ORDER BY avg_annual_growth_pct ASC;
-- Přidejte LIMIT 1 pro zobrazení pouze nejpomalejší kategorie


-- ============================================================
-- VÝZKUMNÁ OTÁZKA 4:
-- Existuje rok, kdy byl meziroční nárůst cen potravin výrazně
-- vyšší než růst mezd? (rozdíl větší než 10 %)
-- ============================================================

WITH distinct_wages AS (
    SELECT DISTINCT year, industry_branch_code, avg_wages
    FROM t_jmeno_prijmeni_project_SQL_primary_final
),
distinct_prices AS (
    SELECT DISTINCT year, food_category_code, avg_price
    FROM t_jmeno_prijmeni_project_SQL_primary_final
),
annual_avg_wages AS (
    SELECT
        year,
        ROUND(AVG(avg_wages), 2) AS avg_national_wage
    FROM distinct_wages
    GROUP BY year
),
annual_avg_prices AS (
    SELECT
        year,
        ROUND(AVG(avg_price), 2) AS avg_national_price
    FROM distinct_prices
    GROUP BY year
),
combined AS (
    SELECT
        w.year,
        w.avg_national_wage,
        LAG(w.avg_national_wage) OVER (ORDER BY w.year)  AS prev_wage,
        p.avg_national_price,
        LAG(p.avg_national_price) OVER (ORDER BY w.year) AS prev_price
    FROM annual_avg_wages w
    JOIN annual_avg_prices p ON w.year = p.year
)
SELECT
    year,
    ROUND((avg_national_wage - prev_wage) / prev_wage * 100, 2)         AS wage_growth_pct,
    ROUND((avg_national_price - prev_price) / prev_price * 100, 2)      AS price_growth_pct,
    ROUND(
        (avg_national_price - prev_price) / prev_price * 100
        - (avg_national_wage - prev_wage) / prev_wage * 100,
    2)                                                                   AS difference_pct,
    CASE
        WHEN ROUND(
                (avg_national_price - prev_price) / prev_price * 100
                - (avg_national_wage - prev_wage) / prev_wage * 100,
             2) > 10
        THEN 'ANO – ceny rostly výrazně rychleji než mzdy'
        ELSE 'NE'
    END AS significant_gap
FROM combined
WHERE prev_wage IS NOT NULL
  AND prev_price IS NOT NULL
ORDER BY year;


-- ============================================================
-- VÝZKUMNÁ OTÁZKA 5:
-- Má výška HDP vliv na mzdy a ceny potravin v ČR?
-- Projeví se výrazný nárůst HDP na cenách či mzdách
-- ve stejném nebo následujícím roce?
-- ============================================================

WITH distinct_wages AS (
    SELECT DISTINCT year, industry_branch_code, avg_wages
    FROM t_jmeno_prijmeni_project_SQL_primary_final
),
distinct_prices AS (
    SELECT DISTINCT year, food_category_code, avg_price
    FROM t_jmeno_prijmeni_project_SQL_primary_final
),
annual_avg_wages AS (
    SELECT year, ROUND(AVG(avg_wages), 2) AS avg_national_wage
    FROM distinct_wages
    GROUP BY year
),
annual_avg_prices AS (
    SELECT year, ROUND(AVG(avg_price), 2) AS avg_national_price
    FROM distinct_prices
    GROUP BY year
),
czechia_gdp AS (
    SELECT
        year,
        GDP,
        LAG(GDP) OVER (ORDER BY year)  AS prev_GDP,
        ROUND(
            (GDP - LAG(GDP) OVER (ORDER BY year))
            / LAG(GDP) OVER (ORDER BY year) * 100,
        2)                             AS gdp_growth_pct
    FROM t_jmeno_prijmeni_project_SQL_secondary_final
    WHERE country = 'Czech Republic'
      AND GDP IS NOT NULL
)
SELECT
    g.year,
    g.GDP,
    g.gdp_growth_pct,
    w.avg_national_wage,
    ROUND(
        (w.avg_national_wage
            - LAG(w.avg_national_wage) OVER (ORDER BY w.year))
        / LAG(w.avg_national_wage) OVER (ORDER BY w.year) * 100,
    2) AS wage_growth_pct,
    p.avg_national_price,
    ROUND(
        (p.avg_national_price
            - LAG(p.avg_national_price) OVER (ORDER BY p.year))
        / LAG(p.avg_national_price) OVER (ORDER BY p.year) * 100,
    2) AS price_growth_pct
FROM czechia_gdp g
JOIN annual_avg_wages  w ON g.year = w.year
JOIN annual_avg_prices p ON g.year = p.year
WHERE g.prev_GDP IS NOT NULL
ORDER BY g.year;
