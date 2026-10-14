-- ============================================================
--  SHOP ANALYTICS: SQL ANALYSIS (MySQL 8.0)
--  Database: shop_analytics (simulated e-commerce data, 2023-2024)
--  Tables: customers, products, orders, order_items, reviews
--  Setup: run shop_analytics.sql first, then this file.
-- ============================================================
use shop_analytics;


-- ============================================================
-- PART 1: EXPLORE THE DATA
-- ============================================================

-- 1.1 Row counts per table (check the load worked)
-- Insight: customers 406, products 42, orders 2,137, order_items 3,738, reviews 1,447.
--          (customers drops to 400 after cleaning in Part 2.)
select 'customers' as tbl, count(*) as row_loaded from customers
union all select 'products', count(*) from products
union all select 'orders', count(*) from orders
union all select 'order_items', count(*) from order_items
union all select 'reviews', count(*) from reviews;

-- 1.2 Look at the first rows of the main (fact) table
select * from orders limit 10;

-- 1.3 Orders by status
-- Insight: 1,955 Delivered, 102 Cancelled, 49 Returned, 31 Shipped (in transit).
select status, count(*) as orders
from orders
group by status
order by orders desc;


-- ============================================================
-- PART 2: DATA QUALITY (NULLs, DUPLICATES)
-- ============================================================

-- 2.1 Count empty (NULL) values in every column of orders
-- Insight: ship_date is empty for 102 orders (the cancelled ones) and
--          delivered_date for 133 (102 cancelled + 31 still in transit).
--          The empties are explained by order status, so they are expected.
select count(*) as total_rows,
sum(order_id is null) as empty_order_id,
sum(customer_id is null) as empty_customer_id,
sum(order_date is null) as empty_order_date,
sum(ship_date is null) as empty_ship_date,
sum(promised_date is null) as empty_promised_date,
sum(delivered_date is null) as empty_delivered_date,
sum(status is null) as empty_status,
sum(payment_method is null) as empty_payment_method
from orders;

-- 2.2 Average delivery days
-- Insight: 6.4 days on average. AVG ignores NULLs, so the WHERE line
--          does not change the result here.
select round(avg(datediff(delivered_date, order_date)), 1) as avg_delivery_days
from orders
where delivered_date is not null;

-- 2.3 Rows in the table vs rows AVG actually used
-- Insight: 2,137 vs 2,004. The difference (133) is the orders with no delivery date.
select count(*) as rows_in_table,
count(datediff(delivered_date, order_date)) as rows_avg_used
from orders;

-- 2.4 CASE WHEN: label every order by delivery outcome
-- The NULL check comes first so undelivered orders are NOT mislabelled "Late".
-- Insight: 133 not delivered, 914 on time, 1,090 late.
--          Without the NULL check, "Late" would wrongly show 1,223.
select case
  when delivered_date is null then 'Not_Delivered'
  when delivered_date <= promised_date then 'On_time'
  else 'Late' end as delivery,
count(*) as orders
from orders
group by delivery;

-- 2.5 Duplicate orders: same order_id, or same customer at the same moment
-- Insight: no duplicate order_ids. The second check returns rows, but every one
--          is at exactly 12:00:00 (see 2.6), so they are not true duplicates.
select order_id, count(*) as times
from orders
group by order_id
having count(*) > 1;

select customer_id, order_date, count(*) as times
from orders
group by customer_id, order_date
having count(*) > 1;

-- 2.6 Why? Check orders stamped at exactly 12:00:00
-- Insight: 876 orders (41%) sit at 12:00:00 and 875 of them fall on the customer's
--          signup date. The simulated data moved early orders to the signup date.
--          Known data issue: analyse at monthly level, not daily.
select count(*) as noon_orders
from orders
where time(order_date) = '12:00:00';

select count(*) as noon_signup_date
from orders o
join customers c on o.customer_id = c.customer_id
where time(o.order_date) = '12:00:00'
and date(c.signup_date) = date(o.order_date);

-- 2.7 Duplicate customers (same email)
-- Insight: 6 emails appear twice, so 406 rows hold only 400 real customers.
select email, count(*) as times
from customers
group by email
having count(*) > 1;

-- Look at the actual rows before deciding anything (subquery)
-- Insight: every column is identical except customer_id; the copy always has the higher id.
select * from customers
where email in (
  select email from customers
  group by email
  having count(*) > 1
)
order by email;

-- Do the duplicate ids have orders? (LEFT JOIN keeps customers with zero orders)
-- Insight: the 6 originals have 2-6 orders each; the 6 copies (401-406) have none,
--          so deleting them cannot break any sales data.
select c.customer_id, count(o.order_id) as orders
from customers c
left join orders o on c.customer_id = o.customer_id
where c.customer_id in (7, 403, 129, 401, 394, 405, 366, 406, 196, 402, 63, 404)
group by c.customer_id
order by c.customer_id;

-- The scalable way to find extra copies: ROW_NUMBER inside a CTE
-- rn = 1 is the original, rn > 1 are duplicates.
with numbered as (
  select customer_id, email,
  row_number() over (partition by email order by customer_id) as rn
  from customers
)
select customer_id, email, rn
from numbered
where rn > 1;

-- 2.8 Safe delete: backup first, then delete inside a transaction
-- (Run once. Re-running on a fresh load is harmless.)
create table customers_backup as
select * from customers;
select count(*) from customers_backup;      -- expect 406

start transaction;
delete from customers
where customer_id in (403, 401, 405, 406, 402, 404);
select count(*) from customers;             -- expect 400
commit;

-- 2.9 Verify the cleaning worked
-- Insight: no duplicate emails left; 400 rows = 400 unique customers.
select email, count(*) as times
from customers
group by email
having count(*) > 1;

select count(*) as total_rows, count(distinct email) as unique_emails
from customers;

drop table customers_backup;

-- 2.10 Reviews: orders with more than one review
-- Insight: 23 orders have two reviews and the ratings differ, so the customer
--          changed their mind. Decision: keep the latest review, delete nothing.
select order_id, count(*) as reviews
from reviews
group by order_id
having count(*) > 1;

select * from reviews
where order_id in (
  select order_id from reviews group by order_id having count(*) > 1
)
order by order_id, review_date;

-- Keep only the latest review per order
-- Insight: 1,447 reviews become 1,424, one per order. The table itself is untouched.
with ranked as (
  select review_id, order_id, rating, review_date,
  row_number() over (partition by order_id order by review_date desc, review_id desc) as rn
  from reviews
)
select review_id, order_id, rating, review_date
from ranked
where rn = 1;


-- ============================================================
-- PART 3: BUSINESS QUESTIONS
-- ============================================================

-- 3.1 Do late deliveries get lower ratings? (two CTEs + JOIN + CASE WHEN)
-- On time = delivered on or before the promised date (same rule as 2.4).
-- Insight: late orders average 2.6 stars vs 4.0 for on-time orders, a gap of
--          1.4 points. 773 of 1,424 reviewed orders (54%) arrived late.
with latest_reviews as (
  select order_id, rating,
  row_number() over (partition by order_id order by review_date desc, review_id desc) as rn
  from reviews
),
delivery as (
  select order_id,
  case when delivered_date <= promised_date then 'On_time' else 'Late' end as delivery_status
  from orders
  where delivered_date is not null
)
select d.delivery_status,
count(*) as reviews,
round(avg(r.rating), 1) as avg_rating
from delivery d
join latest_reviews r on d.order_id = r.order_id
where r.rn = 1
group by d.delivery_status;

-- 3.2 How much money did the shop make? Build it up step by step
select * from order_items limit 10;

-- raw total (ignores discounts and order status)  -> 8,130,418.00
select sum(quantity * unit_price) as total_revenue
from order_items;

-- after discounts                                  -> 7,736,983.80
select round(sum(quantity * unit_price * (1 - discount_pct / 100)), 2) as total_revenue
from order_items;

-- delivered orders only (JOIN to get the status)   -> 7,131,020.70
select round(sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)), 2) as total_revenue
from orders o join order_items oi on o.order_id = oi.order_id
where status = 'Delivered';

-- by status (GROUP BY)
-- Insight: Delivered 7,131,020.70, Cancelled 319,018.20, Returned 196,820.75,
--          Shipped 90,124.15. Only delivered orders count as revenue
--          (returned orders were probably refunded).
select o.status, round(sum(oi.unit_price * oi.quantity * (1 - discount_pct / 100)), 2) as total_revenue
from orders o join order_items oi on o.order_id = oi.order_id
group by o.status;

-- 3.3 Monthly revenue (CTE) - months above 400,000
-- Insight: only 2024-06 to 2024-11 pass 400K. Use '%Y-%m' (not '%Y-%M') so months
--          sort in calendar order instead of alphabetically.
with monthly as (
  select date_format(o.order_date, '%Y-%m') as month,
  round(sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100))) as total_revenue
  from orders o join order_items oi on o.order_id = oi.order_id
  where o.status = 'Delivered'
  group by month
)
select month, total_revenue
from monthly
where total_revenue > 400000
order by month;

-- 3.4 Month-over-month growth with LAG
-- Insight: revenue grew from 16,653.50 (Jan 2023) to 885,123.65 (Nov 2024);
--          November is the peak in both years. The -55% in Dec 2024 is a data
--          artifact (late-December orders were still in transit), not a real decline.
with monthly as (
  select date_format(o.order_date, '%Y-%m') as month,
  round(sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)), 2) as total_revenue
  from orders o join order_items oi on o.order_id = oi.order_id
  where o.status = 'Delivered'
  group by month
),
with_prev as (
  select month, total_revenue,
  lag(total_revenue) over (order by month) as previous_revenue
  from monthly
)
select month, total_revenue, previous_revenue,
round((total_revenue - previous_revenue) / previous_revenue * 100, 1) as growth_pct
from with_prev
order by month;

-- 3.5 Running total of revenue (SUM as a window function)
-- Insight: the running total ends at 7,131,020.70, matching the delivered total in 3.2.
with monthly as (
  select date_format(o.order_date, '%Y-%m') as month,
  round(sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)), 2) as total_revenue
  from orders o join order_items oi on o.order_id = oi.order_id
  where o.status = 'Delivered'
  group by month
)
select month, total_revenue,
sum(total_revenue) over (order by month) as running_total
from monthly
order by month;

-- 3.6 Top 10 products by revenue (RANK)
-- Insight: Air Fryer is #1 (625,095.80), then Smartwatch (572,135.55) and
--          Mechanical Keyboard (410,432.70). Expensive items lead on revenue.
with product_revenue as (
  select p.product_name,
  round(sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)), 2) as total_revenue
  from order_items oi
  join products p on oi.product_id = p.product_id
  join orders o on oi.order_id = o.order_id
  where o.status = 'Delivered'
  group by p.product_id, p.product_name
)
select product_name, total_revenue,
rank() over (order by total_revenue desc) as revenue_rank
from product_revenue
order by revenue_rank
limit 10;

-- 3.7 Top 3 products in each category (RANK + PARTITION BY)
-- Insight: category leaders are Air Fryer (Home & Kitchen), Smartwatch (Electronics),
--          Running Shoes (Fashion), Fitness Tracker (Sports & Fitness) and
--          Statistics Textbook (Books & Stationery).
with product_revenue as (
  select coalesce(p.category, 'uncategorised') as category,
  p.product_name,
  round(sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100)), 2) as total_revenue
  from order_items oi
  join products p on p.product_id = oi.product_id
  join orders o on o.order_id = oi.order_id
  where o.status = 'Delivered'
  group by p.product_id, p.product_name, p.category
),
ranked as (
  select category, product_name, total_revenue,
  rank() over (partition by category order by total_revenue desc) as rank_by_category
  from product_revenue
)
select category, product_name, total_revenue, rank_by_category
from ranked
where rank_by_category <= 3
order by category, rank_by_category;
