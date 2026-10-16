require "test_helper"
require "ostruct"

class Security::ManualPricingTest < ActiveSupport::TestCase
  include ProviderTestHelper

  setup do
    @security = Security.create!(ticker: "BBVA.MC", offline: true)
    @provider = Provider::YahooFinance.new
  end

  test "set_manual_price! stores the typed price for the day, marked as manual" do
    @security.set_manual_price!(BigDecimal("18.6"), currency: "EUR")

    price = @security.prices.find_by!(date: Date.current)
    assert_equal BigDecimal("18.6"), price.price
    assert_equal "EUR", price.currency
    assert price.manual
    assert_not price.provisional
  end

  test "set_manual_price! replaces the price that day already had" do
    Security::Price.create!(security: @security, date: Date.current, price: 10, currency: "EUR")

    @security.set_manual_price!(12, currency: "EUR")

    assert_equal 1, @security.prices.where(date: Date.current).count
    assert_equal 12, @security.prices.find_by!(date: Date.current).price
  end

  test "set_manual_price! refuses a price that is not positive" do
    assert_raises(ArgumentError) { @security.set_manual_price!(0, currency: "EUR") }
  end

  test "current_price falls back to the latest stored price when today has none" do
    @security.set_manual_price!(18.6, currency: "EUR", date: 3.days.ago.to_date)

    assert_equal Money.new(18.6, "EUR"), Security.find(@security.id).current_price
  end

  test "a health check that takes a security offline keeps the prices typed by hand" do
    @security.update!(offline: false)
    Security::Price.create!(security: @security, date: 2.days.ago.to_date, price: 17, currency: "EUR")
    @security.set_manual_price!(18.6, currency: "EUR")

    Security::HealthChecker.new(@security).send(:convert_to_offline_security!)

    assert_equal [ true ], @security.prices.reload.map(&:manual)
  end

  test "try_bring_online! puts an offline security back online with the provider that knows it" do
    Security.stubs(:providers).returns([ @provider ])
    @provider.expects(:fetch_security_price)
             .with(symbol: "BBVA.MC", exchange_operating_mic: nil, date: Date.current)
             .returns(provider_success_response(OpenStruct.new(date: Date.current, price: 18.6, currency: "EUR")))

    assert @security.try_bring_online!(currency: "EUR")

    @security.reload
    assert_not @security.offline?
    assert_equal "yahoo_finance", @security.price_provider
  end

  test "try_bring_online! ignores a listing in another currency" do
    Security.stubs(:providers).returns([ @provider ])
    @provider.stubs(:fetch_security_price)
             .returns(provider_success_response(OpenStruct.new(date: Date.current, price: 21.3, currency: "USD")))

    assert_not @security.try_bring_online!(currency: "EUR")
    assert @security.reload.offline?
  end

  test "try_bring_online! keeps the security offline when no provider finds it" do
    Security.stubs(:providers).returns([ @provider ])
    @provider.stubs(:fetch_security_price).returns(provider_error_response(StandardError.new("not found")))

    assert_not @security.try_bring_online!(currency: "EUR")
    assert @security.reload.offline?
  end
end
