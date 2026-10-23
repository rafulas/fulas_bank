require "test_helper"

class RecurringOverviewTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @user = users(:empty)
    @checking = @family.accounts.create!(name: "Nómina", owner: @user, balance: 3_000, currency: "USD", accountable: Depository.new)
    @broker = @family.accounts.create!(name: "Indexa", owner: @user, balance: 10_000, currency: "USD", accountable: Investment.new)
    @card = @family.accounts.create!(name: "Tarjeta", owner: @user, balance: 0, currency: "USD", accountable: CreditCard.new)
  end

  # Fulas Bank: fixed (the mortgage, loans, the salary, transfers), bills
  # and subscriptions (see RecurringTransaction::Kind).
  test "each recurring movement goes to its tab" do
    series("Luz", 60, bill_type: "bill")
    series("Netflix", 13, bill_type: "subscription")
    series("Nómina", -2_400, bill_type: "income")
    series("Hipoteca", 900, bill_type: "installment")
    series("Aportación Indexa", 300, destination: @broker)
    series("Pago tarjeta", 500, destination: @card)

    overview = RecurringOverview.new(@family, user: @user)

    assert_equal [ "Luz" ], overview.rows_for("bills").map(&:name)
    assert_equal [ "Netflix" ], overview.rows_for("subscriptions").map(&:name)
    assert_equal [ "Aportación Indexa", "Hipoteca", "Nómina", "Pago tarjeta" ], overview.rows_for("fixed").map(&:name).sort
    assert_equal 6, overview.count("all")
  end

  test "monthly totals by kind, the fixed income apart" do
    series("Luz", 60, bill_type: "bill")
    series("Netflix", 13, bill_type: "subscription")
    series("Nómina", -2_400, bill_type: "income")
    series("Aportación Indexa", 300, destination: @broker)

    overview = RecurringOverview.new(@family, user: @user)

    assert_equal Money.new(300, "USD"), overview.monthly_total("fixed")
    assert_equal Money.new(2_400, "USD"), overview.monthly_income
    assert_equal Money.new(373, "USD"), overview.fixed_costs
  end

  test "lists the bills and subscriptions switched off, to switch them on again" do
    old_insurance = series("Seguro antiguo", 30, bill_type: "bill")
    old_insurance.update!(status: "inactive", cancelled_on: Date.current)
    series("Préstamo", 200, bill_type: "installment").update!(status: "inactive")

    overview = RecurringOverview.new(@family, user: @user)

    assert_equal [ old_insurance ], overview.switched_off
    assert_empty overview.switched_off("subscriptions")
    assert_empty overview.rows_for("bills")
  end

  test "a recent price rise shows the price before" do
    gym = series("Gimnasio", 45, bill_type: "bill")
    gym.recurring_price_changes.create!(effective_on: 1.month.ago.to_date, previous_amount: 40, new_amount: 45, currency: "USD", source: "detected")

    row = RecurringOverview.new(@family, user: @user).rows.first

    assert row.price_up?
    assert_equal 40, row.price_change.previous_amount
  end

  private
    def series(name, amount, bill_type: nil, destination: nil)
      @family.recurring_transactions.create!(
        account: @checking, destination_account: destination, name: name, amount: amount, currency: "USD",
        expected_day_of_month: 10, status: "active", manual: true, bill_type: bill_type || "bill", dedup_scope: name,
        last_occurrence_date: Date.current.prev_month, next_expected_date: Date.current.next_month
      )
    end
end
