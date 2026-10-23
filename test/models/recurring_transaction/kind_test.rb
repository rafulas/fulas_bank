require "test_helper"

class RecurringTransaction::KindTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "BBVA", balance: 1_000, currency: "EUR", accountable: Depository.new)
  end

  test "bill types map to the three kinds" do
    assert_equal "subscription", series("Netflix", bill_type: "subscription").fulas_kind
    assert_equal "bill", series("Iberdrola", bill_type: "bill").fulas_kind
    %w[installment income other].each do |type|
      assert_equal "fixed", series("Serie #{type}", bill_type: type).fulas_kind
    end
  end

  test "a fixed one keeps its bill type; a bill made fixed becomes an instalment plan" do
    salary = series("Nómina", amount: -2_500, bill_type: "income")
    salary.fulas_kind = "fixed"
    assert salary.typed_income?

    loan = series("Préstamo", bill_type: "bill")
    loan.fulas_kind = "fixed"
    assert loan.typed_installment?
  end

  test "reclassifies by name: loans fixed, insurance a bill, a streaming service a subscription" do
    loan = series("PRÉSTAMO SOCIAL VIVIENDA", bill_type: "bill")
    insurance = series("Mapfre", bill_type: "subscription")
    spotify = series("Spotify", bill_type: "bill")
    unknown = series("Asociación cultural", bill_type: "bill")

    assert_equal 3, RecurringTransaction::Kind.reclassify!(@family)
    assert_equal "fixed", loan.reload.fulas_kind
    assert_equal "bill", insurance.reload.fulas_kind
    assert_equal "subscription", spotify.reload.fulas_kind
    assert_equal "bill", unknown.reload.fulas_kind
  end

  private
    def series(name, amount: 20, bill_type: "bill")
      @family.recurring_transactions.create!(
        account: @account, name: name, amount: amount, currency: "EUR", dedup_scope: name, bill_type: bill_type,
        expected_day_of_month: 5, status: "active", manual: true,
        last_occurrence_date: Date.current.prev_month, next_expected_date: Date.current.next_month
      )
    end
end
