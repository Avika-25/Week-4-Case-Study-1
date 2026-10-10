

CREATE DATABASE IF NOT EXISTS retail_sales_db;
USE retail_sales_db;



ALTER TABLE dim_customer        ADD PRIMARY KEY (CustomerKey);
ALTER TABLE dim_employee        ADD PRIMARY KEY (EmployeeKey);
ALTER TABLE dim_geography       ADD PRIMARY KEY (GeographyKey);
ALTER TABLE dim_product         ADD PRIMARY KEY (ProductKey);
ALTER TABLE dim_reseller        ADD PRIMARY KEY (ResellerKey);
ALTER TABLE dim_sales_territory ADD PRIMARY KEY (SalesTerritoryKey);

ALTER TABLE dim_customer  ADD FOREIGN KEY (GeographyKey) REFERENCES dim_geography(GeographyKey);
ALTER TABLE dim_reseller  ADD FOREIGN KEY (GeographyKey) REFERENCES dim_geography(GeographyKey);
ALTER TABLE dim_geography ADD FOREIGN KEY (SalesTerritoryKey) REFERENCES dim_sales_territory(SalesTerritoryKey);
ALTER TABLE dim_employee  ADD FOREIGN KEY (SalesTerritoryKey) REFERENCES dim_sales_territory(SalesTerritoryKey);

ALTER TABLE fact_internet_sales
    ADD FOREIGN KEY (ProductKey) REFERENCES dim_product(ProductKey),
    ADD FOREIGN KEY (CustomerKey) REFERENCES dim_customer(CustomerKey),
    ADD FOREIGN KEY (SalesTerritoryKey) REFERENCES dim_sales_territory(SalesTerritoryKey);

ALTER TABLE fact_reseller_sales
    ADD FOREIGN KEY (ProductKey) REFERENCES dim_product(ProductKey),
    ADD FOREIGN KEY (ResellerKey) REFERENCES dim_reseller(ResellerKey),
    ADD FOREIGN KEY (EmployeeKey) REFERENCES dim_employee(EmployeeKey),
    ADD FOREIGN KEY (SalesTerritoryKey) REFERENCES dim_sales_territory(SalesTerritoryKey);


-- ---------------------------------------------------------------------
-- 2. VALIDATION — confirm the load actually matches what Python sent
-- ---------------------------------------------------------------------

SELECT 'dim_customer' AS tbl, COUNT(*) AS row_count FROM dim_customer
UNION ALL SELECT 'dim_product', COUNT(*) FROM dim_product
UNION ALL SELECT 'dim_employee', COUNT(*) FROM dim_employee
UNION ALL SELECT 'dim_reseller', COUNT(*) FROM dim_reseller
UNION ALL SELECT 'dim_geography', COUNT(*) FROM dim_geography
UNION ALL SELECT 'dim_sales_territory', COUNT(*) FROM dim_sales_territory
UNION ALL SELECT 'fact_internet_sales', COUNT(*) FROM fact_internet_sales
UNION ALL SELECT 'fact_reseller_sales', COUNT(*) FROM fact_reseller_sales;

-- nothing in either fact table should have negative money values
SELECT COUNT(*) AS bad_internet_rows FROM fact_internet_sales
WHERE SalesAmount < 0 OR TotalProductCost < 0 OR Freight < 0;

SELECT COUNT(*) AS bad_reseller_rows FROM fact_reseller_sales
WHERE SalesAmount < 0 OR TotalProductCost < 0 OR Freight < 0;

-- every customer should now have a sensible age
SELECT MIN(Age) AS youngest, MAX(Age) AS oldest, AVG(Age) AS avg_age FROM dim_customer;

-- ---------------------------------------------------------------------
-- 3. AGGREGATION TABLES — for fast reporting, matching the pattern
-- used in the other two projects
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS agg_sales_by_territory;
CREATE TABLE agg_sales_by_territory AS
SELECT
    st.SalesTerritoryRegion,
    st.SalesTerritoryCountry,
    'Online Retail' AS Sales_Channel,
    COUNT(*) AS order_lines,
    SUM(f.SalesAmount) AS total_sales,
    ROUND(AVG(f.SalesAmount), 2) AS avg_order_value
FROM fact_internet_sales f
JOIN dim_sales_territory st ON st.SalesTerritoryKey = f.SalesTerritoryKey
GROUP BY st.SalesTerritoryRegion, st.SalesTerritoryCountry
UNION ALL
SELECT
    st.SalesTerritoryRegion,
    st.SalesTerritoryCountry,
    'B2B Reseller' AS Sales_Channel,
    COUNT(*),
    SUM(f.SalesAmount),
    ROUND(AVG(f.SalesAmount), 2)
FROM fact_reseller_sales f
JOIN dim_sales_territory st ON st.SalesTerritoryKey = f.SalesTerritoryKey
GROUP BY st.SalesTerritoryRegion, st.SalesTerritoryCountry;

-- ---------------------------------------------------------------------
-- 4. REPORTING TASKS — these are the three Power BI tasks from the
-- brief, answered directly in SQL first so the dashboard has numbers
-- to be checked against.
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
