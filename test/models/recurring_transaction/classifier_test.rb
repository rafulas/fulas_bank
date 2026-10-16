require "test_helper"

class RecurringTransaction::ClassifierTest < ActiveSupport::TestCase
  Classifier = RecurringTransaction::Classifier

  def setup
    @family = families(:dylan_family)
    @depository = accounts(:depository)
    @credit_card = accounts(:credit_card)
  end

  test "known services classify as subscriptions with autopay on" do
    result = Classifier.classify(name: "Netflix.com", entries: entries_of(15.99, 15.99), account: @depository)

    assert_equal "subscription", result.bill_type
    assert result.autopay
  end

  test "utility and telecom wording classifies as a bill even when flat" do
    result = Classifier.classify(name: "XFINITY INTERNET", entries: entries_of(89.99, 89.99), account: @credit_card)

    assert_equal "bill", result.bill_type
    assert_not result.autopay
  end

  test "ach and billpay descriptors are push payments, not subscriptions" do
    result = Classifier.classify(name: "WATSON PROPERTY WEB PMT", entries: entries_of(537.50, 537.50), account: @depository)

    assert_equal "bill", result.bill_type
  end

  test "a flat modest card charge with no name signal reads as a subscription" do
    result = Classifier.classify(name: "SOMEOBSCURESERVICE", entries: entries_of(9.99, 9.99), account: @credit_card)

    assert_equal "subscription", result.bill_type
  end

  test "varying amounts break the card-charge heuristic" do
    result = Classifier.classify(name: "SOMEOBSCURESERVICE", entries: entries_of(42.17, 39.80), account: @credit_card)

    assert_equal "bill", result.bill_type
  end

  test "interest charges never read as subscriptions someone chose" do
    result = Classifier.classify(name: "Interest Charge", entries: entries_of(2.14, 2.14), account: @credit_card)

    assert_equal "bill", result.bill_type
  end

  test "the series inherits the cluster's most common category" do
    food = categories(:food_and_drink)
    tagged = entries_of(12, 12, 12)
    tagged.first(2).each { |entry| entry.entryable.update!(category: food) }

    result = Classifier.classify(name: "MYSTERY BOX", entries: tagged, account: @depository)

    assert_equal food.id, result.category_id
  end

  test "detection creates classified suggestions" do
    @family.recurring_transactions.destroy_all
    [ 0, 1, 2 ].each do |months_ago|
      @credit_card.entries.create!(
        date: months_ago.months.ago.beginning_of_month + 7.days,
        amount: 15.99, currency: "USD", name: "SPOTIFY USA",
        entryable: Transaction.new
      )
    end

    RecurringTransaction::Identifier.new(@family).identify_recurring_patterns

    created = @family.recurring_transactions.find_by(name: "SPOTIFY USA")
    assert_equal "subscription", created.bill_type
    assert created.autopay
    assert_equal "suggested", created.status
  end


  # A substring test let "max" claim any Maxwell and "gas" claim a gastropub,
  # and a false subscription match also set autopay, which hides the row from
  # the needs-action list.
  test "short keywords only match whole words" do
    result = RecurringTransaction::Classifier.classify(
      name: "Maxwell Plumbing", entries: entries_of(45)
    )
    assert_equal "bill", result.bill_type, "Maxwell is not HBO Max"
  end

  test "the real service names still match" do
    result = RecurringTransaction::Classifier.classify(
      name: "HBO MAX SUBSCRIPTION", entries: entries_of(15.99)
    )
    assert_equal "subscription", result.bill_type
  end

  # The word-boundary fix silently disabled the stems: utilit never
  # matches UTILITIES. Starred stems accept a suffix without regaining the
  # anywhere-in-the-word looseness the boundary fix removed.
  test "keyword stems still reach their inflections" do
    utilities = RecurringTransaction::Classifier.classify(
      name: "AUSTIN UTILITIES", entries: entries_of(120)
    )
    assert_equal "bill", utilities.bill_type
    assert_not utilities.autopay, "a utility is not autopay by default"

    insurer = RecurringTransaction::Classifier.classify(
      name: "STATE FARM INSUR PREM", entries: entries_of(140)
    )
    assert_equal "bill", insurer.bill_type
  end

  # Fulas Bank: a subscription is only what can be cancelled at will.
  test "spanish insurance on a card is a bill, not a subscription" do
    result = Classifier.classify(name: "MAPFRE SEGUROS AUTO", entries: entries_of(47, 47), account: @credit_card)

    assert_equal "bill", result.bill_type
    assert_not result.autopay
  end

  test "a mortgage or a loan is an installment" do
    assert_equal "installment", Classifier.classify(name: "CUOTA HIPOTECA", entries: entries_of(650, 650)).bill_type
    assert_equal "installment", Classifier.classify(name: "Préstamo coche", entries: entries_of(220, 220)).bill_type
  end

  test "spanish utilities and telecom are bills" do
    assert_equal "bill", Classifier.classify(name: "IBERDROLA CLIENTES", entries: entries_of(60), account: @credit_card).bill_type
    assert_equal "bill", Classifier.classify(name: "MOVISTAR", entries: entries_of(45, 45), account: @credit_card).bill_type
  end

  test "a named service wins over bill-like wording" do
    assert_equal "subscription", Classifier.classify(name: "MOVISTAR PLUS", entries: entries_of(12, 12)).bill_type
    assert_equal "subscription", Classifier.classify(name: "Gimnasio VivaGym", entries: entries_of(29.9, 29.9)).bill_type
  end

  test "the category decides when the name says nothing" do
    insurance = category("Seguro del vehículo")
    charges = entries_of(9.99, 9.99)
    charges.each { |entry| entry.entryable.update!(category: insurance) }
    assert_equal "bill", Classifier.classify(name: "SOMEOBSCURESERVICE", entries: charges, account: @credit_card).bill_type

    digital = category("Servicios digitales")
    charges = entries_of(30, 25)
    charges.each { |entry| entry.entryable.update!(category: digital) }
    assert_equal "subscription", Classifier.classify(name: "ANOTHERSERVICE", entries: charges).bill_type
  end

  test "a subcategory of Gastos financieros is an obligation" do
    parent = category("Gastos financieros")
    child = @family.categories.create!(name: "Mi seguro raro", parent: parent, color: "#b86460", lucide_icon: "shield")
    series = recurring_transactions(:netflix_subscription)
    series.update_columns(name: "ALGO", merchant_id: nil, category_id: child.id)

    assert Classifier.obligatory?(series.reload)
  end

  test "refile_obligations! moves misfiled subscriptions and leaves real ones" do
    real = recurring_transactions(:netflix_subscription)
    real.update_columns(bill_type: "subscription")
    insurance = recurring_transactions(:inactive_subscription)
    insurance.update_columns(bill_type: "subscription", merchant_id: nil, name: "SEGURO HOGAR MUTUA")

    Classifier.refile_obligations!(@family)

    assert real.reload.typed_subscription?
    assert insurance.reload.typed_bill?
  end

  private
    def category(name)
      @family.categories.find_by(name: name) ||
        @family.categories.create!(name: name, color: "#b86460", lucide_icon: "shield")
    end

    def entries_of(*amounts)
      amounts.map.with_index do |amount, index|
        @depository.entries.create!(
          date: index.months.ago.to_date,
          amount: amount,
          currency: "USD",
          name: "classifier test entry #{index}",
          entryable: Transaction.new
        )
      end
    end
end
