require "test_helper"

class DebtPlansControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @loan = accounts(:loan)
    @loan.accountable.update!(payment_amount: 2_500)
  end

  test "shows the plan with each loan, the schedule and both views" do
    get debt_plan_url

    assert_response :success
    assert_select "#debt-plan-chart[data-controller='time-series-chart']"
    assert_select "input[name='debt_plan[loans][#{@loan.id}][order]']"
    assert_select "table", minimum: 3

    get debt_plan_url(view: "pending")
    assert_response :success
  end

  test "saves the strategy and the loans' settings" do
    series = @user.family.recurring_transactions.create!(
      account: accounts(:depository), name: "Hipoteca", amount: 2_500, currency: "USD", expected_day_of_month: 1,
      status: "active", manual: true, bill_type: "bill", last_occurrence_date: Date.current, next_expected_date: Date.current
    )

    patch debt_plan_url, params: { debt_plan: {
      strategy: "snowball", monthly_extra: "100", feeds_forecast: "1",
      loans: { @loan.id => { order: "1", payment: "", excluded: "0", recurring_transaction_id: series.id } }
    } }

    assert_redirected_to debt_plan_url
    plan = @user.family.reload.debt_plan
    assert_equal [ "snowball", BigDecimal("100"), true ], [ plan.strategy, plan.monthly_extra, plan.feeds_forecast ]
    assert_equal({ "order" => "1", "recurring_transaction_id" => series.id }, plan.loan_settings[@loan.id])
  end

  test "rejects an unknown strategy" do
    patch debt_plan_url, params: { debt_plan: { strategy: "lottery" } }

    assert_redirected_to debt_plan_url
    assert_nil @user.family.reload.debt_plan
  end

  test "adds and deletes an extra contribution" do
    assert_difference -> { DebtPlan::ExtraPayment.count } => 1 do
      post debt_plan_extra_payments_url, params: { debt_plan_extra_payment: { name: "Bonus", date: "2027-03-15", amount: "15000", repeats_until: "2028-12-31" } }
    end
    assert_redirected_to debt_plan_url

    payment = @user.family.debt_plan.extra_payments.sole
    assert_equal [ Date.new(2027, 3, 15), Date.new(2028, 3, 15) ], payment.dates

    assert_difference -> { DebtPlan::ExtraPayment.count } => -1 do
      delete debt_plan_extra_payment_url(payment)
    end
  end

  test "the forecast shows the plan's lines when it feeds it" do
    @user.family.create_debt_plan!(feeds_forecast: true)

    get forecast_url(period: "1y")

    assert_response :success
    assert_match @loan.name, response.body
  end

  test "puts the totals right after the month and opens the table in a wide dialog" do
    get debt_plan_url

    headers = css_select("table").last.css("thead th").map { |th| th.text.strip }
    assert_operator headers.index(I18n.t("debt_plans.show.total_payment")), :<, headers.index(@loan.name)
    assert_operator headers.index(I18n.t("debt_plans.show.total_balance")), :<, headers.index(@loan.name)
    assert_select "a[href='#{schedule_debt_plan_path(view: "payments")}']"

    get schedule_debt_plan_url(view: "pending")
    assert_response :success
    assert_select "dialog table"
  end
end
