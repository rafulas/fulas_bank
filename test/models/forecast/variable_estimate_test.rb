require "test_helper"

class Forecast::VariableEstimateTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @today = Date.new(2026, 10, 14)
    @account = Account.create!(family: @family, owner: users(:family_admin), name: "Estimate checking", balance: 1_000,
                               currency: "USD", accountable: Depository.new, status: "active")
  end

  test "averages the last three Octobers and the last six months, without the highest and the lowest" do
    spend(100, Date.new(2023, 10, 5))
    spend(200, Date.new(2024, 10, 5))
    spend(900, Date.new(2025, 10, 5))
    [ 4, 5, 6, 7, 8 ].each { |month| spend(300, Date.new(2026, month, 10)) }
    spend(50, Date.new(2026, 9, 10))

    # 50, 100, 200, 300 x5, 900 -> without 50 and 900: (100 + 200 + 300 x5) / 7
    assert_equal BigDecimal("257.14"), estimate.monthly(@account, Date.new(2026, 10, 1))
  end

  test "a month further ahead uses the last three of that month that have already finished" do
    assert_equal [ Date.new(2025, 11, 1), Date.new(2024, 11, 1), Date.new(2023, 11, 1) ],
                 estimate.sample_months(Date.new(2027, 11, 1)).first(3)
    assert_equal Date.new(2026, 4, 1), estimate.sample_months(Date.new(2027, 11, 1)).last
  end

  test "uses only the months with history, and older months once they are imported" do
    spend(400, Date.new(2026, 8, 3))
    spend(200, Date.new(2026, 9, 3))

    assert_equal BigDecimal("300"), estimate.monthly(@account, Date.new(2026, 10, 1))

    spend(1_000, Date.new(2025, 10, 3))

    # Oct 2025 now counts, and so do the empty months since then:
    # 0, 0, 0, 0, 200, 400, 1000 -> without one 0 and 1000 -> 600 / 5
    assert_equal BigDecimal("120"), estimate.monthly(@account, Date.new(2026, 10, 1))
  end

  test "counts only variable spending" do
    spend(100, Date.new(2026, 9, 2))
    spend(70, Date.new(2026, 9, 3), expense_type: "variable")
    spend(500, Date.new(2026, 9, 4), expense_type: "fixed")
    spend(50, Date.new(2026, 9, 5), expense_type: "recurring")
    spend(-2_000, Date.new(2026, 9, 6))
    spend(300, Date.new(2026, 9, 7), kind: "funds_movement")
    spend(900, Date.new(2026, 9, 8), kind: "one_time")
    paid_bill = spend(80, Date.new(2026, 9, 9))
    pay_with(paid_bill)

    assert_equal BigDecimal("170"), estimate.monthly(@account, Date.new(2026, 10, 1))
    assert_equal BigDecimal("170"), estimate.spent(@account, Date.new(2026, 9, 1))
  end

  test "money put into investments is not variable spending" do
    root = @family.categories.find_by(name: "Inversiones", parent_id: nil) ||
           @family.categories.create!(name: "Inversiones", color: "#a448d8")
    funds = @family.categories.find_by(name: "Inversiones financieras") ||
            @family.categories.create!(name: "Inversiones financieras", color: "#a448d8", parent: root)
    pension = @family.categories.create!(name: "Plan pensiones prueba", color: "#a448d8", parent: root)

    spend(100, Date.new(2026, 9, 2))
    spend(280, Date.new(2026, 9, 3), category: funds)
    spend(500, Date.new(2026, 9, 4), category: pension)

    assert_equal BigDecimal("100"), estimate.monthly(@account, Date.new(2026, 10, 1))
  end

  test "all accounts together leave out months with no spending at all" do
    # An old movement that is not variable spending makes the account look
    # covered from 2024, but those months have no data.
    spend(-50, Date.new(2024, 3, 1))
    spend(400, Date.new(2026, 8, 3))
    spend(200, Date.new(2026, 9, 3))

    assert_equal [ Date.new(2026, 9, 1), Date.new(2026, 8, 1) ], estimate.combined_sample_months(Date.new(2026, 11, 1))
    assert_equal BigDecimal("300"), estimate.combined_monthly(Date.new(2026, 11, 1))
  end

  test "a category left out of the forecast does not count in any month" do
    renovation = @family.categories.create!(name: "Reforma prueba", color: "#000000")
    spend(100, Date.new(2026, 9, 2))
    spend(3_000, Date.new(2026, 9, 3), category: renovation)

    plan = Forecast::VariablePlan.new(@family, user: users(:family_admin), today: @today)
    plan.exclude!(renovation.id)

    estimate = Forecast::VariableEstimate.new(@family, accounts: [ @account ], today: @today, plan: plan)
    assert_equal BigDecimal("100"), estimate.combined_monthly(Date.new(2026, 11, 1))
  end

  test "a category planned for a month replaces its average that month only" do
    leisure = @family.categories.create!(name: "Ocio prueba", color: "#000000")
    trips = @family.categories.create!(name: "Viajes prueba", color: "#000000", parent: leisure)
    [ 8, 9 ].each do |month|
      spend(200, Date.new(2026, month, 2))
      spend(600, Date.new(2026, month, 3), category: trips)
    end

    plan = Forecast::VariablePlan.new(@family, user: users(:family_admin), today: @today)
    plan.plan!(Date.new(2026, 11, 1), leisure.id, 0)

    estimate = Forecast::VariableEstimate.new(@family, accounts: [ @account ], today: @today, plan: plan)
    assert_equal BigDecimal("200"), estimate.combined_monthly(Date.new(2026, 11, 1)), "a parent's plan covers its subcategories"
    assert_equal BigDecimal("800"), estimate.combined_monthly(Date.new(2026, 12, 1)), "other months keep the average"

    plan.plan!(Date.new(2026, 11, 1), leisure.id, 150)
    assert_equal BigDecimal("350"),
                 Forecast::VariableEstimate.new(@family, accounts: [ @account ], today: @today, plan: plan).combined_monthly(Date.new(2026, 11, 1))
  end

  test "a movement of a recurring series marked variable counts" do
    bill = spend(80, Date.new(2026, 9, 9), expense_type: "variable")
    pay_with(bill)

    assert_equal BigDecimal("80"), estimate.monthly(@account, Date.new(2026, 10, 1))
  end

  test "no history, no estimate" do
    assert_equal 0, estimate.monthly(@account, Date.new(2026, 10, 1))
  end

  private
    def estimate
      Forecast::VariableEstimate.new(@family, accounts: [ @account ], today: @today)
    end

    def spend(amount, date, **attributes)
      create_transaction(account: @account, name: "Gasto", amount: amount, date: date, **attributes)
    end

    def pay_with(entry)
      series = recurring_transactions(:netflix_subscription)
      occurrence = series.recurring_occurrences.create!(family: @family, original_due_on: entry.date, due_on: entry.date, currency: "USD")
      occurrence.allocations.create!(entry: entry, allocated_amount: entry.amount, currency: "USD", source: "user_created")
    end
end
