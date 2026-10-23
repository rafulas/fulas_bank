require "test_helper"

class Category::AnalysisTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "Analysis checking", balance: 0, currency: "USD", accountable: Depository.new)
    @food = @family.categories.create!(name: "Comida", color: "#22c55e")
    @market = @family.categories.create!(name: "Súper", color: "#16a34a", parent: @food)
    @home = @family.categories.create!(name: "Hogar", color: "#84cc16")
    @salary = @family.categories.create!(name: "Ingresos", color: "#f59e0b")
    @today = Date.new(2026, 10, 14)
    @period = Period.custom(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31))
  end

  test "spending and income by main category, total and savings rate" do
    create_transaction(account: @account, amount: 30, date: Date.new(2026, 10, 2), category: @market)
    create_transaction(account: @account, amount: 20, date: Date.new(2026, 10, 2), category: @food)
    create_transaction(account: @account, amount: 400, date: Date.new(2026, 10, 5), category: @home)
    create_transaction(account: @account, amount: -1_000, date: Date.new(2026, 10, 1), category: @salary)
    create_transaction(account: @account, amount: 300, date: Date.new(2026, 10, 3), kind: "funds_movement")

    assert_equal [ [ "Hogar", 400 ], [ "Comida", 50 ] ], analysis.spending_slices.map { |slice| [ slice.name, slice.amount.to_i ] }
    assert_equal [ [ "Ingresos", 1_000 ] ], analysis.income_slices.map { |slice| [ slice.name, slice.amount.to_i ] }
    assert_equal Money.new(550, "USD"), analysis.net
    assert_equal 55, analysis.savings_rate
  end

  # A statement just imported has no categories yet: the salary must not
  # cancel the purchases (it showed "0 € spent" and a 100 % savings rate).
  test "income and spending with no category are kept apart" do
    create_transaction(account: @account, amount: -1_850, date: Date.new(2026, 10, 1))
    create_transaction(account: @account, amount: 87.45, date: Date.new(2026, 10, 2))
    create_transaction(account: @account, amount: 550.19, date: Date.new(2026, 10, 6))

    assert_equal BigDecimal("637.64"), analysis.spent.amount
    assert_equal BigDecimal("1850"), analysis.income.amount
    assert_equal 66, analysis.savings_rate
    assert_equal [ BigDecimal("637.64") ], analysis.spending_slices.map(&:amount)
    assert_equal [ BigDecimal("1850") ], analysis.income_slices.map(&:amount)
  end

  test "the month's calendar, each day with what it went on" do
    create_transaction(account: @account, amount: 30, date: Date.new(2026, 10, 9), category: @market)
    create_transaction(account: @account, amount: 10, date: Date.new(2026, 10, 9), category: @home)
    create_transaction(account: @account, amount: 99, date: Date.new(2026, 10, 20), category: @home)

    days = analysis.calendar_days
    ninth = days.find { |day| day.date == Date.new(2026, 10, 9) }

    assert_equal 31, days.size
    assert_equal(-40, ninth.total.to_i)
    assert_equal [ "Comida", "Hogar" ], ninth.slices.map(&:name)
    assert_empty days.find { |day| day.date == Date.new(2026, 10, 20) }.slices, "days after today stay empty"
  end

  test "tags and merchants with the most spending" do
    tag = @family.tags.create!(name: "Cupra", color: "#f97316")
    entry = create_transaction(account: @account, name: "Gasolinera", amount: 60, date: Date.new(2026, 10, 3), category: @home)
    entry.transaction.update!(tags: [ tag ])
    create_transaction(account: @account, name: "Mercadona", amount: 25, date: Date.new(2026, 10, 4), category: @market)
    create_transaction(account: @account, name: "Mercadona", amount: 15, date: Date.new(2026, 10, 6), category: @market)

    assert_equal [ [ tag, 60 ] ], analysis.tag_totals.map { |found, amount| [ found, amount.to_i ] }
    assert_equal [ [ "Gasolinera", 60 ], [ "Mercadona", 40 ] ], analysis.merchant_totals.map { |name, amount| [ name, amount.to_i ] }
  end

  test "the last six months, income up and spending down, and their average" do
    create_transaction(account: @account, amount: -2_000, date: Date.new(2026, 5, 28), category: @salary)
    create_transaction(account: @account, amount: 500, date: Date.new(2026, 5, 3), category: @home)
    create_transaction(account: @account, amount: 100, date: Date.new(2026, 10, 3), category: @market)

    bars = analysis.month_bars

    assert_equal (5..10).map { |month| Date.new(2026, month, 1) }, bars.map(&:month)
    assert_equal [ 2_000, 500 ], [ bars.first.income.sum(&:amount).to_i, bars.first.spending.sum(&:amount).to_i ]
    assert_equal [ "Comida" ], bars.last.spending.map(&:name)
    assert_equal Money.new((2_000 - 500 - 100) / 6.0, "USD").amount.round(2), analysis.month_bars_average.amount.round(2)
  end

  test "average daily spending over the days elapsed" do
    create_transaction(account: @account, amount: 140, date: Date.new(2026, 10, 2), category: @home)

    assert_equal 14, analysis.days_elapsed
    assert_equal Money.new(10, "USD"), analysis.daily_average
  end

  test "loan instalments and contributions count as spending, and selling an investment as income" do
    loan = @family.accounts.create!(name: "Hipoteca", balance: 100_000, currency: "USD", accountable: Loan.new)
    fund = @family.accounts.create!(name: "Fondo", balance: 5_000, currency: "USD", accountable: Investment.new)
    card = @family.accounts.create!(name: "Tarjeta", balance: 0, currency: "USD", accountable: CreditCard.new)
    savings = @family.accounts.create!(name: "Ahorro", balance: 0, currency: "USD", accountable: Depository.new)
    investing = @family.categories.create!(name: "Inversiones", color: "#a448d8")
    funds = @family.categories.create!(name: Category::FulasTree::INVESTMENT_CONTRIBUTIONS_NAME, color: "#a448d8", parent: investing)

    instalment = transfer(from: @account, to: loan, amount: 500, date: Date.new(2026, 10, 4))
    instalment.outflow_transaction.update!(category: @home)
    contribution = transfer(from: @account, to: fund, amount: 200, date: Date.new(2026, 10, 5))
    contribution.outflow_transaction.update!(category: investing)
    sale = transfer(from: fund, to: @account, amount: 150, date: Date.new(2026, 10, 6))
    transfer(from: @account, to: card, amount: 80, date: Date.new(2026, 10, 7))
    transfer(from: @account, to: savings, amount: 300, date: Date.new(2026, 10, 8))

    assert_equal funds, sale.inflow_transaction.reload.category, "the cash from selling is categorized as an investment"

    # Each main category nets its money in and out: 200 put in, 150 taken out.
    assert_equal [ [ "Hogar", 500 ], [ "Inversiones", 50 ] ], analysis.spending_slices.map { |slice| [ slice.name, slice.amount.to_i ] }
    assert_empty analysis.income_slices

    assert instalment.outflow_transaction.counts_by_kind?
    assert contribution.outflow_transaction.counts_by_kind?
    assert sale.inflow_transaction.counts_by_kind?
    assert_not contribution.inflow_transaction.counts_by_kind?, "the leg inside the investment account counts as nothing"
    assert_not sale.outflow_transaction.counts_by_kind?
  end

  private
    def transfer(from:, to:, amount:, date:)
      Transfer::Creator.new(family: @family, source_account_id: from.id, destination_account_id: to.id, date: date, amount: amount).create
    end

    def analysis
      Category::Analysis.new(@family, period: @period, account_ids: [ @account.id ], today: @today)
    end
end
