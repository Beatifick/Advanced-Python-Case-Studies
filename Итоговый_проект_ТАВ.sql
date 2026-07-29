--1. Получите количество проектов, подписанных в 2023 году.
--В результат вывести одно значение количества.

SELECT count(*)
FROM stroy.project
WHERE sign_date >= DATE '2023-01-01'
  AND sign_date < DATE '2024-01-01';

--2. Получите общий возраст сотрудников, нанятых в 2022 году.
--Результат вывести одним значением в виде "... years ... months ... days"
--Использование более 2х функций для работы с типом данных дата и время будет являться ошибкой.

SELECT justify_interval(
           sum(age(current_date, p.birthdate))
       )
FROM stroy.employee e
JOIN stroy.person p
    ON p.person_id = e.person_id
WHERE e.hire_date >= DATE '2022-01-01'
  AND e.hire_date < DATE '2023-01-01';

--3. Получите сотрудников, у которого фамилия начинается на М, всего в фамилии 8 букв и который работает дольше других.
--Если таких сотрудников несколько, выведите одного случайного.
--В результат выведите два столбца, в первом должны быть имя и фамилия через пробел, во втором дата найма.

SELECT
    p.first_name || ' ' || p.last_name AS employee_name,
    e.hire_date
FROM stroy.employee e
JOIN stroy.person p
    ON p.person_id = e.person_id
WHERE p.last_name LIKE 'М_______'
  AND e.hire_date = (
        SELECT min(e2.hire_date)
        FROM stroy.employee e2
        JOIN stroy.person p2
            ON p2.person_id = e2.person_id
        WHERE p2.last_name LIKE 'М_______'
    )
ORDER BY random()
LIMIT 1;

--4. Получите среднее значение полных лет сотрудников, которые уволены и не задействованы на проектах.
--В результат вывести одно среднее значение. Если получаете null, то в результат нужно вывести 0.

SELECT COALESCE(
           AVG(EXTRACT(YEAR FROM age(current_date, p.birthdate))),
           0
       )
FROM stroy.employee e
JOIN stroy.person p
    ON p.person_id = e.person_id
WHERE e.dismissal_date IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM stroy.project pr
        WHERE pr.project_manager_id = e.employee_id
           OR e.employee_id = ANY(pr.employees_id)
    );

--5.Чему равна сумма полученных платежей от контрагентов из Жуковский, Россия.
--В результат вывести одно значение суммы.

SELECT sum(pp.amount)
FROM stroy.project_payment pp
JOIN stroy.project pr
    ON pr.project_id = pp.project_id
JOIN stroy.customer c
    ON c.customer_id = pr.customer_id
JOIN stroy.address a
    ON a.address_id = c.address_id
JOIN stroy.city ci
    ON ci.city_id = a.city_id
JOIN stroy.country co
    ON co.country_id = ci.country_id
WHERE pp.fact_transaction_timestamp IS NOT NULL
  AND ci.city_name = 'Жуковский'
  AND co.country_name = 'Россия';

--6. Пусть руководитель проекта получает премию в 1% от стоимости завершенных проектов.
--Если взять завершенные проекты, какой руководитель проекта получит самый большой бонус?
--В результат нужно вывести идентификатор руководителя проекта, его ФИО и размер бонуса.
--Если таких руководителей несколько, предусмотреть вывод всех.

SELECT
    e.employee_id,
    p.full_fio,
    bonus_amount
FROM (
    SELECT
        project_manager_id,
        sum(project_cost * 0.01) AS bonus_amount,
        rank() OVER (
            ORDER BY sum(project_cost * 0.01) DESC
        ) AS rnk
    FROM stroy.project
    WHERE status = 'Завершен'
    GROUP BY project_manager_id
) b
JOIN stroy.employee e
    ON e.employee_id = b.project_manager_id
JOIN stroy.person p
    ON p.person_id = e.person_id
WHERE rnk = 1;

--7. Получите накопительный итог планируемых авансовых платежей на каждый месяц в отдельности.
--Выведите в результат те даты планируемых платежей, которые идут после преодаления накопительной суммой значения в 30 000 000

WITH payments AS (
    SELECT
        plan_payment_date,
        amount,
        sum(amount) OVER (
            PARTITION BY date_trunc('month', plan_payment_date)
            ORDER BY plan_payment_date, project_payment_id
        ) AS cumulative_amount
    FROM stroy.project_payment
    WHERE payment_type = 'Авансовый'
),
result AS (
    SELECT
        plan_payment_date,
        cumulative_amount,
        lag(cumulative_amount) OVER (
            PARTITION BY date_trunc('month', plan_payment_date)
            ORDER BY plan_payment_date
        ) AS prev_amount
    FROM payments
)
SELECT
    plan_payment_date,
    cumulative_amount
FROM result
WHERE cumulative_amount > 30000000
  AND coalesce(prev_amount,0) <= 30000000
ORDER BY plan_payment_date;

--8. Используя рекурсию посчитайте сумму фактических окладов сотрудников из структурного подразделения с id равным 17 и всех дочерних подразделений.
--В результат вывести одно значение суммы.


-- Что в нашей базе считается фактическим окладом сотрудника?
-- employee_salary_history пустая
-- Учитывается ли ставка при расчёте оклада?
-- sum(salary)= 4 050 000 что преподаватель назвал не верным
-- sum(salary * rate) = 3 540 000

WITH RECURSIVE units AS (
    SELECT unit_id
    FROM stroy.company_structure
    WHERE unit_id = 17

    UNION ALL

    SELECT cs.unit_id
    FROM stroy.company_structure cs
    JOIN units u
        ON u.unit_id = cs.parent_id
)
SELECT sum(ep.salary * ep.rate)
FROM stroy.employee_position ep
JOIN stroy."position" p
    ON p.position_id = ep.position_id
JOIN units u
    ON u.unit_id = p.unit_id;


--9. Задание выполняется одним запросом.
--Сделайте сквозную нумерацию фактических платежей по проектам на каждый год в отдельности в порядке даты платежей.
--Получите платежи, сквозной номер которых кратен 5.
--Выведите скользящее среднее размеров платежей с шагом 2 строки назад и 2 строки вперед от текущей.
--Получите сумму скользящих средних значений.
--Получите сумму стоимости проектов на каждый год.
--Выведите в результат значение года (годов) и сумму проектов, где сумма проектов меньше, чем сумма скользящих средних значений.

-- В результате у меня получились пустые строки, т.к. есть условие ps.sum_project_cost < ms.sum_moving_avg 
-- (сумма проектов меньше, чем сумма скользящих средних значений)
-- надеюсь решил правильно.

WITH numbered AS (
    SELECT
        extract(year FROM fact_transaction_timestamp)::int AS year_payment,
        amount,
        row_number() OVER (
            PARTITION BY extract(year FROM fact_transaction_timestamp)
            ORDER BY fact_transaction_timestamp,
                     project_payment_id
        ) AS rn
    FROM stroy.project_payment
    WHERE fact_transaction_timestamp IS NOT NULL
),
moving AS (
    SELECT
        year_payment,
        avg(amount) OVER (
            PARTITION BY year_payment
            ORDER BY rn
            ROWS BETWEEN 2 PRECEDING
                     AND 2 FOLLOWING
        ) AS moving_avg
    FROM numbered
    WHERE rn % 5 = 0
),
moving_sum AS (
    SELECT
        year_payment,
        sum(moving_avg) AS sum_moving_avg
    FROM moving
    GROUP BY year_payment
),
project_sum AS (
    SELECT
        extract(year FROM sign_date)::int AS year_project,
        sum(project_cost) AS sum_project_cost
    FROM stroy.project
    GROUP BY extract(year FROM sign_date)
)
SELECT
    ps.year_project,
    ps.sum_project_cost
FROM project_sum ps
JOIN moving_sum ms
    ON ms.year_payment = ps.year_project
WHERE ps.sum_project_cost < ms.sum_moving_avg;

--10. Создайте материализованное представление, которое будет хранить отчет следующей структуры:
--идентификатор проекта
--название проекта
--дата последней фактической оплаты по проекту
--размер последней фактической оплаты
--ФИО руководителей проектов
--Названия контрагентов
--В виде строки названия типов работ по каждому контрагенту

CREATE MATERIALIZED VIEW stroy.mv_project_payment_report AS
WITH last_payment AS (
    SELECT
        project_id,
        fact_transaction_timestamp,
        amount,
        row_number() OVER (
            PARTITION BY project_id
            ORDER BY fact_transaction_timestamp DESC,
                     project_payment_id DESC
        ) AS rn
    FROM stroy.project_payment
    WHERE fact_transaction_timestamp IS NOT NULL
),
customer_work AS (
    SELECT
        ctw.customer_id,
        array_to_string(
            array_agg(
                tow.type_of_work_name
                ORDER BY tow.type_of_work_name
            ),
            ', '
        ) AS type_of_work_names
    FROM stroy.customer_type_of_work ctw
    JOIN stroy.type_of_work tow
        ON tow.type_of_work_id = ctw.type_of_work_id
    GROUP BY ctw.customer_id
)
SELECT
    p.project_id,
    p.project_name,
    lp.fact_transaction_timestamp AS last_payment_date,
    lp.amount AS last_payment_amount,
    per.full_fio,
    c.customer_name,
    cw.type_of_work_names
FROM stroy.project p
JOIN last_payment lp
    ON lp.project_id = p.project_id
   AND lp.rn = 1
JOIN stroy.customer c
    ON c.customer_id = p.customer_id
JOIN customer_work cw
    ON cw.customer_id = c.customer_id
JOIN stroy.employee e
    ON e.employee_id = p.project_manager_id
JOIN stroy.person per
    ON per.person_id = e.person_id;


SELECT *
FROM stroy.mv_project_payment_report;