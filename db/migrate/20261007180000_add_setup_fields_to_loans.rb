class AddSetupFieldsToLoans < ActiveRecord::Migration[8.1]
  def up
    # A premium quoted as a fixed yearly amount rather than a rate.
    add_column :loans, :insurance_annual_amount, :decimal, precision: 19, scale: 4
    add_check_constraint :loans,
      "insurance_annual_amount IS NULL OR insurance_annual_amount >= 0",
      name: "chk_loans_insurance_annual_amount_non_negative"

    remove_check_constraint :loans, name: "chk_loans_insurance_rate_type"
    add_check_constraint :loans,
      "insurance_rate_type IS NULL OR insurance_rate_type IN ('level_term', 'decreasing_life', 'fixed_amount')",
      name: "chk_loans_insurance_rate_type"

    # The contracted instalment, for a fixed-rate loan whose lender quotes it.
    add_column :loans, :payment_amount, :decimal, precision: 19, scale: 4
    add_check_constraint :loans,
      "payment_amount IS NULL OR payment_amount > 0",
      name: "chk_loans_payment_amount_positive"

    # Day of the month the instalment is charged.
    add_column :loans, :payment_day, :integer
    add_check_constraint :loans,
      "payment_day IS NULL OR (payment_day BETWEEN 1 AND 31)",
      name: "chk_loans_payment_day_range"

    # The asset the loan paid for: the car behind a car loan, the home behind
    # a mortgage.
    add_reference :loans, :asset_account, type: :uuid, null: true,
      foreign_key: { to_table: :accounts, on_delete: :nullify }
  end

  def down
    remove_reference :loans, :asset_account, foreign_key: { to_table: :accounts }
    remove_check_constraint :loans, name: "chk_loans_payment_day_range"
    remove_column :loans, :payment_day
    remove_check_constraint :loans, name: "chk_loans_payment_amount_positive"
    remove_column :loans, :payment_amount

    remove_check_constraint :loans, name: "chk_loans_insurance_rate_type"
    execute "UPDATE loans SET insurance_rate_type = NULL WHERE insurance_rate_type = 'fixed_amount'"
    add_check_constraint :loans,
      "insurance_rate_type IS NULL OR insurance_rate_type IN ('level_term', 'decreasing_life')",
      name: "chk_loans_insurance_rate_type"

    remove_check_constraint :loans, name: "chk_loans_insurance_annual_amount_non_negative"
    remove_column :loans, :insurance_annual_amount
  end
end
