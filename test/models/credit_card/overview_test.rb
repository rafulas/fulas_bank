require "test_helper"

class CreditCard::OverviewTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @bank = @family.accounts.create!(name: "Banco resumen", balance: 5_000, currency: "EUR", accountable: Depository.new)
    @card = @family.accounts.create!(name: "Tarjeta resumen", balance: 600, currency: "EUR",
                                     accountable: CreditCard.new(statement_closing_day: 31, payment_day: 5, payment_account: @bank,
                                                                 available_credit: 3_000, annual_fee: 30))
    @today = Date.new(2026, 12, 10)
  end

  test "how much of the limit is used" do
    overview = overview_for(@card)

    assert_equal 20, overview.usage
    assert_equal 2_400, overview.available
  end

  test "without a limit it only shows what is owed" do
    @card.accountable.update!(available_credit: nil)

    overview = overview_for(@card.reload)

    assert_not overview.limit?
    assert_nil overview.usage
    assert_equal 600, overview.owed
  end

  test "the purchases paid in instalments: what is pending, the next one and what deferring cost" do
    purchase = @card.entries.create!(name: "Sofá", date: Date.new(2026, 11, 10), amount: 100, currency: "EUR", entryable: Transaction.new)
    CardFinancing.from_entry(purchase).update!(installments_count: 4, installment_amount: 26, fee_amount: 2)

    overview = overview_for(@card)

    assert_equal 104, overview.pending_financed
    assert_equal [ Date.new(2027, 1, 5), 26 ], overview.next_installment
    assert_equal 6, overview.financing_cost_this_year
    assert_equal 30, overview.annual_fee
  end

  private
    def overview_for(account)
      CreditCard::Overview.new(account, cycle: CreditCard::Cycle.new(account, today: @today))
    end
end
