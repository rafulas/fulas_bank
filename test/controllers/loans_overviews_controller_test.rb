require "test_helper"

class LoansOverviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "Fulas Bank: paid-off loans are listed apart, under Pagados" do
    paid = @user.family.accounts.create!(name: "Préstamo Boda pagado", balance: 0, currency: "USD", owner: @user,
                                         accountable: Loan.new(initial_balance: 26_800, interest_rate: 0, term_months: 84,
                                                               rate_type: "fixed", payment_amount: 303.57))

    get loans_overview_url

    assert_response :success
    assert_select "details", text: /#{paid.name}/
  end
end
