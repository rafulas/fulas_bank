require "test_helper"

class Loan::AmortizationScheduleTest < ActiveSupport::TestCase
  # A loan paid "on the 30th" is paid on the 30th of every month, or on the
  # month's last day when it is shorter. The first payment still falls in the
  # month after origination, so the term keeps its number of payments.
  test "a payment day moves each payment to that day of its month" do
    schedule = Loan::AmortizationSchedule.new(
      principal: 3_000, annual_rate: 0, term_months: 3,
      start_date: Date.new(2026, 1, 15), currency: "EUR", payment_day: 30
    )

    assert_equal [ Date.new(2026, 2, 28), Date.new(2026, 3, 30), Date.new(2026, 4, 30) ],
                 schedule.payments.map(&:date)
  end

  # The instalment the lender quotes is held as given rather than re-derived.
  # 1,000 at 12% (1% a month) over 12 months levels at 88.85; a quoted 100
  # clears it sooner, and the last payment settles what is left.
  test "a quoted fixed payment is held as given" do
    schedule = Loan::AmortizationSchedule.new(
      principal: 1_000, annual_rate: 12, term_months: 12,
      start_date: Date.new(2026, 1, 1), currency: "EUR", fixed_payment: 100
    )

    assert_equal BigDecimal("100"), schedule.periodic_payment.amount
    assert schedule.payments[0...-1].all? { |payment| payment.payment.amount == BigDecimal("100") }
    assert_operator schedule.payments.size, :<, 12
    assert_equal BigDecimal("0"), schedule.payments.last.ending_balance.amount
  end

  # A variable loan's quoted instalment is what the borrower pays under the
  # rate in force now. It applies from the latest change on or before today;
  # before that the schedule sizes its own payment as usual.
  test "a variable loan's quoted payment applies to the rate period in force today" do
    travel_to Date.new(2026, 6, 15) do
      account = Account.create!(
        family: families(:dylan_family), name: "Variable #{SecureRandom.hex(3)}", balance: 15_000, currency: "EUR",
        accountable: Loan.create!(
          rate_type: "variable", interest_rate: 5, term_months: 24, initial_balance: 20_000,
          start_date: Date.new(2025, 1, 1), variable_rate_schedule: { "2026-01-01" => "6" },
          payment_amount: 600
        )
      )
      payments = account.loan.amortization_schedule.payments

      assert payments.select { |payment| payment.date.year == 2026 }.all? { |payment| payment.payment.amount == BigDecimal("600") },
             "the quoted instalment, under today's rate"
      assert payments.select { |payment| payment.date.year == 2025 }.none? { |payment| payment.payment.amount == BigDecimal("600") },
             "a payment sized at the opening rate before it"
    end
  end

  test "builds one payment per month of the term" do
    schedule = build_schedule

    assert_equal 360, schedule.payments.count
    assert_equal 1, schedule.payments.first.number
    assert_equal 360, schedule.payments.last.number
  end

  test "level payment matches the standard amortization formula" do
    assert_equal BigDecimal("2245.22"), build_schedule.periodic_payment.amount
  end

  test "first payment is mostly interest and last payment is mostly principal" do
    schedule = build_schedule
    first = schedule.payments.first
    last = schedule.payments.last

    # 500,000 at 3.5% => 1,458.33 of interest in month one.
    assert_equal BigDecimal("1458.33"), first.interest.amount
    assert_equal BigDecimal("786.89"), first.principal.amount
    assert first.interest.amount > first.principal.amount
    assert last.principal.amount > last.interest.amount
  end

  test "amortizes down to exactly zero" do
    assert_equal BigDecimal("0"), build_schedule.payments.last.ending_balance.amount
  end

  test "principal portions sum to the original principal" do
    schedule = build_schedule
    total_principal = schedule.payments.sum(BigDecimal(0)) { |payment| payment.principal.amount }

    assert_equal BigDecimal("500000"), total_principal
  end

  test "total paid is principal plus total interest" do
    schedule = build_schedule

    # Slightly above the naive payment*term figure because interest is rounded
    # to cents every month, exactly as a lender's table does.
    assert_equal BigDecimal("308281.36"), schedule.total_interest.amount
    assert_equal schedule.principal + schedule.total_interest.amount, schedule.total_paid.amount
  end

  test "payment dates step monthly from origination" do
    schedule = build_schedule(start_date: Date.new(2026, 1, 31))

    assert_equal Date.new(2026, 2, 28), schedule.payments.first.date
    assert_equal Date.new(2026, 3, 31), schedule.payments.second.date
  end

  test "payoff date is the last payment date" do
    schedule = build_schedule(start_date: Date.new(2026, 1, 1), term_months: 12)

    assert_equal Date.new(2027, 1, 1), schedule.payoff_date
  end

  test "handles a zero-interest loan with straight-line principal" do
    schedule = build_schedule(annual_rate: 0, term_months: 10, principal: 1000)

    assert_equal BigDecimal("100"), schedule.periodic_payment.amount
    assert schedule.payments.all? { |payment| payment.interest.amount.zero? }
    assert_equal BigDecimal("0"), schedule.total_interest.amount
    assert_equal BigDecimal("0"), schedule.payments.last.ending_balance.amount
  end

  test "rounds to whole units for a currency without minor units" do
    schedule = build_schedule(currency: "JPY", principal: 1_000_000, annual_rate: 2, term_months: 12)

    assert schedule.payments.all? { |payment| payment.payment.amount.frac.zero? }
    assert_equal BigDecimal("0"), schedule.payments.last.ending_balance.amount
  end

  test "returns no payments when the term is zero" do
    assert_empty build_schedule(term_months: 0).payments
    assert_nil build_schedule(term_months: 0).payoff_date
    assert_equal BigDecimal("0"), build_schedule(term_months: 0).periodic_payment.amount
    assert_equal BigDecimal("0"), build_schedule(principal: 0).periodic_payment.amount
  end

  test "keeps the periods it built when rounding clears the balance early" do
    # 10 over 51 months rounds to a 0.20 payment, which pays the loan off in 50.
    schedule = build_schedule(principal: 10, annual_rate: 0, term_months: 51)

    assert_equal 50, schedule.payments.count
    assert_equal BigDecimal("0"), schedule.payments.last.ending_balance.amount
    assert_equal BigDecimal("10"), schedule.total_paid.amount
    assert_equal schedule.payments.last.date, schedule.payoff_date
  end

  test "payment_for finds the payment landing in a given month" do
    schedule = build_schedule(start_date: Date.new(2026, 1, 1), term_months: 12)

    assert_equal 3, schedule.payment_for(Date.new(2026, 4, 17)).number
    assert_nil schedule.payment_for(Date.new(2030, 1, 1))
  end

  test "builds from a loan record" do
    loan = loan_account(interest_rate: 3.5, term_months: 360, rate_type: "fixed").loan

    assert_equal BigDecimal("2245.22"), Loan::AmortizationSchedule.for(loan).periodic_payment.amount
  end

  # Reversed by #104. A variable loan was excluded while a schedule could only
  # be built off one rate; it now re-amortises at each recorded change, so the
  # reason for the exclusion is gone.
  test "is buildable for a variable rate loan" do
    loan = loan_account(interest_rate: 3.5, term_months: 360, rate_type: "variable").loan

    assert_not_nil Loan::AmortizationSchedule.for(loan)
  end

  # A rate type outside the form's vocabulary is still a rate type (#100
  # decision 8). PlaidAccount::Liabilities::MortgageProcessor writes Plaid's
  # raw `interest_rate.type` straight through, so this is reachable from a
  # sync, not only from the form, and such a loan is variable rather than
  # unknown.
  test "is buildable for a provider's own rate type" do
    loan = loan_account(interest_rate: 3.5, term_months: 360, rate_type: "teaser").loan

    assert_not_nil Loan::AmortizationSchedule.for(loan)
  end

  # What is still not buildable: no rate type at all.
  test "is not buildable for a blank rate type" do
    loan = loan_account(interest_rate: 3.5, term_months: 360, rate_type: "").loan

    assert_nil Loan::AmortizationSchedule.for(loan)
  end

  private
    def build_schedule(principal: 500_000, annual_rate: 3.5, term_months: 360,
                       start_date: Date.new(2026, 1, 1), currency: "USD")
      Loan::AmortizationSchedule.new(
        principal: principal,
        annual_rate: annual_rate,
        term_months: term_months,
        start_date: start_date,
        currency: currency
      )
    end

    def loan_account(**loan_attrs)
      Account.create! \
        family: families(:dylan_family),
        name: "Mortgage Loan",
        balance: 500_000,
        currency: "USD",
        accountable: Loan.create!(subtype: "mortgage", **loan_attrs)
    end
end
