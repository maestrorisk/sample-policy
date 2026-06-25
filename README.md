# Credit Policies

An [OPA](https://www.openpolicyagent.org/) / Rego policy that turns a loan
application into a structured credit decision: **approve**, **refer** (manual
review), **deny**, or **invalid** (malformed input). The policy is pure and
deterministic — same input, same decision — so it can run anywhere OPA does:
as a sidecar, a library (Wasm/Go), or a server.

## Layout
teste2

| Path | Purpose |
| --- | --- |
| `src/credit/credit.rego` | The decision policy (`package credit`). |
| `src/credit/credit_test.rego` | Test suite (`package credit_test`). |
| `.github/workflows/opa.yml` | CI: check, test, 100% coverage gate, Regal lint. |

## Decision entry point

Evaluate `data.credit.decision`. It returns a single object:

```json
{
  "outcome": "approve",
  "dti": 0.13,
  "approved_amount": 100000,
  "rate_tier": "prime",
  "reasons": []
}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `outcome` | string | `approve` \| `refer` \| `deny` \| `invalid`. |
| `dti` | number | Debt-to-income ratio, rounded to 2 dp. |
| `approved_amount` | number | The loan amount on `approve`, otherwise `0`. |
| `rate_tier` | string | `prime` \| `standard` on `approve`, otherwise `none`. |
| `reasons` | set of strings | Why the application was referred, denied, or rejected; empty on `approve`. |

## Input schema

```json
{
  "applicant": {
    "age": 40,
    "annual_income": 120000,
    "credit_score": 780,
    "employment_status": "employed",
    "existing_monthly_debt": 500
  },
  "loan": {
    "amount": 100000,
    "term_months": 120
  }
}
```

All fields are required. `annual_income`, `existing_monthly_debt`, and
`loan.amount` are in the same currency unit; `term_months` must be a positive
integer.

## Decision logic

Outcomes are evaluated in strict priority order — the first that applies wins:

**`invalid` — fail closed on bad input.** If any required field is missing or
the wrong type, the application is rejected as invalid rather than silently
slipping past a gate. `reasons` lists every offending field. This outranks
every credit decision.

**`deny` — hard declines.** Any one triggers a denial:

- applicant under 18
- no verifiable income (`annual_income <= 0`)
- credit score below 500
- debt-to-income above 0.50
- requested amount over 5× annual income

**`refer` — manual-review triggers.** No decline applies, but any one of:

- credit score in the 500–679 band
- debt-to-income in the 0.36–0.50 caution band
- self-employed (income verification required)
- exposure of 3×–5× annual income

**`approve` — clean application.** No decline and no review trigger. Pricing
tier is set by score: **prime** at 760+, otherwise **standard**.

> **Debt-to-income (DTI)** = `(existing_monthly_debt + new_payment) / monthly_income`,
> where `new_payment` is an interest-free estimate (`loan.amount / term_months`)
> and `monthly_income` is `annual_income / 12`. DTI defaults to a max-risk
> sentinel when income is missing or zero, so a blank income can never pass a
> numeric gate.

## Examples

A strong applicant is approved at the prime tier:

```console
$ echo '{"applicant":{"age":40,"credit_score":780,"annual_income":120000,"employment_status":"employed","existing_monthly_debt":500},"loan":{"amount":100000,"term_months":120}}' \
    | opa eval -d src/credit -I 'data.credit.decision' --format pretty
{
  "approved_amount": 100000,
  "dti": 0.13,
  "outcome": "approve",
  "rate_tier": "prime",
  "reasons": []
}
```

A mid-band score sends the same application to manual review:

```console
$ echo '{"applicant":{"age":40,"credit_score":620,...},"loan":{...}}' \
    | opa eval -d src/credit -I 'data.credit.decision' --format pretty
{
  "approved_amount": 0,
  "dti": 0.13,
  "outcome": "refer",
  "rate_tier": "none",
  "reasons": ["credit score in manual-review band (500-679)"]
}
```

## Commands

```sh
# Check policy (strict mode catches unused vars, unsafe refs, etc.)
opa check --strict ./src/

# Run tests
opa test -v ./src/

# Run tests and fail below 100% line coverage
opa test --coverage --threshold 100 ./src/

# Lint Rego with Regal
regal lint --format github ./src/
```

## CI

`.github/workflows/opa.yml` runs on every push and pull request to `main` and
enforces all four checks above — a drop below 100% line coverage or any Regal
violation fails the build.

## Building a bundle

Package the policy into a distributable OPA bundle. `src/.manifest` declares
`credit` as the bundle root, and `-e credit/decision` records the decision rule
as the entrypoint:

```sh
opa build -b ./src/ --ignore '*_test.rego' -e credit/decision -o bundle.tar.gz
```

`--ignore '*_test.rego'` keeps test files out of the bundle (they sit outside
the `credit` root and would otherwise be rejected). The resulting
`bundle.tar.gz` can be loaded by an OPA agent or served from a bundle server.
