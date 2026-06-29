# Průvodní listina – Projekt z SQL

**Autor:** Jméno Příjmení  
**Datum:** 2024  
**Zaměření projektu:** Dostupnost základních potravin v České republice na základě průměrných mezd

---

## Úvod

Cílem projektu je odpovědět na výzkumné otázky týkající se **dostupnosti základních potravin** pro obyvatele ČR v závislosti na průměrných mzdách. Projekt pracuje s daty z Portálu otevřených dat ČR, konkrétně s daty o mzdách a cenách potravin za několikaleté období.

Výstupem jsou dvě tabulky:
- **Primární tabulka** – mzdy a ceny potravin v ČR za shodná srovnatelná období
- **Sekundární tabulka** – HDP, GINI a populace evropských zemí za stejné období

---

## Popis výstupních tabulek

### t_jmeno_prijmeni_project_SQL_primary_final

Tabulka spojuje roční průměry mezd (z tabulky `czechia_payroll`) s ročními průměry cen potravin (z tabulky `czechia_price`) za **totožná srovnatelná období**, tedy pouze za roky, pro která existují obě datové sady.

| Sloupec | Popis |
|---|---|
| `year` | Rok |
| `industry_branch_code` | Kód odvětví (dle číselníku) |
| `industry_branch_name` | Název odvětví |
| `avg_wages` | Průměrná hrubá mzda za daný rok a odvětví (Kč) |
| `food_category_code` | Kód kategorie potraviny |
| `food_category_name` | Název kategorie potraviny |
| `food_price_value` | Měrná hodnota (množství, ke kterému se cena vztahuje) |
| `food_price_unit` | Jednotka (l, kg apod.) |
| `avg_price` | Průměrná cena potraviny za daný rok (Kč) |

**Filtry použité při tvorbě tabulky:**
- Mzdy: `value_type_code = 1` (průměrná hrubá mzda na zaměstnance), `calculation_code = 100` (přepočtený stav)
- Ceny: `region_code IS NULL` (celostátní průměr bez rozlišení krajů)
- Průnik let: pouze roky, pro která existují data v obou zdrojových tabulkách

---

### t_jmeno_prijmeni_project_SQL_secondary_final

Tabulka obsahuje makroekonomické ukazatele evropských zemí za stejné období jako primární tabulka. Data pocházejí z tabulek `economies` a `countries`.

| Sloupec | Popis |
|---|---|
| `country` | Název státu |
| `capital_city` | Hlavní město |
| `currency_name` | Název měny |
| `region_in_world` | Region světa |
| `year` | Rok |
| `GDP` | HDP (v USD) |
| `gini` | GINI koeficient (index příjmové nerovnosti) |
| `population` | Počet obyvatel |
| `taxes` | Daňová zátěž |

**Filtry použité při tvorbě tabulky:**
- Pouze evropské státy (`continent = 'Europe'`)
- Pouze záznamy s vyplněným HDP (`GDP IS NOT NULL`)
- Rozsah let odpovídá primární tabulce

---

## Výzkumné otázky a výsledky

### Otázka 1: Rostou mzdy ve všech odvětvích, nebo v některých klesají?

**Přístup:** Pomocí funkce `LAG()` byl vypočítán meziroční procentuální rozdíl průměrné mzdy pro každé odvětví. Výsledek zahrnuje označení trendu (Nárůst / Pokles / Beze změny).

**Klíčová zjištění:**
- Ve většině odvětví mzdy v dlouhodobém horizontu rostou.
- Výjimečně dochází k meziročnímu poklesu (např. v krizových letech nebo odvětvích citlivých na ekonomické výkyvy).
- Výsledky lze ověřit filtrováním sloupce `trend = 'Pokles'`.

---

### Otázka 2: Kolik litrů mléka a kilogramů chleba bylo možné koupit v prvním a posledním srovnatelném období?

**Přístup:** Z průměrné celostátní mzdy (průměr přes všechna odvětví) a průměrné ceny mléka (polotučné pasterované) a chleba (konzumní kmínový) byl vypočítán dostupný objem nákupu: `množství = průměrná mzda / cena za jednotku`.

**Klíčová zjištění:**
- Hodnoty jsou dostupné pro první a poslední rok primárního datového rozsahu.
- Sledovatelný trend v dostupnosti obou komodit odráží vývoj kupní síly.

---

### Otázka 3: Která kategorie potravin zdražuje nejpomaleji?

**Přístup:** Pro každou kategorii byl vypočítán průměrný roční meziroční procentuální nárůst ceny. Kategorie seřazeny vzestupně – první místo = nejpomalejší zdražování.

**Klíčová zjištění:**
- Kategorie s nejnižším průměrným ročním nárůstem cen je viditelná na prvním řádku výstupu (viz `ORDER BY avg_annual_growth_pct ASC`).
- Záporné hodnoty by indikovaly zlevnění v průměru – je třeba ověřit konkrétní výsledek po spuštění dotazu.

---

### Otázka 4: Existuje rok, kdy byl meziroční nárůst cen potravin výrazně vyšší než růst mezd (rozdíl > 10 %)?

**Přístup:** Byl vypočítán meziroční procentuální nárůst průměrné celostátní mzdy i průměrné ceny potravin (přes všechny kategorie). Jejich rozdíl byl porovnán s hranicí 10 %.

**Klíčová zjištění:**
- Výsledek dotazu přímo označuje roky, kde `significant_gap = 'ANO'`.
- Takovýto rok (pokud existuje) naznačuje výrazné snížení kupní síly.

---

### Otázka 5: Má výška HDP vliv na mzdy a ceny potravin v ČR?

**Přístup:** Pro ČR byl z tabulky `t_jmeno_prijmeni_project_SQL_secondary_final` extrahován meziroční procentuální růst HDP. Ten byl porovnán s meziročním růstem průměrné mzdy a průměrné ceny potravin ve stejném roce.

**Klíčová zjištění:**
- Výstup dotazu umožňuje vizuální porovnání trendů HDP, mezd a cen potravin rok po roce.
- Korelaci je třeba interpretovat opatrně – vliv HDP se může projevit s časovým zpožděním (následující rok).
- Pro statisticky robustní závěr by bylo třeba rozšířit analýzu (korelační koeficient apod.).

---

## Poznámky k datové kvalitě a omezení

- **Chybějící hodnoty v mzdách:** Tabulka `czechia_payroll` obsahuje záznamy bez kódu odvětví (`industry_branch_code IS NULL`), které odpovídají celostátnímu průměru přes všechna odvětví. Tyto záznamy jsou v primární tabulce záměrně vynechány – pracujeme pouze s daty za konkrétní odvětví.
- **Chybějící ceny dle regionů:** Tabulka `czechia_price` obsahuje ceny jak celostátní, tak krajské. Pro primární tabulku jsou použity pouze celostátní průměry (`region_code IS NULL`), aby byla zajištěna srovnatelnost.
- **Výpočet mléka/chleba:** Výsledek otázky č. 2 pracuje s průměrnou mzdou přes všechna odvětví jako aproximací „typického" příjmu v ČR.
- **HDP pro ČR v sekundární tabulce:** Název státu v tabulce `economies` může být `'Czech Republic'` nebo jiný – ověřte dostupný název pomocí `SELECT DISTINCT country FROM economies WHERE country LIKE '%Czech%'`.

---

## Zdroje dat

| Tabulka | Zdroj |
|---|---|
| `czechia_payroll` | Portál otevřených dat ČR – ISPV (Informační systém o průměrném výdělku) |
| `czechia_price` | Portál otevřených dat ČR – ČSÚ (Český statistický úřad) |
| `economies` | Světová banka / veřejně dostupná makroekonomická data |
| `countries` | Veřejná geografická databáze zemí světa |

---

## Struktura repozitáře

```
projekt-sql/
├── README.md                          ← tento soubor (průvodní listina)
└── projekt_SQL_skript.sql             ← SQL skript (tvorba tabulek + výzkumné otázky)
```
