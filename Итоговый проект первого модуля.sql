-- Задача 1: Время активности объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:

WITH limits AS (
    -- Вычисляем границы для отсечения выбросов (99‑й и 1‑й перцентили)
    -- для ключевых параметров недвижимости
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,  -- Макс. площадь (99 %)
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,          -- Макс. кол‑во комнат (99 %)
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,        -- Макс. балкон (99 %)
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,  -- Верх. граница высоты потолков (99 %)
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l  -- Ниж. граница высоты потолков (1 %)
    FROM real_estate.flats
),

filtered_id AS (
    -- Отбираем ID объявлений, где значения НЕ являются выбросами
    -- Сохраняем записи с пропущенными данными (IS NULL)
    SELECT id
    FROM real_estate.flats f
    WHERE
        total_area < (SELECT total_area_limit FROM limits)  -- Площадь ниже 99‑го перцентиля
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)  -- Комнат меньше лимита ИЛИ NULL
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)  -- Балкон меньше лимита ИЛИ NULL
        AND (
            (ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
             AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits))  -- Высота в допустимом диапазоне
            OR ceiling_height IS NULL  -- ИЛИ NULL
        )
),

base AS (
    -- Основной набор данных с присоединением справочников
    SELECT
        a.id,
        a.first_day_exposition,  -- Дата публикации объявления
        a.days_exposition,       -- Длительность экспозиции (дней)
        a.last_price,           -- Последняя цена
        f.total_area,           -- Общая площадь
        f.rooms,                -- Количество комнат
        f.balcony,              -- Наличие/размер балкона
        f.ceiling_height,       -- Высота потолков
        c.city,                 -- Город
        t.type                   -- Тип локации (город/область)
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON f.id = a.id
    JOIN real_estate.city c ON c.city_id = f.city_id
    JOIN real_estate.type t ON t.type_id = f.type_id
    WHERE a.id IN (SELECT id FROM filtered_id)  -- Только объявления без выбросов
      AND EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018  -- Период 2015–2018 гг.
      AND t.type = 'город'  -- Только городские объявления
),

prepared AS (
    -- Подготовка данных для анализа: категоризация и расчёт метрик
    SELECT *,
        CASE
            WHEN city = 'Санкт-Петербург' THEN 'SPB'
            ELSE 'Leningrad_region'
        END AS region,  -- Группировка по регионам

        CASE
            WHEN days_exposition BETWEEN 1 AND 30 THEN '1-30 days'
            WHEN days_exposition BETWEEN 31 AND 90 THEN '31-90 days'
            WHEN days_exposition BETWEEN 91 AND 180 THEN '91-180 days'
            WHEN days_exposition >= 181 THEN '181+ days'
            ELSE 'non category'
        END AS activity_category,  -- Категоризация длительности экспозиции

        last_price / NULLIF(total_area, 0) AS price_per_sqm  -- Цена за кв. м (защита от деления на 0)
    FROM base
)

-- Финальный запрос: агрегация по регионам и категориям активности
SELECT
    region,
    activity_category,
    COUNT(*) AS ads_cnt,  -- Количество объявлений в группе
    AVG(price_per_sqm) AS avg_price_per_sqm,  -- Ср. цена за кв. м
    AVG(total_area) AS avg_area,  -- Ср. площадь
    AVG(rooms) AS avg_rooms,  -- Ср. количество комнат
    AVG(balcony) AS avg_balcony  -- Ср. значение балкона
FROM prepared
GROUP BY region, activity_category
ORDER BY region, activity_category;

-- Задача 2: Сезонность объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:

WITH limits AS (
    -- Повторное вычисление границ выбросов (аналогично Задаче 1)
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),

filtered_id AS (
    -- Фильтрация ID по тем же критериям выбросов
    SELECT id
    FROM real_estate.flats f
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND (
            (ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
             AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits))
            OR ceiling_height IS NULL
        )
),

base AS (
    -- Базовый набор данных (без лишних полей для анализа сезонности)
    SELECT
        a.id,
        a.first_day_exposition,  -- Дата публикации
        a.days_exposition,       -- Длительность экспозиции
        f.total_area,           -- Площадь
        a.last_price,           -- Цена
        c.city,                 -- Город
        t.type                   -- Тип локации
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON f.id = a.id
    JOIN real_estate.city c ON c.city_id = f.city_id
    JOIN real_estate.type t ON t.type_id = f.type_id
    WHERE a.id IN (SELECT id FROM filtered_id)
      AND EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018
      AND t.type = 'город'
),

prep AS (
    -- Расчёт даты закрытия объявления
    SELECT *,
        (first_day_exposition + days_exposition * INTERVAL '1 day') AS close_date  -- Дата снятия с публикации
    FROM base
),

pub AS (
    -- Статистика по месяцам публикации объявлений
    SELECT
        EXTRACT(MONTH FROM first_day_exposition) AS month,  -- Номер месяца
        COUNT(*) AS ads_cnt,  -- Кол‑во опубликованных объявлений
        AVG(last_price / NULLIF(total_area, 0)) AS avg_price_per_sqm,  -- Ср. цена за кв. м
        AVG(total_area) AS avg_area  -- Ср. площадь объявлений
    FROM prep
    GROUP BY EXTRACT(MONTH FROM first_day_exposition)
),

close AS (
    -- Статистика по месяцам закрытия объявлений (только завершённые сделки)
    SELECT
        EXTRACT(MONTH FROM close_date) AS month,  -- Месяц закрытия
        COUNT(*) AS sold_cnt,  -- Кол‑во закрытых объявлений
        AVG(last_price / NULLIF(total_area, 0)) AS avg_price_per_sqm,  -- Ср. цена за кв. м для закрытых объявлений
        AVG(total_area) AS avg_area  -- Ср. площадь закрытых объявлений
    FROM prep
    WHERE days_exposition IS NOT NULL  -- Учитываем только завершённые сделки (с известной длительностью)
    GROUP BY EXTRACT(MONTH FROM close_date)
)

-- Финальный запрос: объединение статистики по публикации и закрытию объявлений
SELECT
    p.month,  -- Номер месяца (1–12)
    p.ads_cnt AS published_ads,  -- Количество опубликованных объявлений в месяце
    c.sold_cnt AS closed_ads,  -- Количество закрытых (проданных) объявлений в месяце
    p.avg_price_per_sqm AS pub_price,  -- Средняя цена за кв. м у опубликованных объявлений
    c.avg_price_per_sqm AS close_price  -- Средняя цена за кв. м у закрытых объявлений
FROM pub p  -- Таблица с данными по публикации объявлений
LEFT JOIN close c USING (month)  -- Присоединяем данные по закрытию объявлений по месяцу
ORDER BY p.month;  -- Сортируем результаты по месяцам (от 1 до 12)

/*
|month|published_ads|closed_ads|pub_price         |close_price       |
|-----|-------------|----------|------------------|------------------|
|1    |735          |1 225     |106 106,2447305485|104 947,3093510842|
|2    |1 369        |1 048     |103 058,5104126244|103 883,7231594406|
|3    |1 119        |1 071     |102 429,9471818448|106 832,4013744821|
|4    |1 021        |1 031     |102 632,4143064015|102 444,2380207702|
|5    |891          |729       |102 465,1220461998|99 724,0659079218 |
|6    |1 224        |771       |104 802,1513823466|101 863,6873467392|
|7    |1 149        |1 108     |104 488,9585543135|102 290,7235570143|
|8    |1 166        |1 137     |107 034,700534513 |100 036,5131908943|
|9    |1 341        |1 238     |107 563,1201390345|104 070,065600862 |
|10   |1 437        |1 360     |104 065,1092601503|104 317,3305613798|
|11   |1 569        |1 301     |105 048,8016501354|103 791,359654983 |
|12   |1 024        |1 175     |104 775,3931875229|105 504,5233469082|
*/
