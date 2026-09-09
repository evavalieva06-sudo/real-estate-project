/* Решаем ad hoc задачи: анализ данных для агентства недвижимости
 * 
 *
 * Автор: Валиева Ева 
 * Дата: 06.04.2026
*/

-- Задача 1: Время активности объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_id AS (
    SELECT f.id
    FROM real_estate.flats f
    JOIN real_estate."type" t USING (type_id)
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND (
            (ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
             AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits))
            OR ceiling_height IS NULL
        )
        AND type = 'город'
),
base AS (
    SELECT
        a.id,
        a.days_exposition,
        a.last_price,
        f.total_area,
        f.rooms,
        f.balcony,
        f.ceiling_height,
        CASE 
            WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
            ELSE 'Ленинградская область'
        END AS city_name,
        CASE  
            WHEN a.days_exposition BETWEEN 1 AND 30 THEN 'до месяца' 
            WHEN a.days_exposition BETWEEN 31 AND 90 THEN 'до трёх месяцев'
            WHEN a.days_exposition BETWEEN 91 AND 180 THEN 'до полугода'
            WHEN a.days_exposition >= 181 THEN 'более полугода'
            ELSE 'non category'
        END AS category,
        CASE  
            WHEN a.days_exposition BETWEEN 1 AND 30 THEN 1
            WHEN a.days_exposition BETWEEN 31 AND 90 THEN 2
            WHEN a.days_exposition BETWEEN 91 AND 180 THEN 3
            WHEN a.days_exposition >= 181 THEN 4
            ELSE 5
        END AS sort_key
    FROM real_estate.advertisement a
    JOIN filtered_id USING (id)
    JOIN real_estate.flats f USING (id)
    JOIN real_estate.city c USING (city_id)
    WHERE a.first_day_exposition 
        BETWEEN '2015-01-01' AND '2018-12-31'
)
SELECT
    city_name,
    category,
    COUNT(id) AS flats_total,
    ROUND(AVG(last_price::float / total_area)::numeric, 2) AS avg_price_per_m,
    ROUND(AVG(total_area)::numeric, 2) AS avg_area,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY rooms) AS median_rooms, --считаем медиану по комнатам и балконам
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY balcony) AS median_balcony,
    ROUND(AVG(ceiling_height)::numeric, 2) AS avg_ceiling,
    ROUND(COUNT(id)::numeric / SUM(COUNT(id)) OVER (PARTITION BY city_name), 4) AS SHARE --считаем долю объявлений
FROM base
GROUP BY city_name, category, sort_key
ORDER BY city_name, sort_key;



-- Задача 2: Сезонность объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:

  WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats 
    LEFT JOIN real_estate."type" t USING (type_id) 
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
            AND TYPE = 'город' --применяю фильтр только по городам 
    ),
-- Выведем объявления без выбросов:
-- Продолжите запрос здесь
-- Используйте id объявлений (СТЕ filtered_id), которые не содержат выбросы при анализе данных
pub AS ( --считаем публикации
  SELECT  
    COUNT(a.first_day_exposition) AS published,
    ROUND(AVG((LAST_price)::float / (total_area))::numeric,2) AS avg_price_per_m_pub,
    ROUND(AVG(total_area)::numeric,2) AS avg_area_pub,
    EXTRACT(MONTH FROM a.first_day_exposition) AS month_num,
    CASE EXTRACT(MONTH FROM a.first_day_exposition)::int
          WHEN 1 THEN 'январь'
          WHEN 2 THEN 'февраль'
          WHEN 3 THEN 'март'
          WHEN 4 THEN 'апрель'
          WHEN 5 THEN 'май'
          WHEN 6 THEN 'июнь'
          WHEN 7 THEN 'июль'
          WHEN 8 THEN 'август'
          WHEN 9 THEN 'сентябрь'
          WHEN 10 THEN 'октябрь'
          WHEN 11 THEN 'ноябрь'
          WHEN 12 THEN 'декабрь'
        END AS month_name
FROM real_estate.advertisement a 
JOIN real_estate.flats f USING(id)
JOIN filtered_id USING(id)
  WHERE 
      first_day_exposition 
      BETWEEN '2015-01-01'::timestamp 
      AND '2018-12-31'::timestamp
GROUP BY month_num, month_name
),
rem AS ( --считаем снятия
  SELECT
    COUNT(a.first_day_exposition + days_exposition * INTERVAL '1 day') AS removed,
    EXTRACT(MONTH FROM a.first_day_exposition + days_exposition * INTERVAL '1 day') AS month_num,
    CASE EXTRACT(MONTH FROM a.first_day_exposition + days_exposition * INTERVAL '1 day')::int
          WHEN 1 THEN 'январь'
          WHEN 2 THEN 'февраль'
          WHEN 3 THEN 'март'
          WHEN 4 THEN 'апрель'
          WHEN 5 THEN 'май'
          WHEN 6 THEN 'июнь'
          WHEN 7 THEN 'июль'
          WHEN 8 THEN 'август'
          WHEN 9 THEN 'сентябрь'
          WHEN 10 THEN 'октябрь'
          WHEN 11 THEN 'ноябрь'
          WHEN 12 THEN 'декабрь'
        END AS month_name,
    ROUND(AVG((LAST_price)::float / (total_area))::numeric,2) AS avg_price_per_m_rem, --добавим статистику по снятым объявлениям
    ROUND(AVG(total_area)::numeric,2) AS avg_area_rem
FROM real_estate.advertisement a 
JOIN filtered_id USING(id)
JOIN real_estate.flats f USING(id)
   WHERE 
   a.days_exposition IS NOT NULL 
   AND a.first_day_exposition + days_exposition * INTERVAL '1 day' 
   BETWEEN '2015-01-01'::timestamp 
   AND '2018-12-31'::timestamp 
GROUP BY month_num, month_name
)
SELECT --считаем статистику публикаций и снятий по месяцам
COALESCE(pub.month_name, rem.month_name) AS month,
  COALESCE(published, 0) AS published,
  RANK () OVER (ORDER BY published DESC) AS rank_pub,
  COALESCE(removed, 0) AS removed,
  RANK () OVER (ORDER BY removed DESC) AS rank_rem,
ROUND( published::numeric / (published + removed), 2) AS published_share, --добавляем доли по объявлениям
ROUND( removed::numeric / (published + removed),  2) AS removed_share,
  avg_price_per_m_pub,
  avg_area_pub,
  avg_price_per_m_rem,
  avg_area_rem
FROM pub  
FULL JOIN rem USING (month_num, month_name)   
ORDER BY month_num;
