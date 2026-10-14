require "test_helper"

class InvestmentFundsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:investment)
  end

  test "adds, edits and deletes a fund" do
    get new_investment_fund_url
    assert_response :success

    assert_difference -> { @user.family.investment_funds.count } => 1 do
      post investment_funds_url, params: { investment_fund: {
        account_id: @account.id, name: "Indexado mundial", isin: " ie00b03hcz61 ", units: "150.25", price: "20.5", price_date: Date.current.iso8601, cost: "2500"
      } }
    end
    assert_redirected_to investments_overview_url

    fund = @user.family.investment_funds.last
    assert_equal "IE00B03HCZ61", fund.isin
    assert_equal 1, fund.prices.count

    get edit_investment_fund_url(fund)
    assert_response :success

    patch investment_fund_url(fund), params: { investment_fund: { units: "200" } }
    assert_equal BigDecimal("200"), fund.reload.units

    assert_difference -> { @user.family.investment_funds.count } => -1 do
      delete investment_fund_url(fund)
    end
  end

  test "rejects an account that is not one of the user's investments" do
    assert_no_difference -> { InvestmentFund.count } do
      post investment_funds_url, params: { investment_fund: { account_id: accounts(:depository).id, name: "Mal", units: "1" } }
    end

    assert_response :unprocessable_entity
  end

  test "updates the prices of several funds at once" do
    one = @user.family.investment_funds.create!(account: @account, name: "Uno", units: 10, price: 5, price_date: Date.current - 10)
    two = @user.family.investment_funds.create!(account: @account, name: "Dos", units: 10, price: 7, price_date: Date.current - 10)

    get edit_investment_fund_prices_url
    assert_response :success
    assert_select "input[name='prices[#{one.id}]']"

    patch investment_fund_prices_url, params: { date: Date.current.iso8601, prices: { one.id => "5,5", two.id => "" } }

    assert_redirected_to investments_overview_url
    assert_equal [ BigDecimal("5.5"), Date.current ], [ one.reload.price, one.price_date ]
    assert_equal BigDecimal("7"), two.reload.price
  end

  test "the investments page lists the funds" do
    @user.family.investment_funds.create!(account: @account, name: "Fondo de la casa", units: 10, price: 5, price_date: Date.current)

    get investments_overview_url

    assert_response :success
    assert_match "Fondo de la casa", response.body
    assert_select "a[href='#{edit_investment_fund_prices_path}']"
  end
end
