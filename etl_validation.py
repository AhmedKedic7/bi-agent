import psycopg2
import os
from dotenv import load_dotenv
 
load_dotenv()
 
conn = psycopg2.connect(
    host=os.getenv("POSTGRES_HOST"),
    port=os.getenv("POSTGRES_PORT", 5432),
    dbname=os.getenv("POSTGRES_DATABASE", "postgres"),
    user=os.getenv("POSTGRES_USER", "postgres"),
    password=os.getenv("POSTGRES_PASSWORD"),
    sslmode="require"
)
cur = conn.cursor()
 
PASS = "PASS"
FAIL = "FAIL"
results = []
 
def check(label, passed, detail=""):
    status = PASS if passed else FAIL
    results.append((status, label, detail))
    print(f"{status}  {label}{(' — ' + detail) if detail else ''}")
 
print("\n" + "="*60)
print("  OLIST DATA WAREHOUSE — ETL VALIDATION REPORT")
print("="*60 + "\n")
 
 

print("1. ROW COUNTS ")
 
EXPECTED = {
    "fact_order_items":       112650,
    "dim_orders":             99441,
    "dim_customers":          99441,
    "dim_products":           32951,
    "dim_sellers":            3095,
    "dim_payments":           103886,
    "dim_reviews":            99224,
    "dim_product_categories": 71,
}
 
for table, expected in EXPECTED.items():
    cur.execute(f"SELECT COUNT(*) FROM {table};")
    actual = cur.fetchone()[0]
    tolerance = int(expected * 0.01)          # allow 1% variance
    passed = abs(actual - expected) <= tolerance
    check(f"{table}", passed, f"{actual:,} rows (expected ~{expected:,})")
 
 
print("\n 2. FOREIGN KEY INTEGRITY")
 
fk_checks = [
    (
        "fact_order_items - dim_orders",
        """SELECT COUNT(*) FROM fact_order_items foi
           LEFT JOIN dim_orders o ON foi.order_id = o.order_id
           WHERE o.order_id IS NULL"""
    ),
    (
        "fact_order_items - dim_products",
        """SELECT COUNT(*) FROM fact_order_items foi
           LEFT JOIN dim_products p ON foi.product_id = p.product_id
           WHERE p.product_id IS NULL"""
    ),
    (
        "fact_order_items - dim_sellers",
        """SELECT COUNT(*) FROM fact_order_items foi
           LEFT JOIN dim_sellers s ON foi.seller_id = s.seller_id
           WHERE s.seller_id IS NULL"""
    ),
    (
        "dim_orders - dim_customers",
        """SELECT COUNT(*) FROM dim_orders o
           LEFT JOIN dim_customers c ON o.customer_id = c.customer_id
           WHERE c.customer_id IS NULL"""
    ),
    (
        "dim_payments - dim_orders",
        """SELECT COUNT(*) FROM dim_payments p
           LEFT JOIN dim_orders o ON p.order_id = o.order_id
           WHERE o.order_id IS NULL"""
    ),
    (
        "dim_reviews - dim_orders",
        """SELECT COUNT(*) FROM dim_reviews r
           LEFT JOIN dim_orders o ON r.order_id = o.order_id
           WHERE o.order_id IS NULL"""
    ),
]
 
for label, query in fk_checks:
    cur.execute(query)
    orphans = cur.fetchone()[0]
    check(label, orphans == 0, f"{orphans} orphaned rows")
 
 
print("\n 3. NULL CHECKS (critical columns) ")
 
null_checks = [
    ("fact_order_items", "order_id"),
    ("fact_order_items", "product_id"),
    ("fact_order_items", "seller_id"),
    ("fact_order_items", "price"),
    ("dim_orders",       "customer_id"),
    ("dim_orders",       "order_status"),
    ("dim_customers",    "state"),
    ("dim_sellers",      "state"),
    ("dim_reviews",      "review_score"),
    ("dim_payments",     "payment_value"),
]
 
for table, col in null_checks:
    cur.execute(f"SELECT COUNT(*) FROM {table} WHERE {col} IS NULL;")
    nulls = cur.fetchone()[0]
    check(f"{table}.{col}", nulls == 0, f"{nulls} nulls found")
 
 
print("\n 4. BUSINESS LOGIC ")
 
# Negative prices
cur.execute("SELECT COUNT(*) FROM fact_order_items WHERE price < 0;")
check("No negative prices", cur.fetchone()[0] == 0)
 
# Negative freight
cur.execute("SELECT COUNT(*) FROM fact_order_items WHERE freight_value < 0;")
check("No negative freight values", cur.fetchone()[0] == 0)
 
# Review scores in valid range
cur.execute("SELECT COUNT(*) FROM dim_reviews WHERE review_score NOT BETWEEN 1 AND 5;")
check("Review scores between 1-5", cur.fetchone()[0] == 0)
 
# Orders with valid status values
cur.execute("""
    SELECT COUNT(*) FROM dim_orders
    WHERE order_status NOT IN (
        'delivered','shipped','canceled','invoiced',
        'processing','created','approved','unavailable'
    );
""")
check("Valid order status values", cur.fetchone()[0] == 0)
 
# Delivered orders have a delivery timestamp
cur.execute("""
    SELECT COUNT(*) FROM dim_orders
    WHERE order_status = 'delivered' AND order_delivered_ts IS NULL;
""")
check("Delivered orders have delivery timestamp", cur.fetchone()[0] == 0)
 
 
print("\n" + "="*60)
total  = len(results)
passed = sum(1 for r in results if r[0] == PASS)
failed = total - passed
print(f"  TOTAL: {total}  |  PASSED: {passed}  |  FAILED: {failed}")
print("="*60 + "\n")
 
if failed > 0:
    print("Failed checks:")
    for status, label, detail in results:
        if status == FAIL:
            print(f"  • {label}: {detail}")
 
cur.close()
conn.close()