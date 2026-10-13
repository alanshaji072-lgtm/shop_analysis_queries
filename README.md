-- ============================================================
--  SHOP ANALYTICS: SQL ANALYSIS (MySQL 8.0)
--  Database: shop_analytics (simulated e-commerce data, 2023-2024)
--  Tables: customers, products, orders, order_items, reviews
-- ============================================================
USE shop_analytics;


-- ============================================================
-- PART 1: EXPLORE THE DATA
-- ============================================================

-- 1.1 Row counts per table (check the load worked)
-- Insight: customers 406, products 42, orders 2,137, order_items 3,738, reviews 1,447.
SELECT 'customers' AS tbl, COUNT(*) AS n FROM customers
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'reviews', COUNT(*) FROM reviews;

-- 1.2 Orders by status
-- Insight: 1,955 Delivered, 102 Cancelled, 49 Returned, 31 Shipped (in transit).
SELECT status, COUNT(*) AS orders
FROM orders
GROUP BY status
ORDER BY orders DESC;


-- ============================================================
-- PART 2: DATA QUALITY (NULLs, DUPLICATES)
-- ============================================================

-- 2.1 Count empty (NULL) values in every column of orders
-- Insight: ship_date is empty for 102 orders (the cancelled ones) and
--          delivered_date for 133 (102 cancelled + 31 still in transit).
--          The empties are explained by order status, so they are expected.
SELECT
    COUNT(*)                    AS total_rows,
    SUM(order_id IS NULL)       AS empty_order_id,
    SUM(customer_id IS NULL)    AS empty_customer_id,
    SUM(order_date IS NULL)     AS empty_order_date,
    SUM(ship_date IS NULL)      AS empty_ship_date,
    SUM(promised_date IS NULL)  AS empty_promised_date,
    SUM(delivered_date IS NULL) AS empty_delivered_date,
    SUM(status IS NULL)         AS empty_status,
    SUM(payment_method IS NULL) AS empty_payment_method
FROM orders;

-- 2.2 CASE WHEN: label every order by delivery outcome
-- The NULL check comes first so undelivered orders are NOT mislabelled "Late".
-- Insight: 133 not delivered, 914 on time, 1,090 late.
--          Without the NULL check, "Late" would wrongly show 1,223.
SELECT CASE
           WHEN delivered_date IS NULL THEN 'Not delivered'
           WHEN delivered_date <= promised_date THEN 'On time'
           ELSE 'Late'
       END AS delivery,
       COUNT(*) AS orders
FROM orders
GROUP BY delivery;

-- 2.3 Find duplicate customers by email
-- Insight: 6 emails appear twice, so 406 rows hold only 400 real customers.
SELECT email, COUNT(*) AS times
FROM customers
GROUP BY email
HAVING COUNT(*) > 1;

-- 2.4 Find the extra copies with ROW_NUMBER (CTE + window function)
-- rn = 1 is the original, rn > 1 are duplicates.
-- Insight: the duplicates are customer_ids 401-406 and none of them has orders.
WITH numbered AS (
    SELECT customer_id, email,
           ROW_NUMBER() OVER (PARTITION BY email ORDER BY customer_id) AS rn
    FROM customers
)
SELECT customer_id, email, rn
FROM numbered
WHERE rn > 1;

-- 2.5 Safe delete of the duplicates (backup, then transaction)
-- Already run once. Left commented so re-running the file does not repeat it.
-- CREATE TABLE customers_backup AS SELECT * FROM customers;
-- START TRANSACTION;
-- DELETE FROM customers WHERE customer_id IN (401, 402, 403, 404, 405, 406);
-- SELECT COUNT(*) FROM customers;   -- expect 400
-- COMMIT;

-- 2.6 Orders with more than one review
-- Insight: 23 orders have two reviews, and the ratings differ, so the
--          customer changed their mind. Decision: keep the latest review.
SELECT order_id, COUNT(*) AS reviews
FROM reviews
GROUP BY order_id
HAVING COUNT(*) > 1;

-- 2.7 Keep only the latest review per order
-- Insight: 1,447 reviews become 1,424, one per order. The table itself is untouched.
WITH ranked AS (
    SELECT review_id, order_id, rating, review_date,
           ROW_NUMBER() OVER (
               PARTITION BY order_id
               ORDER BY review_date DESC, review_id DESC
           ) AS rn
    FROM reviews
)
SELECT review_id, order_id, rating, review_date
FROM ranked
WHERE rn = 1;


-- ============================================================
-- PART 3: BUSINESS QUESTIONS
-- ============================================================

-- 3.1 Do late deliveries get lower ratings? (two CTEs + JOIN + CASE WHEN)
-- Insight: late orders average 2.6 stars vs 4.0 for on-time orders,
--          a gap of 1.4 points. 782 of 1,424 reviewed orders (55%) were late.
WITH latest_reviews AS (
    SELECT order_id, rating,
           ROW_NUMBER() OVER (
               PARTITION BY order_id
               ORDER BY review_date DESC, review_id DESC
           ) AS rn
    FROM reviews
),
delivery AS (
    SELECT order_id,
           CASE WHEN delivered_date <= promised_date THEN 'On time' ELSE 'Late' END AS delivery_status
    FROM orders
    WHERE delivered_date IS NOT NULL
)
SELECT d.delivery_status,
       COUNT(*) AS reviews,
       ROUND(AVG(r.rating), 2) AS avg_rating
FROM delivery d
JOIN latest_reviews r ON d.order_id = r.order_id
WHERE r.rn = 1
GROUP BY d.delivery_status;

-- 3.2 Monthly revenue (delivered orders only, after discounts)
-- Insight: revenue grew from 16,653.50 (Jan 2023) to 885,123.65 (Nov 2024).
--          November is the peak month in both years.
--          Total delivered revenue: 7,131,020.70.
SELECT DATE_FORMAT(o.order_date, '%Y-%m') AS month,
       ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)), 2) AS revenue
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.status = 'Delivered'
GROUP BY month
ORDER BY month;

-- 3.3 Month-over-month growth with LAG
-- Insight: the -55.0% drop in Dec 2024 is a data artifact (late-December orders
--          were still in transit and excluded). It is not a real decline.
WITH monthly AS (
    SELECT DATE_FORMAT(o.order_date, '%Y-%m') AS month,
           ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)), 2) AS revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status = 'Delivered'
    GROUP BY month
),
with_prev AS (
    SELECT month, revenue,
           LAG(revenue) OVER (ORDER BY month) AS prev_revenue
    FROM monthly
)
SELECT month, revenue, prev_revenue,
       ROUND((revenue - prev_revenue) / prev_revenue * 100, 1) AS growth_pct
FROM with_prev
ORDER BY month;

-- 3.4 Running total of revenue (SUM as a window function)
-- Insight: the running total ends at 7,131,020.70, matching the total in 3.2.
WITH monthly AS (
    SELECT DATE_FORMAT(o.order_date, '%Y-%m') AS month,
           ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)), 2) AS revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status = 'Delivered'
    GROUP BY month
)
SELECT month, revenue,
       ROUND(SUM(revenue) OVER (ORDER BY month), 2) AS running_total
FROM monthly
ORDER BY month;

-- 3.5 Top 3 products in each category (RANK + PARTITION BY)
-- Insight: Air Fryer is the top product overall (625,095.80). Top by category:
--          Home & Kitchen: Air Fryer; Electronics: Smartwatch;
--          Fashion: Running Shoes; Sports & Fitness: Fitness Tracker;
--          Books & Stationery: Statistics Textbook.
WITH product_revenue AS (
    SELECT COALESCE(p.category, 'Uncategorised') AS category,
           p.product_name,
           ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)), 2) AS revenue
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
    JOIN orders o   ON oi.order_id = o.order_id
    WHERE o.status = 'Delivered'
    GROUP BY p.product_id, p.category, p.product_name
),
ranked AS (
    SELECT category, product_name, revenue,
           RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS rank_in_category
    FROM product_revenue
)
SELECT category, product_name, revenue, rank_in_category
FROM ranked
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;
