require "test_helper"

class Loan::PayrollDeductionTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @reforma = @family.categories.create!(name: "Reformas y construcción")
    @nomina = @family.categories.create!(name: "Nómina")
    @loan_account = @family.accounts.create!(
      name: "Préstamo Reforma", balance: 25_000, currency: "USD",
      accountable: Loan.new(initial_balance: 30_000, interest_rate: 2, rate_type: "fixed", term_months: 120,
                            start_date: Date.current - 2.years, payment_day: 19)
    )
    @loan = @loan_account.loan
    @fake = @family.accounts.create!(name: "Cuenta Fake", balance: 0, currency: "USD", accountable: Depository.new)
  end

  test "switching it on starts today and needs the category of the instalment" do
    @loan.payroll_deducted = true
    assert_not @loan.valid?

    @loan.update!(payroll_deducted: true, payroll_expense_category: @reforma, payroll_income_category: @nomina)
    assert_equal Date.current, @loan.payroll_deducted_since
  end

  test "each month's pay and instalment are booked in the loan once, and the instalment is its payment" do
    @loan.update!(payroll_deducted: true, payroll_expense_category: @reforma, payroll_income_category: @nomina)
    @loan.update_columns(payroll_deducted_since: (Date.current << 3).beginning_of_month)
    deduction = Loan::PayrollDeduction.new(@loan.reload)
    months = deduction.due_dates.size
    assert_operator months, :>=, 3

    booked = deduction.book_due!

    # (Saving the loan may already have booked today's, if today is the 19th.)
    assert_equal months, @loan.payment_links.count
    pair = booked.first
    assert_equal @loan_account, pair.expense.account
    assert_equal @reforma, pair.expense.entryable.category
    assert_equal @nomina, pair.income.entryable.category
    assert_equal(-pair.expense.amount, pair.income.amount)
    assert_equal deduction.instalment_on(pair.date), pair.expense.amount

    assert_empty Loan::PayrollDeduction.new(@loan.reload).book_due!, "a month is booked once"
  end

  test "the months booked in another account are found as pairs and moved into the loan" do
    @loan.update!(payroll_deducted: true, payroll_expense_category: @reforma, payroll_income_category: @nomina)
    deduction = Loan::PayrollDeduction.new(@loan.reload)
    dates = [ (Date.current << 2).change(day: 19), (Date.current << 1).change(day: 19) ]
    dates.each do |date|
      amount = deduction.instalment_on(date)
      @fake.entries.create!(name: "Préstamo RRHH Reforma", date: date, amount: -amount, currency: "USD", entryable: Transaction.new(category: @nomina))
      @fake.entries.create!(name: "Préstamo RRHH Reforma", date: date, amount: amount, currency: "USD", entryable: Transaction.new(category: @reforma))
    end
    # A charge of the same amount with no pay beside it is not one of them.
    @fake.entries.create!(name: "Otra cosa", date: dates.first + 2, amount: deduction.instalment_on(dates.first), currency: "USD", entryable: Transaction.new)

    pairs = deduction.pairs_elsewhere(since: dates.first.beginning_of_month)
    assert_equal dates, pairs.map(&:date)

    assert_equal 2, deduction.move!(pairs)

    assert_equal 4, @loan_account.entries.where(entryable_type: "Transaction", date: dates).count
    assert_equal 1, @fake.entries.where(entryable_type: "Transaction").count, "only the unrelated charge stays"
    assert_equal 2, @loan.payment_links.joins(:entry).where(entries: { date: dates }).count
    assert_empty Loan::PayrollDeduction.new(@loan.reload).pairs_elsewhere(since: dates.first.beginning_of_month)
  end
end
