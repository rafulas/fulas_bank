require "test_helper"

class Account::InvestmentProgressTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
  end

  test "adds up the money put in up to each day" do
    policy = investment("Póliza", balance: 2_300)
    contribute(policy, 1_000, Date.new(2025, 1, 10))
    contribute(policy, 1_000, Date.new(2025, 6, 10))
    withdraw(policy, 200, Date.new(2025, 9, 1))

    progress = Account::InvestmentProgress.new(policy)

    assert progress.applies?
    assert_equal Money.new(0, "EUR"), progress.contributed_on(Date.new(2025, 1, 9))
    assert_equal Money.new(1_000, "EUR"), progress.contributed_on(Date.new(2025, 1, 10))
    assert_equal Money.new(2_000, "EUR"), progress.contributed_on(Date.new(2025, 8, 31))
    assert_equal Money.new(1_800, "EUR"), progress.contributed_on(Date.new(2025, 9, 1))
  end

  test "each day of the value chart carries its value, gain and money put in" do
    policy = investment("Póliza", balance: 2_300)
    contribute(policy, 1_000, Date.new(2025, 1, 10))
    contribute(policy, 1_000, Date.new(2025, 6, 10))

    series = Series.new(
      start_date: Date.new(2025, 6, 1), end_date: Date.new(2025, 6, 30), interval: "1 day",
      values: [
        Series::Value.new(date: Date.new(2025, 6, 1), date_formatted: "", value: Money.new(1_100, "EUR")),
        Series::Value.new(date: Date.new(2025, 6, 30), date_formatted: "", value: Money.new(2_150, "EUR"))
      ]
    )

    Account::InvestmentProgress.new(policy).annotate(series)

    first, last = series.values.map { |value| value.details.index_by { |detail| detail[:key] } }
    assert_equal Money.new(1_100, "EUR"), first["value"][:value]
    assert_equal Money.new(1_000, "EUR"), first["contributed"][:value]
    assert_equal Money.new(100, "EUR"), first["gain"][:value]
    assert_equal Money.new(2_000, "EUR"), last["contributed"][:value]
    assert_equal Money.new(150, "EUR"), last["gain"][:value]
    assert_includes last["gain"][:percent_formatted], "7"

    json = series.as_json[:values].last[:details]
    assert_equal %w[value gain contributed], json.map { |detail| detail[:key] }
  end

  test "an account with nothing put in, or that is not an investment, shows nothing extra" do
    by_hand = investment("Fondo a mano", balance: 0)
    checking = @family.accounts.create!(name: "BBVA", balance: 1_000, currency: "EUR", accountable: Depository.new)

    refute Account::InvestmentProgress.new(by_hand).applies?
    refute Account::InvestmentProgress.new(checking).applies?

    series = Series.new(start_date: Date.current, end_date: Date.current, interval: "1 day",
                        values: [ Series::Value.new(date: Date.current, date_formatted: "", value: Money.new(0, "EUR")) ])
    Account::InvestmentProgress.new(by_hand).annotate(series)

    assert_nil series.values.first.details
    refute series.as_json[:values].first.key?(:details)
  end

  private
    def investment(name, balance:)
      @family.accounts.create!(name: name, balance: balance, currency: "EUR", accountable: Investment.new)
    end

    def contribute(account, amount, date)
      create_transaction(account: account, name: "Aportación", amount: -amount, date: date, currency: "EUR")
    end

    def withdraw(account, amount, date)
      create_transaction(account: account, name: "Rescate", amount: amount, date: date, currency: "EUR")
    end
end
