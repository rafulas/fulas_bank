require "test_helper"

class Rule::SuggesterTest < ActiveSupport::TestCase
  include EntriesTestHelper
  include ActiveJob::TestHelper

  setup do
    @family = families(:dylan_family)
    @groceries = categories(:food_and_drink)
    @account = accounts(:depository)
  end

  test "finds the words a rule should look for" do
    assert_equal "MERCADONA", Rule::Suggester.key_for("COMPRA EN MERCADONA VALENCIA, CON LA TARJETA 1234")
    assert_equal "NETFLIX", Rule::Suggester.key_for("Netflix.com")
    assert_equal "BAR PEPE", Rule::Suggester.key_for("Bar Pepe 12/10")
    assert_nil Rule::Suggester.key_for("Pago 123")
  end

  test "suggests a rule when one category holds most movements of a name" do
    3.times { |index| create_transaction(account: @account, name: "COMPRA EN MERCADONA VALENCIA #{index}", amount: 40, category: @groceries, date: Date.current - index) }
    create_transaction(account: @account, name: "MERCADONA ONLINE", amount: 60, date: Date.current - 5)

    suggestion = suggester.suggestions.find { |each| each.key == "MERCADONA" }

    assert_equal @groceries, suggestion.category
    assert_equal "expense", suggestion.transaction_type
    assert_equal 3, suggestion.count
    assert_equal 1, suggestion.uncategorized_count
    assert_in_delta 1.0, suggestion.share
  end

  test "leaves out names without a clear category, already covered by a rule, or dismissed" do
    2.times { |index| create_transaction(account: @account, name: "FERRETERIA LOPEZ #{index}", amount: 10, category: @groceries, date: Date.current - index) }
    2.times { |index| create_transaction(account: @account, name: "FERRETERIA LOPEZ #{index}", amount: 10, category: categories(:one), date: Date.current - index) }
    3.times { |index| create_transaction(account: @account, name: "STARBUCKS #{index}", amount: 5, category: @groceries, date: Date.current - index) }
    3.times { |index| create_transaction(account: @account, name: "IBERDROLA #{index}", amount: 50, category: @groceries, date: Date.current - index) }

    keys = Rule::Suggester.new(@family, entries: @family.entries, dismissed: [ "expense:IBERDROLA" ]).suggestions.map(&:key)

    assert_not_includes keys, "FERRETERIA"
    assert_not_includes keys, "STARBUCKS" # rules(:one) looks for "starbucks"
    assert_not_includes keys, "IBERDROLA"
  end

  test "creating the rule only categorizes movements without a category" do
    4.times { |index| create_transaction(account: @account, name: "MERCADONA #{index}", amount: 40, category: @groceries, date: Date.current - index) }
    other = create_transaction(account: @account, name: "MERCADONA LIMPIEZA", amount: 15, category: categories(:one), date: Date.current - 4)
    loose = create_transaction(account: @account, name: "MERCADONA EXPRESS", amount: 12, date: Date.current - 6)
    suggestion = suggester.suggestions.find { |each| each.key == "MERCADONA" }

    rule = nil
    perform_enqueued_jobs { rule = suggester.accept!(suggestion) }

    assert_equal [ "transaction_category", "transaction_name", "transaction_type" ], rule.conditions.map(&:condition_type).sort
    assert_equal @groceries, loose.reload.transaction.category
    assert_equal categories(:one), other.reload.transaction.category
    assert_not suggester.suggestions.any? { |each| each.key == "MERCADONA" }
  end

  private
    def suggester
      @suggester ||= Rule::Suggester.new(@family, entries: @family.entries)
    end
end
