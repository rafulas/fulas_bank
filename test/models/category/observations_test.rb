require "test_helper"

class Category::ObservationsTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "Observations checking", balance: 0, currency: "USD", accountable: Depository.new)
    @food = @family.categories.create!(name: "Comida", color: "#22c55e")
    @salary = @family.categories.create!(name: "Nómina obs", color: "#f59e0b")
    @today = Date.new(2026, 10, 14)
    @period = Period.custom(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31))
  end

  test "a sentence and a figure for what stands out in the period" do
    create_transaction(account: @account, amount: 300, date: Date.new(2026, 10, 2), category: @food, name: "Mercadona")
    create_transaction(account: @account, amount: 100, date: Date.new(2026, 10, 3), category: @food, name: "Lidl")
    create_transaction(account: @account, amount: -1_000, date: Date.new(2026, 10, 1), category: @salary)
    create_transaction(account: @account, amount: 50, date: Date.new(2026, 8, 3), category: @food)

    by_key = observations.all.index_by(&:key)

    assert_equal "75 %", by_key[:merchant].figure
    assert_match "Mercadona", by_key[:merchant].text
    assert_equal "60 %", by_key[:saving].figure
    assert_equal :positive, by_key[:saving].tone
    assert_equal "100 %", by_key[:income_source].figure
    assert_equal :warning, by_key[:category_change].tone
    assert by_key.key?(:daily)
  end

  test "nothing to say without movements" do
    assert_not observations.any?
  end

  private
    def observations
      analysis = Category::Analysis.new(@family, period: @period, account_ids: [ @account.id ], today: @today)
      Category::Observations.new(analysis)
    end
end
