require "test_helper"

class InvestmentsControllerTest < ActionDispatch::IntegrationTest
  include AccountableResourceInterfaceTest

  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:investment)
  end

  test "offers only the Spanish investment types" do
    get new_investment_url

    assert_response :success
    assert_select "select[name='account[accountable_attributes][subtype]'] option[value='stocks']"
    assert_select "select[name='account[accountable_attributes][subtype]'] option[value='401k']", count: 0
    assert_select "input[name='account[balance]'][required]", count: 0
  end

  test "opens an investment without a balance, to record purchases one by one" do
    assert_difference -> { Account.count } => 1 do
      post investments_url, params: { account: {
        name: "Acciones BBVA", balance: "", currency: "EUR", accountable_type: "Investment",
        accountable_attributes: { subtype: "stocks" }
      } }
    end

    account = Account.order(:created_at).last
    assert_equal BigDecimal("0"), account.balance
    assert_equal "stocks", account.accountable.subtype
    assert_equal 0, account.entries.where(entryable_type: "Valuation").count
  end
end
