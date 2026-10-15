require "test_helper"

class CreditCard::CycleTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @bank = @family.accounts.create!(name: "BBVA Rafa", balance: 5_000, currency: "EUR", accountable: Depository.new)
    @card = @family.accounts.create!(name: "Tarjeta BBVA Rafa", balance: 0, currency: "EUR",
                                     accountable: CreditCard.new(statement_closing_day: 31, payment_day: 5, payment_account: @bank))
  end

  test "a month's purchases are charged on the 5th, or the working day before" do
    spend(345.67, Date.new(2026, 8, 12))
    spend(1_000, Date.new(2026, 8, 20))

    statement = cycle.statement(Date.new(2026, 8, 1))

    assert_equal Date.new(2026, 8, 31), statement.closes_on
    assert_equal Date.new(2026, 8, 1), statement.opens_on
    # Saturday 5 September 2026 -> Friday the 4th.
    assert_equal Date.new(2026, 9, 4), statement.charged_on
    assert_equal BigDecimal("1345.67"), statement.amount
  end

  test "a purchase on a weekend at the end of the month goes to the next statement, and so can any by hand" do
    weekend = spend(50, Date.new(2026, 10, 31)) # Saturday
    late = spend(20, Date.new(2026, 10, 28))
    late.entryable.update!(next_card_statement: true)

    assert_equal 0, cycle.statement(Date.new(2026, 10, 1)).amount
    assert_equal [ late, weekend ].map(&:id).sort, cycle.statement(Date.new(2026, 11, 1)).entries.map(&:id).sort
  end

  test "consolidation days move late purchases to the next statement" do
    @card.credit_card.update!(consolidation_days: 2)
    spend(30, Date.new(2026, 10, 29)) # Thursday: booked Monday 2 November

    assert_equal BigDecimal("30"), cycle.statement(Date.new(2026, 11, 1)).amount
  end

  test "a purchase paid in instalments leaves the statement, and is charged apart" do
    purchase = spend(345.67, Date.new(2026, 9, 12))
    spend(1_000, Date.new(2026, 9, 20))
    financing = CardFinancing.from_entry(purchase)
    financing.update!(installments_count: 9, installment_amount: 39.5, fee_amount: 2.5)

    assert_equal BigDecimal("1000"), cycle.statement(Date.new(2026, 9, 1)).amount

    charges = financing.charges(cycle)
    assert_equal [ Date.new(2026, 10, 5), BigDecimal("2.5"), :fee ], [ charges.first.date, charges.first.amount, charges.first.kind ]
    assert_equal Date.new(2026, 11, 5), charges.second.date
    assert_equal Date.new(2027, 7, 5), charges.last.date
    assert_equal 10, charges.size
    assert_not financing.mismatch?
    assert_equal BigDecimal("12.33"), financing.cost.round(2)
  end

  test "flags instalments that do not cover the purchase" do
    purchase = spend(345.67, Date.new(2026, 9, 12))
    financing = CardFinancing.from_entry(purchase)
    financing.assign_attributes(installments_count: 9, installment_amount: 35.58)

    assert financing.mismatch?
  end

  test "the forecast charges the open statement and the instalments in the payment account" do
    today = Date.new(2026, 10, 15)
    spend(200, Date.new(2026, 10, 3))
    purchase = spend(345.67, Date.new(2026, 9, 12))
    CardFinancing.from_entry(purchase).update!(installments_count: 9, installment_amount: 39.5, fee_amount: 2.5)

    forecast = Forecast.new(@family, accounts: [ @bank ], card_accounts: [ @card ], through: Date.new(2026, 12, 31),
                                     include_variable: false, today: today)
    card_flows = forecast.flows.select { |flow| flow.source == :card }

    statement = card_flows.find { |flow| flow.date == Date.new(2026, 11, 5) && flow.amount == BigDecimal("200") }
    assert statement, "the October statement, charged on 5 November"
    assert_equal @bank, statement.account
    assert_equal [ Date.new(2026, 11, 5), Date.new(2026, 12, 4) ], card_flows.select { |flow| flow.amount == BigDecimal("39.5") }.map(&:date)
  end

  private
    def cycle(today: Date.new(2026, 10, 15))
      CreditCard::Cycle.new(@card, today: today)
    end

    def spend(amount, date)
      create_transaction(account: @card, name: "Compra", amount: amount, date: date, currency: "EUR")
    end
end
