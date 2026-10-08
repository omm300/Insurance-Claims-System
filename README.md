# Insurance Claims Validation and Exception Reporting System

A batch claims-adjudication system that emulates an **IBM z/OS mainframe job** using
**GnuCOBOL**, with a **Flask + Chart.js web dashboard** on top.

Each incoming claim is pushed through **8 validation gates**. Valid claims are settled
(deductible → co-pay → insurer payable); invalid ones go to an **exception log** with an
error code. Settled claims that need a human look get **review flags**.

## Architecture

```
raw_claims.dat ──► STEP02 DFSORT (sort by policy ID)
                       │
policy_master.dat (DB2)  ─┐
coverage_rates_index.dat  ├─► STEP04 CLMPROC01 (COBOL) ─► CLAIMS_SETTLEMENT_REPORT.txt
(VSAM KSDS)              ─┘                              ─► PLAN_CLAIMS_SUMMARY.txt
                                                         ─► CLAIMS_EXCEPTION_LOG.txt
```

| JCL step | Program | What it does |
|---|---|---|
| STEP01 | IEFBR14 | Verifies `cobc` is installed |
| STEP02 | DFSORT | Stable sort of claims on cols 7–11 (policy ID) |
| STEP03 | IKFCBL00 | Compiles `src/CLMPROC01.cbl` |
| STEP04 | CLMPROC01 | Validates, settles, reports |
| STEP05 | IEBGENER | Verifies the three output datasets |

Return codes follow mainframe convention: **RC 0000** clean run, **RC 0004** completed
with rejects/flags, **RC 0008+** failure.

## Record layouts (fixed width)

**Claims** `data/input/raw_claims.dat` — 27 bytes
`CLAIM-ID(6) POLICY-ID(5) AMOUNT(7, 2 implied decimals) COVER(1) DATE(8 YYYYMMDD)`
Example: `600001700011250000A20260315` = claim 600001, policy 70001, $12,500.00, cover A, 2026-03-15

**Policy master** `data/ref/policy_master.dat` — 53 bytes
`POLICY-ID(5) HOLDER(20) PLAN(4) SUM-INSURED(7, whole $) EFFECTIVE(8) EXPIRY(8) STATUS(1: A/L/C)`

**Coverage index** `data/ref/coverage_rates_index.dat` — 32 bytes
`CODE(1) PLAN(4) DESCRIPTION(12) DEDUCTIBLE(5) COPAY-%(3) PER-CLAIM-LIMIT(7)`

| Code | Plan | Coverage | Deductible | Co-pay | Per-claim limit |
|---|---|---|---|---|---|
| A | HLTH | Hospital | $500 | 10% | $50,000 |
| B | HLTH | Outpatient | $100 | 20% | $5,000 |
| C | AUTO | Collision | $1,000 | 10% | $40,000 |
| D | AUTO | Theft | $500 | 15% | $30,000 |
| E | HOME | Fire/Damage | $1,000 | 10% | $200,000 |
| F | HOME | Theft | $500 | 20% | $20,000 |

## Validation gates (first failure rejects the claim)

| Code | Rule |
|---|---|
| ERR-01 | Invalid format: non-numeric IDs/amount/date, zero amount, impossible month/day |
| ERR-02 | Duplicate claim ID (already settled in this run) |
| ERR-03 | Policy ID not found in master |
| ERR-04 | Coverage code not in index |
| ERR-05 | Coverage doesn't belong to the policy's plan (e.g. auto cover on a health policy) |
| ERR-06 | Policy not active (lapsed or cancelled) |
| ERR-07 | Claim date outside the policy's effective–expiry period |
| ERR-08 | Eligible amount exceeds the policy's **remaining** sum insured (running total per policy) |

## Settlement calculation

```
eligible   = min(claim amount, coverage per-claim limit)
after_ded  = max(0, eligible - deductible)
copay      = after_ded x copay %            (rounded to cents)
payable    = after_ded - copay              (insurer pays)
```

## Review flags (claim is still settled, but logged)

| Code | Status | Meaning |
|---|---|---|
| WRN-01 | CAPD | Claim exceeded the per-claim limit and was capped |
| WRN-02 | REVW | Eligible amount is ≥ 50% of the policy's sum insured, so manual review is needed |
| WRN-03 | NIL | Claim is within the deductible, so payout is $0 |

Status priority on the report: REVW > CAPD > NIL > APPR.

## Run it

**Prerequisites:** GnuCOBOL (`sudo apt-get install gnucobol`), Python 3.9+.

```bash
# Batch only (Linux / macOS / WSL)
bash scripts/run_batch.sh

# Web dashboard
pip install -r requirements.txt
python app.py            # open http://localhost:5000
```

On **Windows**, install GnuCOBOL inside WSL (Ubuntu). The dashboard's *Run Batch* button
calls WSL automatically (set the `WSL_DISTRO` environment variable if your distro isn't
named `Ubuntu`), or double-click `scripts/run_batch.bat`.

## Expected result for the bundled sample data (21 claims)

| Metric | Value |
|---|---|
| Approved | 10 (3 flagged: 600005 REVW, 600006 NIL, 600010 CAPD) |
| Rejected | 11 (one of every error code; ERR-01 x3, ERR-06 x2) |
| Total claimed (approved) | $231,900.00 |
| Insurer payable | $179,775.00 |

## Dashboard tabs

Overview (KPIs + charts) · Analytics · Claims & Input (live pre-flight check, editable
dataset) · Reference Data · Run Batch (JES2-style console) · Settlement Report ·
Plan Summary · Exception Log.

The **pre-flight check** on the Claims tab is a Python mirror of the COBOL gates so you
can see what will happen before submitting the job; the COBOL engine remains the
system of record.

## Project layout

```
app.py                      Flask server + report parsers
src/CLMPROC01.cbl           COBOL batch engine
scripts/run_batch.sh|.bat   JCL emulation (Linux/WSL, Windows launcher)
templates/dashboard.html    Web UI
static/js/chart.min.js      Chart.js (bundled, works offline)
data/input|ref|work|output  Datasets
```

## Known limits

Amount columns print up to 9,999,999.99. Tables hold 100 policies, 20 cover codes and
500 claim IDs per run. Dates are validated for month 1–12 and day 1–31 only (no
per-month day count or leap-year check).
