-- ============================================================
-- OLIST BI AGENT — GOLDEN QUERIES TEST SUITE
-- 10 business questions with expected SQL for agent validation
-- ============================================================


-- ── Q1: Total Revenue by Product Category ────────────────────
-- Business Question:
--   Which product categories generate the most revenue?
-- Business Value:
--   Identifies high-value categories for inventory and marketing focus.
-- Expected: health_beauty, watches_gifts, bed_bath_table in top 5.

SELECT
    pc.category_name_english        AS category,
    ROUND(SUM(foi.price)::numeric, 2) AS total_revenue_brl,
    COUNT(DISTINCT foi.order_id)    AS total_orders
FROM fact_order_items foi
JOIN dim_products p        ON foi.product_id = p.product_id
JOIN dim_product_categories pc ON p.category_name = pc.category_name_portuguese
GROUP BY pc.category_name_english
ORDER BY total_revenue_brl DESC
LIMIT 10;


-- ── Q2: Top 10 Sellers by Revenue ────────────────────────────
-- Business Question:
--   Who are the top-performing sellers on the platform?
-- Business Value:
--   Identifies key sellers for partnership programs or performance rewards.
-- Expected: Top sellers concentrated in SP state.

SELECT
    s.seller_id,
    s.city                          AS seller_city,
    s.state                         AS seller_state,
    ROUND(SUM(foi.price)::numeric, 2) AS total_revenue_brl,
    COUNT(DISTINCT foi.order_id)    AS total_orders
FROM fact_order_items foi
JOIN dim_sellers s ON foi.seller_id = s.seller_id
GROUP BY s.seller_id, s.city, s.state
ORDER BY total_revenue_brl DESC
LIMIT 10;


-- ── Q3: Average Delivery Time by State ───────────────────────
-- Business Question:
--   How long does delivery take on average across Brazilian states?
-- Business Value:
--   Highlights logistics bottlenecks in remote states vs. major hubs.
-- Expected: SP/RJ < 10 days, northern states (AM, RR) > 20 days.

SELECT
    c.state                         AS customer_state,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (o.order_delivered_ts - o.order_purchase_ts))
        / 86400
    )::numeric, 1)                  AS avg_delivery_days,
    COUNT(*)                        AS total_delivered_orders
FROM dim_orders o
JOIN dim_customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_ts IS NOT NULL
GROUP BY c.state
ORDER BY avg_delivery_days ASC;


-- ── Q4: Monthly Order Volume and Revenue Trend ───────────────
-- Business Question:
--   How have order volumes and revenue trended month by month?
-- Business Value:
--   Reveals seasonality, growth periods, and potential anomalies.
-- Expected: Peak in Nov 2017 (Black Friday), steady growth through 2018.

SELECT
    TO_CHAR(o.order_purchase_ts, 'YYYY-MM') AS month,
    COUNT(DISTINCT o.order_id)              AS total_orders,
    ROUND(SUM(foi.price)::numeric, 2)       AS total_revenue_brl
FROM dim_orders o
JOIN fact_order_items foi ON o.order_id = foi.order_id
WHERE o.order_purchase_ts IS NOT NULL
GROUP BY TO_CHAR(o.order_purchase_ts, 'YYYY-MM')
ORDER BY month;


-- ── Q5: Review Score Distribution ────────────────────────────
-- Business Question:
--   What is the overall customer satisfaction distribution?
-- Business Value:
--   Measures platform health; high % of 1-star reviews signals problems.
-- Expected: ~57% 5-star, ~11% 1-star reviews.

SELECT
    review_score,
    COUNT(*)                                    AS total_reviews,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS percentage
FROM dim_reviews
GROUP BY review_score
ORDER BY review_score DESC;


-- ── Q6: Payment Type Breakdown ───────────────────────────────
-- Business Question:
--   Which payment methods do customers prefer?
-- Business Value:
--   Informs payment gateway investment and installment financing strategy.
-- Expected: Credit card ~74%, boleto ~19%.

SELECT
    payment_type,
    COUNT(*)                                    AS total_transactions,
    ROUND(SUM(payment_value)::numeric, 2)       AS total_value_brl,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct_of_transactions
FROM dim_payments
GROUP BY payment_type
ORDER BY total_transactions DESC;


-- ── Q7: Freight Cost as % of Order Value by State ────────────
-- Business Question:
--   In which states does freight cost represent the highest
--   proportion of the order value?
-- Business Value:
--   Identifies where free shipping offers would be most costly
--   and where logistics partnerships are needed.
-- Expected: Northern/remote states show highest freight ratios.

SELECT
    c.state                         AS customer_state,
    ROUND(AVG(foi.freight_value)::numeric, 2)   AS avg_freight_brl,
    ROUND(AVG(foi.price)::numeric, 2)           AS avg_item_price_brl,
    ROUND(
        AVG(foi.freight_value) * 100.0
        / NULLIF(AVG(foi.price), 0)
    ::numeric, 1)                   AS freight_pct_of_price
FROM fact_order_items foi
JOIN dim_orders o    ON foi.order_id = o.order_id
JOIN dim_customers c ON o.customer_id = c.customer_id
GROUP BY c.state
ORDER BY freight_pct_of_price DESC;


-- ── Q8: Order Status Summary ──────────────────────────────────
-- Business Question:
--   What is the current breakdown of order statuses?
-- Business Value:
--   Monitors operational health — high cancellation or processing
--   rates indicate fulfilment problems.
-- Expected: ~97% delivered, <1% canceled.

SELECT
    order_status,
    COUNT(*)                                    AS total_orders,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentage
FROM dim_orders
GROUP BY order_status
ORDER BY total_orders DESC;


-- ── Q9: Late Delivery Rate by Seller State ────────────────────
-- Business Question:
--   Which seller states have the highest rate of late deliveries?
-- Business Value:
--   Pinpoints regional fulfilment problems and seller SLA violations.
-- Expected: States with fewer sellers show higher late rates.

SELECT
    s.state                         AS seller_state,
    COUNT(*)                        AS total_delivered,
    SUM(CASE
        WHEN o.order_delivered_ts > o.order_estimated_ts THEN 1
        ELSE 0
    END)                            AS late_deliveries,
    ROUND(
        SUM(CASE WHEN o.order_delivered_ts > o.order_estimated_ts
                 THEN 1 ELSE 0 END)
        * 100.0 / NULLIF(COUNT(*), 0)
    ::numeric, 1)                   AS late_delivery_pct
FROM dim_orders o
JOIN fact_order_items foi ON o.order_id = foi.order_id
JOIN dim_sellers s        ON foi.seller_id = s.seller_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_ts IS NOT NULL
  AND o.order_estimated_ts IS NOT NULL
GROUP BY s.state
HAVING COUNT(*) > 50
ORDER BY late_delivery_pct DESC;


-- ── Q10: Customer Repeat Purchase Rate ───────────────────────
-- Business Question:
--   What percentage of customers placed more than one order?
-- Business Value:
--   Core retention metric — low repeat rate signals acquisition
--   dependency and weak loyalty programs.
-- Expected: Olist has low repeat rate (~3%) due to marketplace model.

SELECT
    total_orders_placed,
    COUNT(*)                                    AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct_of_customers
FROM (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders_placed
    FROM dim_customers c
    JOIN dim_orders o ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
) order_counts
GROUP BY total_orders_placed
ORDER BY total_orders_placed;