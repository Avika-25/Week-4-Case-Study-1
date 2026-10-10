-- ---------------------------------------------------------------------
-- 4. REPORTING TASKS 
-- ---------------------------------------------------------------------

-- 4.1 Underperforming sales territories — total sales and average order
-- value per territory, both channels combined
SELECT
    SalesTerritoryRegion,
    SalesTerritoryCountry,
    SUM(total_sales) AS total_sales,
    ROUND(AVG(avg_order_value), 2) AS avg_order_value
FROM agg_sales_by_territory
GROUP BY SalesTerritoryRegion, SalesTerritoryCountry
ORDER BY total_sales ASC;   -- lowest first = the territories that need attention

-- 4.2 Customer segmentation by occupation and income — average sales
-- per customer, so we can see which segments spend below average
SELECT
    c.Occupation,
    c.YearlyIncome,
    COUNT(DISTINCT c.CustomerKey) AS customers,
    ROUND(SUM(f.SalesAmount) / COUNT(DISTINCT c.CustomerKey), 2) AS avg_sales_per_customer
FROM fact_internet_sales f
JOIN dim_customer c ON c.CustomerKey = f.CustomerKey
GROUP BY c.Occupation, c.YearlyIncome
ORDER BY avg_sales_per_customer ASC;

-- same thing, but bucketed by income band rather than the exact figure
-- (easier to read as a report than every distinct income value)
SELECT
    c.Occupation,
    CASE
        WHEN c.YearlyIncome < 30000 THEN 'Under 30K'
        WHEN c.YearlyIncome < 60000 THEN '30K-60K'
        WHEN c.YearlyIncome < 90000 THEN '60K-90K'
        ELSE '90K+'
    END AS income_band,
    COUNT(DISTINCT c.CustomerKey) AS customers,
    ROUND(SUM(f.SalesAmount) / COUNT(DISTINCT c.CustomerKey), 2) AS avg_sales_per_customer
FROM fact_internet_sales f
JOIN dim_customer c ON c.CustomerKey = f.CustomerKey
GROUP BY c.Occupation, income_band
ORDER BY c.Occupation, income_band;

-- 4.3 Which age group under 50 should be targeted for marketing —
-- total and average sales by the Age_Group the notebook calculated
SELECT
    c.Age_Group,
    COUNT(DISTINCT c.CustomerKey) AS customers,
    SUM(f.SalesAmount) AS total_sales,
    ROUND(SUM(f.SalesAmount) / COUNT(DISTINCT c.CustomerKey), 2) AS avg_sales_per_customer
FROM fact_internet_sales f
JOIN dim_customer c ON c.CustomerKey = f.CustomerKey
WHERE c.Age < 50
GROUP BY c.Age_Group
ORDER BY total_sales DESC;

-- ---------------------------------------------------------------------
-- 5. GENERAL SALES & PRODUCT PERFORMANCE (problem statement, challenge 3)
-- ---------------------------------------------------------------------

-- top and bottom selling products by revenue, both channels combined
SELECT
    p.Product,
    p.Category,
    p.Subcategory,
    SUM(combined.SalesAmount) AS total_revenue,
    SUM(combined.TotalProductCost) AS total_cost,
    SUM(combined.SalesAmount) - SUM(combined.TotalProductCost) AS gross_profit
FROM (
    SELECT ProductKey, SalesAmount, TotalProductCost FROM fact_internet_sales
    UNION ALL
    SELECT ProductKey, SalesAmount, TotalProductCost FROM fact_reseller_sales
) combined
JOIN dim_product p ON p.ProductKey = combined.ProductKey
GROUP BY p.Product, p.Category, p.Subcategory
ORDER BY total_revenue DESC;

-- monthly sales trend, both channels combined
SELECT
    DATE_FORMAT(order_date, '%Y-%m') AS sales_month,
    SUM(SalesAmount) AS total_sales
FROM (
    SELECT OrderDate AS order_date, SalesAmount FROM fact_internet_sales
    UNION ALL
    SELECT OrderDate AS order_date, SalesAmount FROM fact_reseller_sales
) combined
GROUP BY DATE_FORMAT(order_date, '%Y-%m')
ORDER BY sales_month;
