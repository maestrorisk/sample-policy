package credit

import rego.v1

monthly_income := input.applicant.annual_income / 12

# A loan term is only usable for a payment estimate when it is a positive
# number; anything else (missing, zero, negative, non-numeric) is caught by
# input validation below and must never reach the division.
valid_term_months if {
	is_number(input.loan.term_months)
	input.loan.term_months > 0
}

# Approximate, interest-free monthly payment — sufficient for a DTI gate.
# Guarded so a missing or zero term can never raise a divide-by-zero.
new_payment := input.loan.amount / input.loan.term_months if valid_term_months

# Debt-to-income. Defaults to a max-risk sentinel when income is missing or
# zero, so a blank income can never slip through the numeric gates below.
default dti := 999.0

dti := (input.applicant.existing_monthly_debt + new_payment) / monthly_income if {
	monthly_income > 0
}

# --- Input validation ------------------------------------------------------
# Each gate below relies on a field being present and well-typed. A missing
# field makes its gate go undefined (the rule simply doesn't fire), which would
# let a malformed application slip past a decline it should have hit. So we
# validate every required field up front and fail closed to an "invalid"
# outcome that outranks every credit decision.
#
# Validity is expressed as a positive helper rule per field, then negated. This
# is deliberate: `not is_number(input.x)` on a *missing* field evaluates to
# undefined (not true), so the reason would never be added — but negating an
# undefined helper rule correctly yields true. See the valid_* helpers below.

valid_age if is_number(input.applicant.age)

valid_annual_income if is_number(input.applicant.annual_income)

valid_credit_score if is_number(input.applicant.credit_score)

valid_existing_monthly_debt if is_number(input.applicant.existing_monthly_debt)

valid_employment_status if is_string(input.applicant.employment_status)

valid_loan_amount if is_number(input.loan.amount)

invalid_reasons contains "applicant.age missing or not a number" if not valid_age

invalid_reasons contains "applicant.annual_income missing or not a number" if not valid_annual_income

invalid_reasons contains "applicant.credit_score missing or not a number" if not valid_credit_score

invalid_reasons contains "applicant.existing_monthly_debt missing or not a number" if not valid_existing_monthly_debt

invalid_reasons contains "applicant.employment_status missing or not a string" if not valid_employment_status

invalid_reasons contains "loan.amount missing or not a number" if not valid_loan_amount

invalid_reasons contains "loan.term_months missing or not a positive number" if not valid_term_months

# --- Hard declines ---------------------------------------------------------

deny_reasons contains "applicant must be at least 18" if {
	input.applicant.age < 18
}

deny_reasons contains "no verifiable income" if {
	input.applicant.annual_income <= 0
}

deny_reasons contains "credit score below minimum (500)" if {
	input.applicant.credit_score < 500
}

deny_reasons contains "debt-to-income above 0.50" if {
	dti > 0.50
}

deny_reasons contains "requested amount exceeds 5x annual income" if {
	input.loan.amount > input.applicant.annual_income * 5
}

# --- Manual-review triggers ------------------------------------------------

refer_reasons contains "credit score in manual-review band (500-679)" if {
	input.applicant.credit_score >= 500
	input.applicant.credit_score < 680
}

refer_reasons contains "debt-to-income in caution band (0.36-0.50)" if {
	dti >= 0.36
	dti <= 0.50
}

refer_reasons contains "self-employed income verification required" if {
	input.applicant.employment_status == "self_employed"
}

refer_reasons contains "large exposure relative to income (3x-5x)" if {
	input.loan.amount > input.applicant.annual_income * 3
	input.loan.amount <= input.applicant.annual_income * 5
}

# --- Outcome (invalid wins over deny wins over refer wins over approve) -----

outcome := "invalid" if {
	count(invalid_reasons) > 0
}

outcome := "deny" if {
	count(invalid_reasons) == 0
	count(deny_reasons) > 0
}

outcome := "refer" if {
	count(invalid_reasons) == 0
	count(deny_reasons) == 0
	count(refer_reasons) > 0
}

outcome := "approve" if {
	count(invalid_reasons) == 0
	count(deny_reasons) == 0
	count(refer_reasons) == 0
}

# --- Pricing (only meaningful on approve) ----------------------------------

default rate_tier := "none"

rate_tier := "prime" if {
	outcome == "approve"
	input.applicant.credit_score >= 760
}

rate_tier := "standard" if {
	outcome == "approve"
	input.applicant.credit_score < 760
}

default approved_amount := 0

approved_amount := input.loan.amount if {
	outcome == "approve"
}

# --- Reasons surfaced to the caller ----------------------------------------

reasons := invalid_reasons if outcome == "invalid"

reasons := deny_reasons if outcome == "deny"

reasons := refer_reasons if outcome == "refer"

reasons := set() if outcome == "approve"

# --- Final decision object -------------------------------------------------

decision := {
	"outcome": outcome,
	"dti": round(dti * 100) / 100,
	"reasons": reasons,
	"approved_amount": approved_amount,
	"rate_tier": rate_tier,
}
