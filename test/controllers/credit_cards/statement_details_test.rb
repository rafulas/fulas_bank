require "test_helper"

# Fulas Bank: a card statement's movements and a financed purchase's charges,
# opened from the card's statement tab.
class CreditCards::StatementDetailsTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @card = accounts(:credit_card)
    @bank = accounts(:depository)
    @card.credit_card.update!(statement_closing_day: 31, payment_day: 5, payment_account: @bank)
    @month = Date.current.beginning_of_month.prev_month
    @purchase = create_transaction(account: @card, name: "Gasolinera Repsol", amount: 60, date: @month + 9)
    @revision = create_transaction(account: @card, name: "Revisión moto", amount: 300, date: @month + 3)
    @financing = CardFinancing.from_entry(@revision)
    @financing.update!(installments_count: 3, installment_amount: 101, fee_amount: 1.5)
  end

  test "the statement tab links each period and each financed purchase" do
    get account_url(@card, tab: "card_statement")

    assert_response :success
    assert_select "a[href=?]", credit_card_statement_path(@card, @month.strftime("%Y-%m"))
    assert_select "a[href=?]", credit_card_financing_path(@card, @financing)
  end

  test "a statement lists the movements it is made of" do
    get credit_card_statement_url(@card, @month.strftime("%Y-%m"))

    assert_response :success
    assert_select "a[href=?]", entry_path(@purchase), text: "Gasolinera Repsol"
    assert_select "a[href=?]", entry_path(@revision), text: "Revisión moto"
    assert_select "a[href=?]", credit_card_financing_path(@card, @financing)
  end

  test "a financed purchase lists its fee and instalments, with the bank's charge once imported" do
    cycle = CreditCard::Cycle.new(@card)
    fee_day = @financing.charges(cycle).first.date
    charge = create_transaction(account: @bank, name: "OPERACION FINANCIADA CON TARJETA", amount: 1.5, date: fee_day) if fee_day <= Date.current

    get credit_card_financing_url(@card, @financing)

    assert_response :success
    assert_select "a[href=?]", entry_path(@revision)
    assert_match "Instalment 3 of 3", response.body
    assert_select "a[href=?]", entry_path(charge) if charge
  end

  test "another family's card is not found" do
    other = families(:empty).accounts.create!(name: "Ajena", balance: 0, currency: "EUR",
                                              accountable: CreditCard.new(statement_closing_day: 31, payment_day: 5))

    get credit_card_statement_url(other, @month.strftime("%Y-%m"))
    assert_response :not_found
  end
end
