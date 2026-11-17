require "test_helper"

class MerchantActivityTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "Comercios corriente", balance: 0, currency: "USD", accountable: Depository.new)
    @physio = @family.categories.create!(name: "Fisio", color: "#22c55e")
    @today = Date.new(2026, 10, 14)
    @period = Period.custom(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31))
    @merchant = @family.merchants.create!(name: "Clínica Sol")
  end

  test "lists each merchant with what was spent, net of refunds, most first" do
    create_transaction(account: @account, name: "CLINICA SOL 1", amount: 55, date: Date.new(2026, 10, 2), merchant: @merchant)
    create_transaction(account: @account, name: "CLINICA SOL 2", amount: 55, date: Date.new(2026, 10, 9), merchant: @merchant)
    create_transaction(account: @account, name: "Reembolso", amount: -45, date: Date.new(2026, 10, 10), merchant: @merchant, category: @physio)
    create_transaction(account: @account, name: "Panadería", amount: 20, date: Date.new(2026, 10, 3))
    create_transaction(account: @account, name: "Panadería", amount: 5, date: Date.new(2026, 9, 3))

    rows = activity.list

    assert_equal [ "Clínica Sol", "Panadería" ], rows.map(&:name)
    clinic = rows.first
    assert_equal 65, clinic.spent
    assert_equal 45, clinic.refunded
    assert_equal 2, clinic.count
    assert_equal Date.new(2026, 10, 10), clinic.last_date
    assert_equal 20, rows.last.spent
    assert_equal [ "Panadería" ], activity.list(search: "pana").map(&:name)
  end

  test "a merchant's page has its months, categories and latest movements" do
    create_transaction(account: @account, name: "Sol", amount: 55, date: Date.new(2026, 10, 2), merchant: @merchant, category: @physio)
    create_transaction(account: @account, name: "Sol", amount: 40, date: Date.new(2026, 8, 20), merchant: @merchant)

    detail = activity.detail("Clínica Sol")

    assert_equal 55, detail.row.spent
    assert_equal Date.new(2026, 8, 20), detail.first_date
    assert_equal 12, detail.months.size
    assert_equal 40, detail.months.find { |month| month.month == Date.new(2026, 8, 1) }.spent
    assert_equal 47.5, detail.monthly_average
    assert_equal [ @physio ], detail.categories.map(&:category)
    assert_equal 2, detail.entries.size
    assert_nil activity.detail("No existe")
  end

  private
    def activity
      MerchantActivity.new(@family, period: @period, account_ids: [ @account.id ], today: @today)
    end
end
