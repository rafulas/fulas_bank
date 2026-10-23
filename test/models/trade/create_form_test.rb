require "test_helper"

# Fulas Bank: a buy the account's cash does not cover records the money put in.
class Trade::CreateFormTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @security = securities(:aapl)
  end

  test "a buy in an account with no cash records the money put in, so the account is worth the shares" do
    account = @family.accounts.create!(name: "Acciones BBVA", balance: 0, cash_balance: 0, currency: "USD",
                                       accountable: Investment.new(subtype: "stocks"))

    entry = nil
    assert_difference -> { account.entries.count }, 2 do
      entry = buy(account, qty: 100, price: 4)
    end

    assert entry.persisted?
    deposit = account.entries.where(entryable_type: "Transaction").sole
    assert_equal(-400, deposit.amount)
    assert_equal entry.date, deposit.date
    assert deposit.transaction.funds_movement?
    assert_equal I18n.t("trades.form.purchase_funding_name", ticker: "AAPL"), deposit.name
  end

  test "only the part the cash does not cover is put in" do
    account = @family.accounts.create!(name: "Broker", balance: 150, cash_balance: 150, currency: "USD",
                                       accountable: Investment.new)

    buy(account, qty: 100, price: 4)

    assert_equal(-250, account.entries.where(entryable_type: "Transaction").sole.amount)
  end

  test "a buy the cash covers, or a sale, records nothing else" do
    account = @family.accounts.create!(name: "Broker", balance: 1_000, cash_balance: 1_000, currency: "USD",
                                       accountable: Investment.new)

    assert_difference -> { account.entries.count }, 1 do
      buy(account, qty: 100, price: 4)
    end

    assert_difference -> { account.entries.count }, 1 do
      buy(account, qty: 10, price: 4, type: "sell")
    end
  end

  test "shares received as pay: the pay as income and the shares bought with it, nothing else" do
    account = @family.accounts.create!(name: "Cuenta de Valores", balance: 0, cash_balance: 0, currency: "USD",
                                       accountable: Investment.new(subtype: "stocks"))
    payroll = @family.categories.create!(name: "Nómina", color: "#e99537", lucide_icon: "banknote")

    form = Trade::CreateForm.new(account: account, date: Date.current, amount: 7_083.89, qty: 348,
                                 currency: "USD", type: "grant", manual_ticker: "AAPL")
    form.stubs(:security).returns(@security)

    trade_entry = nil
    assert_difference -> { account.entries.count }, 2 do
      trade_entry = form.create
    end

    assert trade_entry.persisted?
    assert_equal 348, trade_entry.entryable.qty
    assert_in_delta 7_083.89, trade_entry.amount, 0.01
    income = account.entries.where(entryable_type: "Transaction").sole
    assert_equal(-7_083.89, income.amount)
    assert_equal payroll, income.entryable.category
    assert income.entryable.standard?
  end

  private
    def buy(account, qty:, price:, type: "buy")
      form = Trade::CreateForm.new(account: account, date: Date.current, qty: qty, price: price,
                                   currency: "USD", type: type, manual_ticker: "AAPL")
      form.stubs(:security).returns(@security)
      form.create
    end
end
