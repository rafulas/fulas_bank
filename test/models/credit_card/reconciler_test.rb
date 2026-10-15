require "test_helper"

class CreditCard::ReconcilerTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @bank = @family.accounts.create!(name: "BBVA Rafa", balance: 5_000, currency: "EUR", accountable: Depository.new)
    @card = @family.accounts.create!(name: "Tarjeta BBVA Rafa", balance: 0, currency: "EUR",
                                     accountable: CreditCard.new(statement_closing_day: 31, payment_day: 5, payment_account: @bank))
    @fees = @family.categories.create!(name: "Comisiones", color: "#506cd8", lucide_icon: "shapes")
    @today = Date.new(2026, 10, 15)

    @revision = card_purchase(345.67, Date.new(2026, 9, 12), "Revisión moto")
    card_purchase(1_000, Date.new(2026, 9, 20), "Compras")
    CardFinancing.from_entry(@revision).update!(installments_count: 9, installment_amount: 39.5, fee_amount: 2.5)
  end

  test "files the statement charge as a payment to the card, and says it matches" do
    charge = bank_charge(1_000, Date.new(2026, 10, 5), "ADEUDO MENSUAL DE TARJETA")

    assert_operator reconciler.run!, :>=, 1

    transfer = Transfer.find_by(outflow_transaction: charge.entryable)
    assert transfer, "the charge is a transfer to the card"
    assert_equal @card, transfer.inflow_transaction.entry.account
    assert_equal "cc_payment", charge.entryable.reload.kind

    status = reconciler.status_for(CreditCard::Cycle.new(@card, today: @today).statement(Date.new(2026, 9, 1)))
    assert_equal :matched, status.state
  end

  test "says how much the charge differs from the statement" do
    bank_charge(1_002.40, Date.new(2026, 10, 5), "ADEUDO MENSUAL DE TARJETA")

    status = reconciler.status_for(CreditCard::Cycle.new(@card, today: @today).statement(Date.new(2026, 9, 1)))

    assert_equal :different, status.state
    assert_equal BigDecimal("2.40"), status.difference
  end

  test "links the card's own payment when it was imported instead of adding one" do
    charge = bank_charge(1_000, Date.new(2026, 10, 5), "ADEUDO MENSUAL DE TARJETA")
    payment = create_transaction(account: @card, name: "PAGO", amount: -1_000, date: Date.new(2026, 10, 6), currency: "EUR")

    assert_no_difference -> { @card.entries.count } do
      reconciler.run!
    end

    assert_equal payment.entryable, Transfer.find_by(outflow_transaction: charge.entryable).inflow_transaction
  end

  test "splits the financed charge into the instalments, paid to the card, and the fees" do
    charge = bank_charge(42, Date.new(2026, 11, 5), "OPERACION FINANCIADA CON TARJETA")

    reconciler(today: Date.new(2026, 11, 10)).run!

    assert charge.reload.excluded?, "the original charge is split"
    paid, cost = charge.child_entries.order(:amount).reverse
    assert_equal BigDecimal("39.5"), paid.amount
    assert Transfer.exists?(outflow_transaction: paid.entryable)
    assert_equal BigDecimal("2.5"), cost.amount
    assert_equal @fees, cost.entryable.category
  end

  test "the fee of the first month is spending, and nothing is filed twice" do
    charge = bank_charge(2.5, Date.new(2026, 10, 5), "OPERACION FINANCIADA CON TARJETA")

    reconciler.run!
    reconciler.run!

    assert_equal @fees, charge.entryable.reload.category
    assert_not Transfer.exists?(outflow_transaction: charge.entryable)
  end

  private
    def reconciler(today: @today)
      CreditCard::Reconciler.new(@card, today: today)
    end

    def card_purchase(amount, date, name)
      create_transaction(account: @card, name: name, amount: amount, date: date, currency: "EUR")
    end

    def bank_charge(amount, date, name)
      create_transaction(account: @bank, name: name, amount: amount, date: date, currency: "EUR")
    end
end
