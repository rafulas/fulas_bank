require "test_helper"

class Transactions::CardFinancingsControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @card = accounts(:credit_card)
    @card.credit_card.update!(statement_closing_day: 31, payment_day: 5, payment_account: accounts(:depository))
    @purchase = create_transaction(account: @card, name: "Revisión moto", amount: 345.67, date: Date.current.beginning_of_month)
  end

  test "a card purchase shows its statement and can be paid in instalments" do
    get transaction_url(@purchase)
    assert_response :success
    assert_select "a[href=?]", new_transaction_card_financing_path(@purchase)

    assert_difference -> { CardFinancing.count }, 1 do
      post transaction_card_financing_url(@purchase), params: {
        card_financing: { financed_amount: "345.67", installments_count: "9", installment_amount: "39.50", fee_amount: "2.50" }
      }
    end

    financing = CardFinancing.last
    assert_equal @purchase, financing.entry
    assert_equal 9, financing.installments_count

    get account_url(@card)
    assert_response :success
    assert_match "Revisión moto", response.body
    assert_match I18n.t("credit_cards.tabs.statement.financed_title"), response.body
  end

  test "moves a purchase to the next statement" do
    patch transaction_card_statement_url(@purchase), params: { card_statement: { next_card_statement: "1" } }

    assert @purchase.transaction.reload.next_card_statement
  end

  test "only card purchases can be financed" do
    post transaction_card_financing_url(entries(:transaction)), params: {
      card_financing: { financed_amount: "10", installments_count: "2", installment_amount: "5" }
    }

    assert_response :unprocessable_entity
  end
end
