require "test_helper"

class InvestmentsOverview::PriceRefreshTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @user = users(:empty)
    @account = @family.accounts.create!(name: "Acciones BBVA", balance: 1_000, currency: "USD",
                                        accountable: Investment.new(subtype: "stocks"))
  end

  test "fetches the prices of every share held and recalculates the accounts that hold them" do
    hold(securities(:aapl))
    hold(securities(:msft))

    Security.any_instance.expects(:import_provider_prices).twice.returns([ 20, nil ])
    Balance::Materializer.any_instance.expects(:materialize_balances).once

    result = refresh

    assert_equal %w[AAPL MSFT], result.updated.sort
    assert_empty result.failed
  end

  test "reports the shares the provider has no price for, and skips the ones typed in by hand" do
    hold(securities(:aapl))
    hold(Security.create!(ticker: "MIFONDO", name: "Mi fondo", offline: true))

    Security.any_instance.expects(:import_provider_prices).once.returns([ 0, "not found" ])
    Balance::Materializer.any_instance.expects(:materialize_balances).never

    result = refresh

    assert_empty result.updated
    assert_equal %w[AAPL], result.failed
  end

  test "with no shares there is nothing to do" do
    assert refresh.nothing_to_do?
  end

  private
    def hold(security)
      @account.holdings.create!(security: security, date: Date.current, qty: 10, price: 10, amount: 100, currency: "USD")
    end

    def refresh
      InvestmentsOverview::PriceRefresh.new(InvestmentsOverview.new(@family, user: @user)).run
    end
end
