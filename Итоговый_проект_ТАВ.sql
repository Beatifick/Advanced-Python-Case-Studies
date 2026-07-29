-- 1. Get the number of projects signed in 2023.
-- Return a single value representing the total count.

SELECT count(*)
FROM stroy.project
WHERE sign_date >= DATE '2023-01-01'
  AND sign_date < DATE '2024-01-01';

-- 2. Calculate the total age of employees hired in 2022.
-- Return a single value in the format "... years ... months ... days".
-- Using more than two date/time functions will be considered an error.

SELECT justify_interval(
           sum(age(current_date, p.birthdate))
       )
FROM stroy.employee e
JOIN stroy.person p
    ON p.person_id = e.person_id
WHERE e.hire_date >= DATE '2022-01-01'
  AND e.hire_date < DATE '2023-01-01';

-- 3. Find an employee whose last name starts with "M", contains exactly 8 letters,
-- and who has been working at the company the longest.
-- If multiple employees match the criteria, return one random employee.
-- Return two columns: full name and hire date.

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

-- 4. Calculate the average age in full years of employees who have been dismissed
-- and are not assigned to any projects.
-- Return a single average value. If the result is NULL, return 0.

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

-- 5. Calculate the total amount of received payments from customers located
-- in Zhukovsky, Russia.
-- Return a single value representing the total payment amount.

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

-- 6. Project managers receive a bonus equal to 1% of the cost of completed projects.
-- Find the project manager who would receive the highest bonus.
-- Return the manager's ID, full name, and bonus amount.
-- If multiple managers have the same highest bonus, return all of them.

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

-- 7. Calculate the cumulative total of planned advance payments for each month separately.
-- Return the payment dates where the cumulative amount exceeds 30,000,000.

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

-- 8. Using recursion, calculate the total actual salaries of employees
-- from the organizational unit with ID = 17 and all its child units.
-- Return a single value representing the total salary amount.

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


-- 9. Complete the task using a single query.
-- Create sequential numbering of actual project payments separately for each year
-- ordered by payment date.
-- Select payments where the sequential number is divisible by 5.
-- Calculate the moving average of payment amounts using a window of
-- 2 rows before and 2 rows after the current row.
-- Calculate the sum of moving averages.
-- Calculate the total project cost for each year.
-- Return years where the total project cost is lower than the sum of moving averages.

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

-- 10. Create a materialized view storing a report with the following structure:
-- - Project ID
-- - Project name
-- - Date of the latest actual payment for the project
-- - Amount of the latest actual payment
-- - Full name of project managers
-- - Customer names
-- - Work type names for each customer as a single string

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
