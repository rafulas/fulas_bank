require "test_helper"

class RegionalDefaultsTest < ActiveSupport::TestCase
  SPAIN = {
    DEFAULT_LOCALE: "es",
    DEFAULT_CURRENCY: "EUR",
    DEFAULT_COUNTRY: "ES",
    DEFAULT_DATE_FORMAT: "%d/%m/%Y",
    DEFAULT_TIMEZONE: "Europe/Madrid",
    DEFAULT_NUMBER_FORMAT: "1.234,56"
  }.freeze

  test "new families keep the schema defaults when nothing is configured" do
    family = Family.new

    assert_equal "en", family.locale
    assert_equal "USD", family.currency
    assert_equal "US", family.country
    assert_equal "%m-%d-%Y", family.date_format
    assert_nil family.timezone
  end

  test "new families start with the configured regional defaults" do
    with_env_overrides(SPAIN) do
      family = Family.new

      assert_equal "es", family.locale
      assert_equal "EUR", family.currency
      assert_equal "ES", family.country
      assert_equal "%d/%m/%Y", family.date_format
      assert_equal "Europe/Madrid", family.timezone
      assert family.valid?, family.errors.full_messages.to_sentence
    end
  end

  test "explicit attributes win over regional defaults" do
    with_env_overrides(SPAIN) do
      family = Family.new(currency: "GBP", locale: "fr")

      assert_equal "GBP", family.currency
      assert_equal "fr", family.locale
      assert_equal "ES", family.country
    end
  end

  test "existing families are not touched" do
    family = families(:dylan_family)
    original_currency = family.currency

    with_env_overrides(SPAIN) do
      assert_equal original_currency, Family.find(family.id).currency
    end
  end

  test "invalid values are ignored" do
    with_env_overrides(DEFAULT_LOCALE: "xx", DEFAULT_DATE_FORMAT: "%Q", DEFAULT_TIMEZONE: "Mars/Olympus", DEFAULT_NUMBER_FORMAT: "12") do
      assert_equal({}, RegionalDefaults.family_attributes.slice(:locale, :date_format, :timezone))
      assert_nil RegionalDefaults.number_format
    end
  end

  test "imports use the configured number format by default" do
    with_env_overrides(SPAIN) do
      import = families(:dylan_family).imports.new(type: "TransactionImport")
      import.valid?

      assert_equal "1.234,56", import.number_format
    end
  end
end
