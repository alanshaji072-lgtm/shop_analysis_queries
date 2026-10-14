# E-commerce SQL Analysis (MySQL)

SQL analysis of a simulated online store (Jan 2023 to Dec 2024): data cleaning, delivery performance, revenue trends and top products.

> **Data note:** the dataset is synthetic and was generated for practice. It is not from a real company.

## Tools
MySQL 8.0, MySQL Workbench

## Database
Five tables: `customers`, `products`, `orders`, `order_items`, `reviews`.
Set it up by running `shop_analytics.sql`, then run `shop_analysis_queries.sql`.

## Key findings
- **Late deliveries hurt ratings:** late orders average **2.6 stars** against **4.0** for on-time orders, and 54% of reviewed orders (773 of 1,424) arrived late.
- **Revenue grew strongly** from about 16.7K (Jan 2023) to 885K (Nov 2024), with November the peak month in both years. Total delivered revenue: **7.13M**.
- **Top product:** the Air Fryer, with 625K in revenue. Each category's top 3 is in query 3.7.

## Data quality work
| Issue found | How I handled it |
|---|---|
| 133 orders with no delivery date (102 cancelled, 31 in transit) | Labelled "Not_Delivered" so they are not counted as late (2.4) |
| 6 duplicate customers (406 rows, 400 real people) | Checked they had no orders, backed up the table, then deleted them inside a transaction (2.7 to 2.9) |
| 23 orders with two reviews and different ratings | Kept the latest review per order with `ROW_NUMBER`, without deleting anything (2.10) |
| 41% of orders timestamped exactly 12:00:00 | Traced to the signup-date shift in the simulated data, so analysis is done at monthly level (2.6) |
| December 2024 revenue drops 55% | Late-December orders were still in transit, so this is an incomplete month, not a real decline (3.4) |
| Orders delivered exactly on the promised time | Counted as on time (`delivered_date <= promised_date`) in both 2.4 and 3.1 |

Returned orders are excluded from revenue (a choice: they were probably refunded).

## SQL skills demonstrated
| Skill | Used in |
|---|---|
| NULL handling, `COALESCE` | 2.1 to 2.4, 3.7 |
| `CASE WHEN` | 2.4, 3.1 |
| `GROUP BY` / `HAVING` | 1.3, 2.5, 2.7, 2.10 |
| `JOIN`, `LEFT JOIN`, subqueries | 2.6, 2.7, 3.1 to 3.7 |
| Transactions (safe `DELETE` with backup) | 2.8 |
| CTEs (including several in one query) | 2.7, 2.10, 3.1, 3.3 to 3.7 |
| Window functions: `ROW_NUMBER`, `LAG`, `SUM() OVER`, `RANK` with `PARTITION BY` | 2.7, 2.10, 3.4 to 3.7 |
| Date functions: `DATE_FORMAT`, `DATEDIFF` | 2.2, 3.3 to 3.5 |

## Files
- `shop_analytics.sql` creates the database and loads the data
- `shop_analysis_queries.sql` holds all queries, each with a one-line insight
