# banking-fraud-analytics
Banking fraud detection and financial analytics using SQL and Python
# Banking Fraud Detection & Financial Analytics
**SQL Server | Python (Pandas) | 13.3M Transactions | 2010–2019**

---

## About This Project

I analyzed 13.3 million real banking transactions to find fraud hiding in the data.
Not obvious fraud — the kind that hides in late-night transactions, cards quietly listed on dark web marketplaces, and customers whose error rates are just a little too high.

The analysis covers Fraud Detection, Customer Risk, Revenue Trends, Payment Technology, and Geographic Spending.

---

## What I Found

- **13.3 million** transactions across 10 years — 2,000 customers, 6,145 cards
- Cards flagged on the **dark web** had higher error rates — it's a real signal, not just a label
- Revenue grew **~8.7% every year** — customers were also spending more per transaction, not just transacting more
- **Chip cards hit ~50%** of all transactions by 2019, pushing fraud from card skimming to online
- **2am–6am** had the highest error rates despite low volume — fraudsters work nights
- **Online was the biggest channel** — more transactions than any single US state
- One customer spent **over $1 million** in 10 years — valuable, but also a risk to watch

---

## What I Analyzed

| Area | What I looked at |
|---|---|
| Dataset Overview | Size, date range, unique customers, cards and merchants |
| Revenue Growth | Year over year transaction volume and revenue trends |
| Transaction Errors | Error types, high-risk customers, errors on high-value transactions |
| Suspicious Cards | Do dark web flagged cards actually behave differently? |
| Payment Technology | How swipe, chip and online payments shifted across the decade |
| High-Value Customers | Top spenders tiered into Platinum, Gold, Silver, Bronze, Standard |
| Geographic Trends | State-level volume, revenue and merchant density |
| Merchant Categories | Which merchant types had the highest error rates |
| Refunds & Reversals | Is the refund rate normal — or are some customers gaming it? |
| Transaction Timing | Which hours of the day carry the most fraud risk |
| Card Risk Analysis | Chip vs swipe error rates and dark web exposure by card type |
| Customer Risk Profiles | Risk scoring using credit score, error rate and card compromise status |

---

## Files

| File | What it contains |
|---|---|
| `Banking_Fraud_Analytics.sql` | 12 SQL queries with findings and comments |
| `Banking_Fraud_Analytics.ipynb` | Full Python analysis notebook |

---

## Dataset

[Kaggle — Financial Transactions Fraud Dataset](https://www.kaggle.com/datasets/computingvictor/transactions-fraud-datasets)  
4 tables | 13.3M transactions | 2,000 customers | 6,145 cards | 2010–2019

---

## Author

**Supriya Pagadala** — Data Analyst | SQL • Python  
📧 supriiya18s@gmail.com | [GitHub](https://github.com/supriiya1)
