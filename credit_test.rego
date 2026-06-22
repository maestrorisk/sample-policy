package credit_test

import rego.v1

import data.credit

# A strong applicant: high score, low DTI, salaried.
test_strong_applicant_is_approved if {
	d := credit.decision with input as {
		"applicant": {"age": 40, "credit_score": 780, "annual_income": 120000, "employment_status": "employed", "existing_monthly_debt": 500},
		"loan": {"amount": 100000, "term_months": 120},
	}
	d.outcome == "approve"
	d.rate_tier == "prime"
	d.approved_amount == 100000
}

# Mid-band score sends the application to manual review.
test_midband_score_is_referred if {
	d := credit.decision with input as {
		"applicant": {"age": 40, "credit_score": 620, "annual_income": 120000, "employment_status": "employed", "existing_monthly_debt": 500},
		"loan": {"amount": 100000, "term_months": 120},
	}
	d.outcome == "refer"
}

# Self-employed always needs verification, even with a great score.
test_self_employed_is_referred if {
	d := credit.decision with input as {
		"applicant": {"age": 40, "credit_score": 800, "annual_income": 120000, "employment_status": "self_employed", "existing_monthly_debt": 500},
		"loan": {"amount": 100000, "term_months": 120},
	}
	d.outcome == "refer"
}

# A minor is a hard decline regardless of everything else.
test_minor_is_denied if {
	d := credit.decision with input as {
		"applicant": {"age": 16, "credit_score": 800, "annual_income": 120000, "employment_status": "employed", "existing_monthly_debt": 0},
		"loan": {"amount": 50000, "term_months": 120},
	}
	d.outcome == "deny"
}

# High debt load relative to income is a hard decline on DTI.
test_high_dti_is_denied if {
	d := credit.decision with input as {
		"applicant": {"age": 40, "credit_score": 800, "annual_income": 60000, "employment_status": "employed", "existing_monthly_debt": 2500},
		"loan": {"amount": 30000, "term_months": 24},
	}
	d.outcome == "deny"
}

# Zero income is unverifiable income — a hard decline.
test_no_verifiable_income_is_denied if {
	d := credit.decision with input as {
		"applicant": {"age": 40, "credit_score": 780, "annual_income": 0, "employment_status": "employed", "existing_monthly_debt": 0},
		"loan": {"amount": 10000, "term_months": 120},
	}
	d.outcome == "deny"
	d.reasons["no verifiable income"]
}

# A score below the floor is a hard decline, distinct from the review band.
test_low_credit_score_is_denied if {
	d := credit.decision with input as {
		"applicant": {"age": 40, "credit_score": 450, "annual_income": 120000, "employment_status": "employed", "existing_monthly_debt": 500},
		"loan": {"amount": 100000, "term_months": 120},
	}
	d.outcome == "deny"
	d.reasons["credit score below minimum (500)"]
}

# Borrowing more than 5x income is a hard decline even at low DTI.
test_amount_over_5x_income_is_denied if {
	d := credit.decision with input as {
		"applicant": {"age": 40, "credit_score": 780, "annual_income": 50000, "employment_status": "employed", "existing_monthly_debt": 0},
		"loan": {"amount": 300000, "term_months": 360},
	}
	d.outcome == "deny"
	d.reasons["requested amount exceeds 5x annual income"]
}

# DTI in the caution band (0.36-0.50) is a manual-review trigger.
test_dti_caution_band_is_referred if {
	d := credit.decision with input as {
		"applicant": {"age": 40, "credit_score": 780, "annual_income": 120000, "employment_status": "employed", "existing_monthly_debt": 3000},
		"loan": {"amount": 100000, "term_months": 120},
	}
	d.outcome == "refer"
	d.reasons["debt-to-income in caution band (0.36-0.50)"]
}

# Exposure of 3x-5x income is a manual-review trigger, not a decline.
test_large_exposure_is_referred if {
	d := credit.decision with input as {
		"applicant": {"age": 40, "credit_score": 780, "annual_income": 100000, "employment_status": "employed", "existing_monthly_debt": 0},
		"loan": {"amount": 350000, "term_months": 360},
	}
	d.outcome == "refer"
	d.reasons["large exposure relative to income (3x-5x)"]
}

# An approval below the prime threshold (760) is priced at the standard tier.
test_approve_below_prime_is_standard_tier if {
	d := credit.decision with input as {
		"applicant": {"age": 40, "credit_score": 720, "annual_income": 120000, "employment_status": "employed", "existing_monthly_debt": 500},
		"loan": {"amount": 100000, "term_months": 120},
	}
	d.outcome == "approve"
	d.rate_tier == "standard"
}

# --- Input validation (fail closed) ----------------------------------------

# A missing credit_score must not silently skip the credit-score gate; it is
# invalid input, not an approval.
test_missing_credit_score_is_invalid if {
	d := credit.decision with input as {
		"applicant": {"age": 40, "annual_income": 120000, "employment_status": "employed", "existing_monthly_debt": 500},
		"loan": {"amount": 100000, "term_months": 120},
	}
	d.outcome == "invalid"
	d.reasons["applicant.credit_score missing or not a number"]
}

# A missing age must not bypass the minor check.
test_missing_age_is_invalid if {
	d := credit.decision with input as {
		"applicant": {"credit_score": 780, "annual_income": 120000, "employment_status": "employed", "existing_monthly_debt": 500},
		"loan": {"amount": 100000, "term_months": 120},
	}
	d.outcome == "invalid"
	d.reasons["applicant.age missing or not a number"]
}

# A zero term must not raise a divide-by-zero; it is caught as invalid.
test_zero_term_months_is_invalid if {
	d := credit.decision with input as {
		"applicant": {"age": 40, "credit_score": 780, "annual_income": 120000, "employment_status": "employed", "existing_monthly_debt": 500},
		"loan": {"amount": 100000, "term_months": 0},
	}
	d.outcome == "invalid"
	d.reasons["loan.term_months missing or not a positive number"]
}

# A wrong-typed field (string income) is invalid, not a numeric comparison.
test_non_numeric_income_is_invalid if {
	d := credit.decision with input as {
		"applicant": {"age": 40, "credit_score": 780, "annual_income": "lots", "employment_status": "employed", "existing_monthly_debt": 500},
		"loan": {"amount": 100000, "term_months": 120},
	}
	d.outcome == "invalid"
	d.reasons["applicant.annual_income missing or not a number"]
}

# An empty payload surfaces every missing field at once and never errors.
test_empty_input_is_invalid if {
	d := credit.decision with input as {}
	d.outcome == "invalid"
	count(d.reasons) == 7
}
