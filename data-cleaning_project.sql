-- Очистка даних
-- 1. Видалення дублікатів
-- 2. Стандартизація даних (видалення пробілів, єдині назви та ін)
-- 3. Обробка пустих значень і Null
-- 4. Видалення непотрібних записів і полів

-- 0. Підготовка до роботи з даними
-- виводимо дані
SELECT 
    *
FROM
    layoffs;
    
-- створюємо пусту копію таблиці
CREATE TABLE layoffs_staging LIKE layoffs;
SELECT 
    *
FROM
    layoffs_staging;
    
-- заповнюємо пусту копію значеннями
INSERT layoffs_staging SELECT * FROM layoffs;
SELECT 
    *
FROM
    layoffs_staging;
    
-- 1. Видалення дублікатів
-- 1.1. пошук дублікатів
-- визначаємо номери однакових записів через віконну функцію
SELECT *,
row_number() 
over (partition by company, location, industry, total_laid_off, `date`, stage, country, funds_raised_millions) as row_num
FROM layoffs_staging;

-- робимо табличний вираз із запиту
WITH duplicate_cte AS (
SELECT *,
row_number() 
over (partition by company, location, industry, total_laid_off, `date`, stage, country, funds_raised_millions) as row_num
FROM layoffs_staging
)

-- досліджуємо к-сть записів через табличний вираз. якщо номер запису більше 1 - це дублікат
SELECT 
    *
FROM
    duplicate_cte
WHERE
    row_num > 1;
    
-- додатково фільтруємо окрему компанію. бачимо, що записи справді дублюються
SELECT 
    *
FROM
    layoffs_staging
WHERE
    company = 'Casper';

-- 1.2. видалення дублікатів
-- видаляємо визначені дублікати з номером запису 2 за допомогою табличного виразу.
WITH duplicate_cte AS (
SELECT *,
row_number() 
over (partition by company, location, industry, total_laid_off, `date`, stage, country, funds_raised_millions) as row_num
FROM layoffs_staging
)
DELETE FROM duplicate_cte 
WHERE
    row_num > 1;
-- НЕ ПРАЦЮЄ!!! помилка. табличний вираз не є оновлюваним
-- створюємо таблицю з додатковим полем для номера ряду через копіювання і заповнюємо її значеннями
CREATE TABLE `world_layoffs`.`layoffs_staging2` (
`company` text,
`location`text,
`industry`text,
`total_laid_off` INT,
`percentage_laid_off` text,
`date` text,
`stage`text,
`country` text,
`funds_raised_millions` int,
row_num INT
);
 
INSERT INTO layoffs_staging2
SELECT *,
row_number() 
over (partition by company, location, industry, total_laid_off, `date`, stage, country, funds_raised_millions) as row_num
FROM layoffs_staging;

-- перевірка
SELECT 
    *
FROM
    layoffs_staging2
WHERE row_num > 1;
    
-- тепер можна видалити дублікати з номером більшим за 1
DELETE FROM layoffs_staging2 
WHERE
    row_num > 1;
    
-- перевірка знову
SELECT 
    *
FROM
    layoffs_staging2
WHERE row_num > 1;

SELECT 
    *
FROM
    layoffs_staging2;

-- 2. Стандартизація даних (видалення пробілів, єдині назви та ін)
-- видалення пробілів у стовпці
-- дивимось (досліджуємо), порівнюємо
SELECT 
    company, TRIM(company)
FROM
    layoffs_staging2;
-- замінюємо значення стовпця
UPDATE layoffs_staging2 
SET 
    company = TRIM(company);

-- досліджуємо наступне поле
SELECT DISTINCT industry
FROM layoffs_staging2
ORDER BY 1;

-- бачимо повторювані видозмінені значення, замінюємо на єдине 
SELECT 
DISTINCT industry
FROM
    layoffs_staging2
WHERE
    industry LIKE 'crypt%';

UPDATE layoffs_staging2 
SET 
    industry = 'Crypto'
WHERE industry LIKE 'Crypt%';

-- досліджуємо наступні поля і робимо заміни
SELECT DISTINCT location
FROM layoffs_staging2
ORDER BY 1;

UPDATE layoffs_staging2 
SET 
    location = 'Dusseldorf'
WHERE location LIKE '%sseldorf';

SELECT DISTINCT country
FROM layoffs_staging2
ORDER BY 1;

-- бачимо крапку у кінці країни, видаляємо її
SELECT DISTINCT country, trim(trailing '.' from country)
FROM layoffs_staging2
ORDER BY 1;

UPDATE layoffs_staging2 
SET 
    country = trim(trailing '.' from country);
    
-- змінюємо тип даних на дату для дат
SELECT 
    `date`, STR_TO_DATE(`date`, '%m/%d/%Y')
FROM
    layoffs_staging2;

UPDATE layoffs_staging2 
SET 
    `date` = STR_TO_DATE(`date`, '%m/%d/%Y');

ALTER TABLE layoffs_staging2 
MODIFY COLUMN `date` DATE;

-- перевірка
SELECT 
    *
FROM
    layoffs_staging2;
    
-- 3.  Обробка пустих значень і Null

-- дослідимо поле industry на наявність пустих значень і/або null
SELECT 
    *
FROM
    layoffs_staging2
WHERE industry = '' OR industry IS NULL
;
-- деякі з цих компаній можуть мати заповнені поля industry в інших записах, тому відфільтруємо їх
SELECT 
    *
FROM
    layoffs_staging2
WHERE company IN (
					SELECT 
						company
					FROM
						layoffs_staging2
					WHERE industry = '' OR industry IS NULL)
;
-- заповнимо пусті поля industry знайденими значеннями за умови, що такі непусті значення присутні в інших записах
UPDATE layoffs_staging2
SET industry = (industry IS NOT NULL)
where industry = '' OR industry IS NULL;
-- УПС! усі пусті поля тепер містять 1-ці. більше так робити не буду. але принаймні я замінив відсутні і пусті значення на єдине - одиниці
-- спробуємо інший підхід, де дані будемо брати з аналогічної таблиці, яка автоматично створиться шляхом внутрішнього обєднання
-- подивимось спочатку на резульат обєднання
SELECT *
FROM layoffs_staging2 t1
JOIN layoffs_staging2 t2 
	ON t1.company = t2.company 
WHERE
    t1.industry = 1
        AND t2.industry IS NOT NULL;        
-- підходить, лише потрібно врахувати наявність 1 замість пустих значень. робимо оновлення з замінами
UPDATE layoffs_staging2 t1
        JOIN
    layoffs_staging2 t2 ON t1.company = t2.company 
SET 
    t1.industry = t2.industry
WHERE
    t1.industry = 1
        AND (t2.industry IS NOT NULL AND t2.industry <> 1);
        
-- перевірка
SELECT 
    *
FROM
    layoffs_staging2
where company = 'airbnb';
-- готово

-- дослідимо поля total_laid_off і percentage_laid_off на присутність пустих значень і/або null одночасно
-- допустимо, що такі записи не надаватимуть нам корисної інформації, тому підлягають видаленню. єдине, що могло б запобігти їх видаленню, це припущення, 
-- що нас можуть цікавити інші показники таблиці, а не показники звільнень. тоді ми мали б це врахувати. 
SELECT 
    company, total_laid_off, percentage_laid_off
FROM
    layoffs_staging2
WHERE
    (total_laid_off = ''
        OR total_laid_off IS NULL)
        AND (percentage_laid_off = ''
        OR percentage_laid_off IS NULL);

-- бачимо, що таких компаній досить багато i усі вони null. видаляємо їх
DELETE FROM layoffs_staging2 
WHERE
    total_laid_off IS NULL
    AND percentage_laid_off IS NULL;
    
-- 4. Видалення непотрібних записів і полів
-- позбавимось від тепер непотрібного нам поля row_num

ALTER TABLE layoffs_staging2
DROP COLUMN row_num;

-- остання перевірка
SELECT 
    *
FROM
    layoffs_staging2;    
-- ГОТОВО! 

-- ПС
# надалі можуть бути внесені інші необхідні зміни. це можна буде зробити або за допомогою цієї СУБД, або інших інструментів підготовки даних,
# в залежності від того, куди будуть імпортовані ці дані і яка мети використання цих даних. більше того, внесення змін могло б бути недоцільним саме у цьому проекті, 
# оскільки за допомогою інших інструментів це можна було б зробити значно швидше і простіше.




