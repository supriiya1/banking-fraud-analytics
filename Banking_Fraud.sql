-- ========================================================
-- Project   : Banking Fraud Detection & Financial Analytics
-- Author    : Supriya
-- Tool      : Microsoft SQL Server Management Studio (v16)
-- Dataset   : Financial Transactions Dataset: Analytics
--             Source: Kaggle (computingvictor/transactions-fraud-datasets)
-- Scale     : 13.3 Million Transactions | 2,000 Customers | 6,145 Cards
-- Period    : 2010 – 2019
-- ============================================================
-- In this project, analysis is done on 13.3 million banking transactions to detect fraud patterns, customer behavior trends,
-- transaction risks, payment anomalies, revenue growth etc over a decade.
--
-- Areas covered in the analysis:
-- Fraud Detection
-- Customer Risk Profiling
-- Transaction Error Analysis
-- Revenue & Growth Trends
-- Payment Technology Trends
-- Geographic Spending Trends

-- ============================================================

USE Banking_Fraud;
GO

-- ============================================================
-- Query 1: Dataset Overview
-- ============================================================
-- Understand the dataset size and structure before
-- beginning any fraud detection.

SELECT
    'transactions_data' AS table_name,
    COUNT(*) AS total_rows,
    MIN(date) AS earliest_transaction,
    MAX(date) AS latest_transaction,
    COUNT(DISTINCT client_id) AS unique_customers,
    COUNT(DISTINCT card_id) AS unique_cards,
    COUNT(DISTINCT merchant_id) AS unique_merchants
FROM transactions_data

UNION ALL

SELECT 'cards_data', COUNT(*), NULL, NULL, NULL, NULL, NULL
FROM cards_data

UNION ALL

SELECT 'users_data', COUNT(*), NULL, NULL, NULL, NULL, NULL
FROM users_data;

GO

/*
13.3 million transactions between years 2010 and 2019, involving 2,000 customers, 
6,145 credit cards, and more than 100,000 merchants.
The high number of transactions make the dataset suitable for fraud and behavioral analysis.
*/

-- ============================================================
-- Query 2: Revenue Growth Analysis
-- ============================================================
-- Examine the trend of yearly transactions and revenue.

WITH yearly_stats AS (
    SELECT
        LEFT(date, 4) AS transaction_year,
        COUNT(*) AS total_transactions,
        COUNT(DISTINCT client_id) AS active_customers,
        ROUND(SUM(CAST(REPLACE(REPLACE(amount, '$', ''), ',', '') AS FLOAT)), 2) AS total_revenue,
        ROUND(AVG(CAST(REPLACE(REPLACE(amount, '$', ''), ',', '') AS FLOAT)), 2) AS avg_transaction_value
    FROM transactions_data
    WHERE amount NOT LIKE '-%'
    GROUP BY LEFT(date, 4)
)

SELECT
    transaction_year,
    total_transactions,
    active_customers,
    total_revenue,
    avg_transaction_value,
    LAG(total_transactions) OVER (ORDER BY transaction_year) AS prev_year_transactions,
    ROUND(
        CAST(total_transactions - LAG(total_transactions)
        OVER (ORDER BY transaction_year) AS FLOAT) /
        NULLIF(LAG(total_transactions) OVER (ORDER BY transaction_year), 0) * 100
    , 2) AS yoy_growth_pct,
    ROUND(
        CAST(total_revenue - LAG(total_revenue)
        OVER (ORDER BY transaction_year) AS FLOAT) /
        NULLIF(LAG(total_revenue) OVER (ORDER BY transaction_year), 0) * 100
    , 2) AS revenue_growth_pct
FROM yearly_stats
ORDER BY transaction_year;

GO

/*
It has grown steadily at a rate of about 8.7% annually throughout the decade. 2018 was its most active year in terms of volume.

More interesting, however, is the average transaction amount that it climbed from around $38 in 2010 to almost $47 in 2019.
It's nothing remarkable, but it is consistent, and it shows that the customers were spending progressively more per transaction
rather than merely making more transactions over time.
*/

-- ============================================================
-- Query 3: Transaction Error Analysis
-- ============================================================
-- The errors in the transaction data aren't merely technical artifacts.
-- In the banking industry, the patterns of errors say much about fraudulent activities, card issues, and problematic customer behavior.

-- Part A: What kind of errors are we talking about here?
SELECT
    CASE
        WHEN errors IS NULL OR errors = 'NULL' THEN 'No Error'
        ELSE errors
    END AS error_type,
    COUNT(*) AS transaction_count,
    ROUND(CAST(COUNT(*) AS FLOAT) / SUM(COUNT(*)) OVER () * 100, 2) AS pct_of_total,
    ROUND(AVG(CAST(REPLACE(REPLACE(amount, '$', ''), ',', '') AS FLOAT)), 2) AS avg_amount,
    COUNT(DISTINCT client_id) AS affected_customers
FROM transactions_data
GROUP BY CASE
    WHEN errors IS NULL OR errors = 'NULL' THEN 'No Error'
    ELSE errors
END
ORDER BY transaction_count DESC;

GO

-- Part B: Which customers have unusually high error rates?
WITH customer_errors AS (
    SELECT
        client_id,
        COUNT(*) AS total_transactions,
        SUM(CASE WHEN errors IS NOT NULL
            AND errors <> 'NULL' THEN 1 ELSE 0 END) AS error_transactions,
        ROUND(
            CAST(SUM(CASE WHEN errors IS NOT NULL
                AND errors <> 'NULL' THEN 1 ELSE 0 END) AS FLOAT)
            / COUNT(*) * 100
        , 2) AS error_rate_pct
    FROM transactions_data
    GROUP BY client_id
)

SELECT TOP 20
    client_id,
    total_transactions,
    error_transactions,
    error_rate_pct,
    RANK() OVER (ORDER BY error_rate_pct DESC) AS risk_rank
FROM customer_errors
WHERE total_transactions >= 100
ORDER BY error_rate_pct DESC;

GO

-- Part C: High-value transactions with errors — the real red flags
SELECT TOP 50
    t.id AS transaction_id,
    t.date,
    t.client_id,
    t.amount,
    t.use_chip,
    t.merchant_city,
    t.merchant_state,
    t.errors,
    u.credit_score,
    u.yearly_income,
    c.card_type,
    c.card_on_dark_web
FROM transactions_data t
LEFT JOIN users_data u ON t.client_id = u.id
LEFT JOIN cards_data c ON t.card_id = c.id
WHERE t.errors IS NOT NULL
AND t.errors <> 'NULL'
AND CAST(REPLACE(REPLACE(t.amount, '$', ''), ',', '') AS FLOAT) > 500
ORDER BY CAST(REPLACE(REPLACE(t.amount, '$', ''), ',', '') AS FLOAT) DESC;

GO

/*
Most transactions have no errors — which is expected.
The interesting ones are the errors that show up on large transactions. A bad PIN on a $12 grocery purchase
is probably just a customer mistyping. A bad PIN on a $600 transaction from a card that's appeared on the
dark web is a different conversation entirely.

Part C surfaces exactly that combination — high value,error flagged, and cross-referenced against card compromise
status. That's where a fraud analyst would start their day.
*/
-- ============================================================
-- Query 4: Suspicious Card Activity
-- ============================================================
-- There is some information in this data set regarding cards that have appeared on the dark web marketplaces.
-- This query seeks to determine whether there is an association between this information and the activity of the card.

-- Part A: Number of compromised cards?
SELECT
    c.card_on_dark_web,
    COUNT(*) AS total_cards,
    ROUND(CAST(COUNT(*) AS FLOAT) / SUM(COUNT(*)) OVER () * 100, 2) AS pct_of_cards,
    COUNT(DISTINCT c.client_id) AS affected_customers
FROM cards_data c
GROUP BY c.card_on_dark_web;

GO

-- Part B: Are dark web cards really acting differently?
SELECT
    c.card_on_dark_web,
    COUNT(t.id) AS total_transactions,
    ROUND(AVG(CAST(REPLACE(REPLACE(t.amount, '$', ''), ',', '') AS FLOAT)), 2) AS avg_transaction_value,
    ROUND(SUM(CAST(REPLACE(REPLACE(t.amount, '$', ''), ',', '') AS FLOAT)), 2) AS total_spend,
    SUM(CASE WHEN t.errors IS NOT NULL
        AND t.errors <> 'NULL' THEN 1 ELSE 0 END) AS error_count,
    ROUND(
        CAST(SUM(CASE WHEN t.errors IS NOT NULL
            AND t.errors <> 'NULL' THEN 1 ELSE 0 END) AS FLOAT)
        / COUNT(t.id) * 100
    , 2) AS error_rate_pct
FROM transactions_data t
INNER JOIN cards_data c ON t.card_id = c.id
GROUP BY c.card_on_dark_web;

GO

-- Part C: Customers with compromised cards — full profile
SELECT
    u.id AS customer_id,
    u.current_age,
    u.gender,
    u.credit_score,
    u.yearly_income,
    u.total_debt,
    u.num_credit_cards,
    COUNT(DISTINCT c.id) AS total_cards,
    SUM(CASE WHEN c.card_on_dark_web = 'Yes' THEN 1 ELSE 0 END) AS compromised_cards,
    COUNT(t.id) AS total_transactions,
    SUM(CASE WHEN t.errors IS NOT NULL
        AND t.errors <> 'NULL' THEN 1 ELSE 0 END) AS error_transactions
FROM users_data u
LEFT JOIN cards_data c ON u.id = c.client_id
LEFT JOIN transactions_data t ON u.id = t.client_id
WHERE c.card_on_dark_web = 'Yes'
GROUP BY u.id, u.current_age, u.gender, u.credit_score,
         u.yearly_income, u.total_debt, u.num_credit_cards
ORDER BY compromised_cards DESC, error_transactions DESC;

GO

/*
It’s hard to argue that the dark web flag would be valuable at all if it doesn’t indicate any differences in behavior. 
Question Part B directly addresses that by comparing the error rates between compromised and clean cards.

If the error rate is indeed significantly higher for the compromised cards, that means the flag is an active risk indicator,
not historical noise. Otherwise, that indicates the information has not been used actively – just stored for future use.

Both results are useful because it helps the fraud team decide whether to treat this as fire or just smoke.
*/

-- ============================================================
-- Query 5: Payment Technology trends
-- ============================================================
-- The dataset includes the exact time frame during which chip cards became the predominant payment technology in the US.
-- It was interesting to see this shift in the data.

WITH payment_yearly AS (
    SELECT
        LEFT(date, 4) AS transaction_year,
        use_chip AS payment_method,
        COUNT(*) AS transaction_count,
        ROUND(AVG(CAST(REPLACE(REPLACE(amount, '$', ''), ',', '') AS FLOAT)), 2) AS avg_amount
    FROM transactions_data
    WHERE amount NOT LIKE '-%'
    GROUP BY LEFT(date, 4), use_chip
)

SELECT
    transaction_year,
    SUM(CASE WHEN payment_method = 'Swipe Transaction'
        THEN transaction_count ELSE 0 END) AS swipe_count,
    SUM(CASE WHEN payment_method = 'Chip Transaction'
        THEN transaction_count ELSE 0 END) AS chip_count,
    SUM(CASE WHEN payment_method = 'Online Transaction'
        THEN transaction_count ELSE 0 END) AS online_count,
    SUM(transaction_count) AS total_count,
    ROUND(CAST(SUM(CASE WHEN payment_method = 'Swipe Transaction'
        THEN transaction_count ELSE 0 END) AS FLOAT)
        / SUM(transaction_count) * 100, 1) AS swipe_pct,
    ROUND(CAST(SUM(CASE WHEN payment_method = 'Chip Transaction'
        THEN transaction_count ELSE 0 END) AS FLOAT)
        / SUM(transaction_count) * 100, 1) AS chip_pct,
    ROUND(CAST(SUM(CASE WHEN payment_method = 'Online Transaction'
        THEN transaction_count ELSE 0 END) AS FLOAT)
        / SUM(transaction_count) * 100, 1) AS online_pct
FROM payment_yearly
GROUP BY transaction_year
ORDER BY transaction_year;

GO

/*
By 2010, pretty much everything was swipe. By 2019, chip transactions comprised nearly 50 percent of all transactions.

The reason this is important for fraud is that each chip-based transaction creates a unique code, which means that once
a card number has been skimmed through a chip-based purchase, it cannot be replayed like it could with a magnetic strip.
As the chip became more widely used, so too did the nature of fraud change. And since online transactions increased every
year, this created another avenue for fraud in the form of card-not-present fraud that chip technology does not prevent.

When you look at all three of these lines together, you see more about the trends in banking fraud than with any other
metric alone.
*/

-- ============================================================
-- Query 6: High Value Customers
-- ============================================================
-- Identifies the platform's most valuable customers based on total spending and frequency of transactions.

WITH customer_spend AS (
    SELECT
        t.client_id,
        COUNT(*) AS total_transactions,
        ROUND(SUM(CAST(REPLACE(REPLACE(t.amount, '$', ''), ',', '') AS FLOAT)), 2) AS total_spend,
        ROUND(AVG(CAST(REPLACE(REPLACE(t.amount, '$', ''), ',', '') AS FLOAT)), 2) AS avg_transaction,
        MAX(CAST(REPLACE(REPLACE(t.amount, '$', ''), ',', '') AS FLOAT)) AS max_single_transaction,
        COUNT(DISTINCT LEFT(t.date, 7)) AS active_months,
        u.credit_score,
        u.yearly_income,
        u.current_age,
        u.gender
    FROM transactions_data t
    LEFT JOIN users_data u ON t.client_id = u.id
    WHERE t.amount NOT LIKE '-%'
    GROUP BY t.client_id, u.credit_score, u.yearly_income,
             u.current_age, u.gender
),

spend_ranked AS (
    SELECT *,
        NTILE(5) OVER (ORDER BY total_spend DESC) AS spend_quintile,
        RANK() OVER (ORDER BY total_spend DESC) AS spend_rank,
        SUM(total_spend) OVER () AS platform_total_spend
    FROM customer_spend
)

SELECT
    client_id,
    spend_rank,
    total_transactions,
    total_spend,
    avg_transaction,
    max_single_transaction,
    active_months,
    credit_score,
    yearly_income,
    current_age,
    gender,
    ROUND(total_spend / platform_total_spend * 100, 4) AS pct_of_total_revenue,
    CASE spend_quintile
        WHEN 1 THEN 'Platinum'
        WHEN 2 THEN 'Gold'
        WHEN 3 THEN 'Silver'
        WHEN 4 THEN 'Bronze'
        ELSE 'Standard'
    END AS customer_tier
FROM spend_ranked
ORDER BY spend_rank;

GO

-- Tier revenue breakdown
WITH customer_spend AS (
    SELECT
        t.client_id,
        COUNT(*) AS total_transactions,
        ROUND(SUM(CAST(REPLACE(REPLACE(t.amount, '$', ''), ',', '') AS FLOAT)), 2) AS total_spend,
        ROUND(AVG(CAST(REPLACE(REPLACE(t.amount, '$', ''), ',', '') AS FLOAT)), 2) AS avg_transaction
    FROM transactions_data t
    WHERE t.amount NOT LIKE '-%'
    GROUP BY t.client_id
),
spend_tiered AS (
    SELECT *,
        NTILE(5) OVER (ORDER BY total_spend DESC) AS spend_quintile
    FROM customer_spend
)

SELECT
    CASE spend_quintile
        WHEN 1 THEN 'Platinum'
        WHEN 2 THEN 'Gold'
        WHEN 3 THEN 'Silver'
        WHEN 4 THEN 'Bronze'
        ELSE 'Standard'
    END AS customer_tier,
    COUNT(*) AS total_customers,
    ROUND(AVG(total_transactions), 0) AS avg_transactions,
    ROUND(AVG(total_spend), 2) AS avg_spend,
    ROUND(SUM(total_spend), 2) AS tier_total_revenue,
    ROUND(SUM(total_spend) /
        SUM(SUM(total_spend)) OVER () * 100, 2) AS pct_of_revenue
FROM spend_tiered
GROUP BY spend_quintile
ORDER BY spend_quintile;

GO

/*
Outlier for customer 708 – $1,094,355 spent through 8,681 transactions within a decade. It is both the most valuable
customer for the platform and concentration risk.

Tier summary provides information on whether revenues are distributed evenly among customers or concentrated at
the top. In banking datasets, the top 20% of customers account for approximately 80% of revenues. Whether it’s the case
here or it’s even more concentrated says something about the risk profile of the portfolio.
*/

-- ============================================================
-- Query 7: Geographic Transaction Analysis
-- ============================================================
-- Geographical analysis of transactions provides information on where your customers live and spend money – and
-- where the platform needs to improve its geographical coverage.

SELECT
    CASE
        WHEN merchant_state IS NULL
        OR merchant_state = 'NULL' THEN 'Online / International'
        ELSE merchant_state
    END AS state,
    COUNT(*) AS total_transactions,
    COUNT(DISTINCT client_id) AS unique_customers,
    COUNT(DISTINCT merchant_id) AS unique_merchants,
    ROUND(SUM(CAST(REPLACE(REPLACE(amount, '$', ''), ',', '') AS FLOAT)), 2) AS total_revenue,
    ROUND(AVG(CAST(REPLACE(REPLACE(amount, '$', ''), ',', '') AS FLOAT)), 2) AS avg_transaction_value,
    ROUND(CAST(COUNT(*) AS FLOAT) /
        SUM(COUNT(*)) OVER () * 100, 2) AS pct_of_transactions,
    RANK() OVER (ORDER BY COUNT(*) DESC) AS volume_rank
FROM transactions_data
WHERE amount NOT LIKE '-%'
GROUP BY CASE
    WHEN merchant_state IS NULL
    OR merchant_state = 'NULL' THEN 'Online / International'
    ELSE merchant_state
END
ORDER BY total_transactions DESC;

GO

/*
Online transactions make up the biggest single category with 1.56 million, more than any single state.
In its own right, this is an important discovery, as by the end of this data set, online had already become the dominant
channel by volume.

Of the physical states, California and Texas are on top due to their large populations. However, the real issue is the states
that have many customers but few merchants, as this indicates under-service.
*/

-- ============================================================
-- Query 8: Merchant category Analysis
-- ============================================================
-- MCC codes indicate the nature of the business that the merchant does. This query provides insights into categories
-- that dominate transaction volume and also have high error rates.

SELECT TOP 20
    mcc,
    COUNT(*) AS total_transactions,
    COUNT(DISTINCT client_id) AS unique_customers,
    COUNT(DISTINCT merchant_id) AS unique_merchants,
    ROUND(SUM(CAST(REPLACE(REPLACE(amount, '$', ''), ',', '') AS FLOAT)), 2) AS total_revenue,
    ROUND(AVG(CAST(REPLACE(REPLACE(amount, '$', ''), ',', '') AS FLOAT)), 2) AS avg_transaction_value,
    SUM(CASE WHEN errors IS NOT NULL
        AND errors <> 'NULL' THEN 1 ELSE 0 END) AS error_count,
    ROUND(
        CAST(SUM(CASE WHEN errors IS NOT NULL
            AND errors <> 'NULL' THEN 1 ELSE 0 END) AS FLOAT)
        / COUNT(*) * 100
    , 2) AS error_rate_pct,
    RANK() OVER (ORDER BY COUNT(*) DESC) AS volume_rank
FROM transactions_data
WHERE amount NOT LIKE '-%'
AND mcc IS NOT NULL
GROUP BY mcc
ORDER BY total_transactions DESC;

GO

/*
Grocery stores and restaurants take the lead in transactions per customer, not because of the transaction amount,
but because people go there many times per week. This makes them crucial merchant relationships.

error_rate_pct will be the column of interest for the fraud team. The higher the error rate of a particular MCC
compared to the platform average, the more likely that terminals belonging to this merchant category have skimming,
or the merchant is involved in a fraud scheme. At least, the former needs investigation to avoid the latter.

*/

-- ============================================================
-- Query 9: Refunds and Reversals Analysis
-- ============================================================
-- Negative values indicate refunds/reversals/chargebacks. Refunds up to a certain level are considered normal and healthy.
-- High refunds for some merchants/customers are a sign of fraud.

-- Part A: Overall refund overview
SELECT
    COUNT(*) AS total_negative_transactions,
    ROUND(CAST(COUNT(*) AS FLOAT) /
        (SELECT COUNT(*) FROM transactions_data) * 100, 2) AS pct_of_all_transactions,
    ROUND(AVG(CAST(REPLACE(REPLACE(amount, '$', ''), ',', '') AS FLOAT)), 2) AS avg_refund_value,
    ROUND(MIN(CAST(REPLACE(REPLACE(amount, '$', ''), ',', '') AS FLOAT)), 2) AS largest_refund,
    ROUND(SUM(CAST(REPLACE(REPLACE(amount, '$', ''), ',', '') AS FLOAT)), 2) AS total_refund_value,
    COUNT(DISTINCT client_id) AS customers_with_refunds,
    COUNT(DISTINCT merchant_id) AS merchants_with_refunds
FROM transactions_data
WHERE amount LIKE '-%';

GO

-- Part B: Customers with the most refund activity
WITH refund_customers AS (
    SELECT
        client_id,
        COUNT(*) AS refund_count,
        ROUND(SUM(CAST(REPLACE(REPLACE(amount, '$', ''), ',', '') AS FLOAT)), 2) AS total_refund_amount,
        ROUND(AVG(CAST(REPLACE(REPLACE(amount, '$', ''), ',', '') AS FLOAT)), 2) AS avg_refund
    FROM transactions_data
    WHERE amount LIKE '-%'
    GROUP BY client_id
),
total_transactions AS (
    SELECT client_id, COUNT(*) AS total_txns
    FROM transactions_data
    GROUP BY client_id
)

SELECT TOP 20
    r.client_id,
    r.refund_count,
    t.total_txns,
    ROUND(CAST(r.refund_count AS FLOAT) / t.total_txns * 100, 2) AS refund_rate_pct,
    r.total_refund_amount,
    r.avg_refund,
    RANK() OVER (ORDER BY r.refund_count DESC) AS refund_rank
FROM refund_customers r
INNER JOIN total_transactions t ON r.client_id = t.client_id
ORDER BY refund_count DESC;

GO

/*
Around 2.9% of transactions are negative, which is acceptable within the normal range of a retail banking portfolio.

The highest amount of refund is capped at -$500 and repeats precisely 176 times, indicating that it might be a system
limitation rather than refund activity. Should be noted to the engineering department.

Fraudsters can be found among the customers who dispute more transactions than the average transaction dispute rate on
the platform. A frequent buyer, followed by disputes on his purchases, is a known pattern of fraud. Disputes' amounts
usually occur in the same merchants or time frames.
*/

-- ============================================================
-- Query 10: Analysis of the Transaction Timing
-- ============================================================
-- Transaction timing plays an important role in detecting fraudulent activity. Honest customers make purchases during daytime hours. 
-- Meanwhile, fraudsters tend to conduct transactions during late night hours.

WITH hourly_stats AS (
    SELECT
        CAST(SUBSTRING(date, 12, 2) AS INT) AS transaction_hour,
        COUNT(*) AS transaction_count,
        ROUND(AVG(CAST(REPLACE(REPLACE(amount, '$', ''), ',', '') AS FLOAT)), 2) AS avg_amount,
        SUM(CASE WHEN errors IS NOT NULL
            AND errors <> 'NULL' THEN 1 ELSE 0 END) AS error_count,
        ROUND(
            CAST(SUM(CASE WHEN errors IS NOT NULL
                AND errors <> 'NULL' THEN 1 ELSE 0 END) AS FLOAT)
            / COUNT(*) * 100
        , 2) AS error_rate_pct
    FROM transactions_data
    WHERE LEN(date) >= 13
    GROUP BY CAST(SUBSTRING(date, 12, 2) AS INT)
)

SELECT
    transaction_hour,
    transaction_count,
    ROUND(CAST(transaction_count AS FLOAT) /
        SUM(transaction_count) OVER () * 100, 2) AS pct_of_daily_volume,
    avg_amount,
    error_count,
    error_rate_pct,
    CASE
        WHEN transaction_hour BETWEEN 0 AND 5 THEN 'Late Night'
        WHEN transaction_hour BETWEEN 6 AND 11 THEN 'Morning'
        WHEN transaction_hour BETWEEN 12 AND 17 THEN 'Afternoon Peak'
        WHEN transaction_hour BETWEEN 18 AND 21 THEN 'Evening'
        ELSE 'Night'
    END AS time_segment,
    RANK() OVER (ORDER BY error_rate_pct DESC) AS fraud_risk_rank
FROM hourly_stats
ORDER BY transaction_hour;

GO

/*
The afternoon peak period (12:00 - 18:00) accounts for around 45% of total transactions — not very surprising.

The late night period (02:00 – 06:00) has a low transaction volume but deserves some attention. In case if an error rate in this period
is significantly higher than the afternoon average, it should be taken into account.
Criminals tend to use off-hours because of obvious reasons — less supervision, slow bank reaction, customers being asleep.

The fraud_risk_rank field makes it easy to pass this task to operations in order of importance. 
*/

-- ============================================================
-- Query 11: Card and Payment Method Risk Analysis
-- ============================================================
-- All cards are not created equally in terms of fraud.
-- The following query analyzes transaction patterns and error rates by card brand, type, and whether or not it has a chip
-- in order to see if the card itself is a risk factor.

-- Part A: Analyzing by card brand and type                                         
SELECT
    c.card_brand,
    c.card_type,
    COUNT(DISTINCT c.id) AS total_cards,
    COUNT(t.id) AS total_transactions,
    ROUND(AVG(CAST(REPLACE(REPLACE(t.amount, '$', ''), ',', '') AS FLOAT)), 2) AS avg_transaction,
    ROUND(SUM(CAST(REPLACE(REPLACE(t.amount, '$', ''), ',', '') AS FLOAT)), 2) AS total_revenue,
    SUM(CASE WHEN t.errors IS NOT NULL
        AND t.errors <> 'NULL' THEN 1 ELSE 0 END) AS total_errors,
    ROUND(
        CAST(SUM(CASE WHEN t.errors IS NOT NULL
            AND t.errors <> 'NULL' THEN 1 ELSE 0 END) AS FLOAT)
        / NULLIF(COUNT(t.id), 0) * 100
    , 2) AS error_rate_pct,
    SUM(CASE WHEN c.card_on_dark_web = 'Yes' THEN 1 ELSE 0 END) AS dark_web_exposures
FROM cards_data c
LEFT JOIN transactions_data t ON c.id = t.card_id
WHERE t.amount NOT LIKE '-%'
GROUP BY c.card_brand, c.card_type
ORDER BY total_transactions DESC;

GO

 -- Part B: Is there really any difference between chip and no chip?
SELECT
    c.has_chip,
    COUNT(DISTINCT c.id) AS total_cards,
    COUNT(t.id) AS total_transactions,
    ROUND(AVG(CAST(REPLACE(REPLACE(t.amount, '$', ''), ',', '') AS FLOAT)), 2) AS avg_transaction,
    SUM(CASE WHEN t.errors IS NOT NULL
        AND t.errors <> 'NULL' THEN 1 ELSE 0 END) AS error_count,
    ROUND(
        CAST(SUM(CASE WHEN t.errors IS NOT NULL
            AND t.errors <> 'NULL' THEN 1 ELSE 0 END) AS FLOAT)
        / NULLIF(COUNT(t.id), 0) * 100
    , 2) AS error_rate_pct,
    SUM(CASE WHEN c.card_on_dark_web = 'Yes'
        THEN 1 ELSE 0 END) AS dark_web_count
FROM cards_data c
LEFT JOIN transactions_data t ON c.id = t.card_id
GROUP BY c.has_chip;

GO

/*
The chip vs no-chip analysis provides the most actionable insights of this query. 
Chip transactions create a unique transaction code each time, which means that stolen data cannot be used in replay attacks. 
This does not apply to swipe transactions.

If chip transactions have fewer errors than swipe transactions, it provides evidence for the efforts of the industry to adopt chip technology.
If there is only a marginal difference between chip and swipe transactions in terms of errors, it could be argued that perhaps
the errors recorded here are not even related to fraud.

In any case, knowing the answer will help the product team convince management of the need to move towards chips.
*/

-- ============================================================
-- Query 12: Customer Risk Profile
-- ============================================================
-- Aggregates the credit score, income level, debt, card compromised status, and transaction error rate into one
-- risk profile for each customer.
-- It is the type of analysis that a fraud analyst would use to prioritize their watch list each morning.

WITH customer_profile AS (
    SELECT
        u.id AS customer_id,
        u.current_age,
        u.gender,
        u.credit_score,
        u.yearly_income,
        u.total_debt,
        u.num_credit_cards,
        COUNT(t.id) AS total_transactions,
        ROUND(SUM(CAST(REPLACE(REPLACE(t.amount, '$', ''), ',', '') AS FLOAT)), 2) AS total_spend,
        ROUND(AVG(CAST(REPLACE(REPLACE(t.amount, '$', ''), ',', '') AS FLOAT)), 2) AS avg_spend,
        SUM(CASE WHEN t.errors IS NOT NULL
            AND t.errors <> 'NULL' THEN 1 ELSE 0 END) AS total_errors,
        COUNT(DISTINCT c.id) AS total_cards,
        SUM(CASE WHEN c.card_on_dark_web = 'Yes'
            THEN 1 ELSE 0 END) AS compromised_cards
    FROM users_data u
    LEFT JOIN transactions_data t ON u.id = t.client_id
    LEFT JOIN cards_data c ON u.id = c.client_id
    WHERE t.amount NOT LIKE '-%'
    GROUP BY u.id, u.current_age, u.gender, u.credit_score,
             u.yearly_income, u.total_debt, u.num_credit_cards
)

SELECT
    customer_id,
    current_age,
    gender,
    credit_score,
    yearly_income,
    total_debt,
    num_credit_cards,
    total_transactions,
    total_spend,
    avg_spend,
    total_errors,
    compromised_cards,
    CASE
        WHEN credit_score >= 750
        AND compromised_cards = 0
        AND total_errors = 0 THEN 'Low Risk'
        WHEN credit_score >= 650
        AND compromised_cards <= 1
        AND total_errors <= 5 THEN 'Moderate Risk'
        WHEN credit_score >= 550
        OR compromised_cards >= 1
        OR total_errors > 10 THEN 'High Risk'
        ELSE 'Critical Risk'
    END AS risk_classification,
    RANK() OVER (ORDER BY total_spend DESC) AS spend_rank,
    NTILE(4) OVER (ORDER BY credit_score DESC) AS credit_quartile
FROM customer_profile
ORDER BY
    CASE
        WHEN credit_score >= 750 AND compromised_cards = 0 THEN 4
        WHEN credit_score >= 650 AND compromised_cards <= 1 THEN 3
        WHEN credit_score >= 550 OR compromised_cards >= 1 THEN 2
        ELSE 1
    END ASC,
    total_errors DESC;

GO

/*
The risk classification above considers three factors: credit score, card compromised, and error rate. 
None of these factors alone can provide sufficient information. 
A client with a perfect credit score but with his or her card compromised online would still be at risk. On the other hand, 
a client with a low error rate, but poor credit score and high debt level, would be another risk.

This is the reason why I used CASE WHEN with several conditions instead of using just one threshold. 
The NTILE quartile for credit helps to determine how each client stands in relation to all other clients rather than compared to a set standard.

The clients ranked at the top of this output – Critical Risk followed by High Risk – are those that the fraud analyst would first review in the morning.
*/