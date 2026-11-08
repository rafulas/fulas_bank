require "test_helper"

class CardFinancingTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @bank = @family.accounts.create!(name: "Banco principal", balance: 5_000, currency: "EUR", accountable: Depository.new)
    @card = @family.accounts.create!(name: "Tarjeta principal", balance: 0, currency: "EUR",
                                     accountable: CreditCard.new(statement_closing_day: 31, payment_day: 5, payment_account: @bank))
    purchase = @card.entries.create!(name: "Compra", date: Date.new(2026, 11, 10), amount: 100, currency: "EUR", entryable: Transaction.new)
    @financing = CardFinancing.from_entry(purchase)
    @financing.update!(installments_count: 4, installment_amount: 25, fee_amount: 2)
  end

  # The 5th of December 2026 is a Saturday: the bank charges it the Friday before.
  test "the fee on the statement's charge day and each instalment on the next ones" do
    assert_equal [ [ Date.new(2026, 12, 4), 2, :fee ], [ Date.new(2027, 1, 5), 25, :installment ], [ Date.new(2027, 2, 5), 25, :installment ],
                   [ Date.new(2027, 3, 5), 25, :installment ], [ Date.new(2027, 4, 5), 25, :installment ] ],
                 @financing.charges.map { |charge| [ charge.date, charge.amount, charge.kind ] }
  end

  test "the fee and the first instalment can have their own day" do
    @financing.update!(fee_on: Date.new(2026, 11, 28), first_installment_on: Date.new(2026, 12, 15))

    assert_equal [ Date.new(2026, 11, 28), Date.new(2026, 12, 15), Date.new(2027, 1, 15), Date.new(2027, 2, 15), Date.new(2027, 3, 15) ],
                 @financing.charges.map(&:date)
  end

  test "paid off early, what was left is charged that day and no instalment after it" do
    @financing.update!(paid_off_on: Date.new(2027, 3, 5))

    charges = @financing.charges
    assert_equal [ Date.new(2026, 12, 4), Date.new(2027, 1, 5), Date.new(2027, 2, 5), Date.new(2027, 3, 5) ], charges.map(&:date)
    assert_equal :payoff, charges.last.kind
    assert_equal 50, charges.last.amount
    assert_equal 102, @financing.total_to_pay
    assert @financing.finished?(today: Date.new(2027, 3, 6))
    assert_equal 50, @financing.due_on(Date.new(2027, 3, 5))
  end

  test "paying off early takes the amount the bank charged, and undoing it forgets the amount" do
    @financing.update!(paid_off_on: Date.new(2027, 3, 5), payoff_amount: 48.5)
    assert_equal BigDecimal("48.5"), @financing.charges.last.amount

    @financing.update!(paid_off_on: nil)
    assert_nil @financing.reload.payoff_amount
    assert_equal 5, @financing.charges.size
  end

  test "the days cannot be before the purchase" do
    @financing.paid_off_on = Date.new(2026, 11, 1)
    assert_not @financing.valid?
  end
end
