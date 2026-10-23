require "test_helper"

class Category::SpendingSplitTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "BBVA", balance: 0, currency: @family.currency, accountable: Depository.new)
    @income = category("Ingresos")
    @food = category("Comida y bebida", spending_class: "essential")
    @bars = category("Cañas y vinos", parent: @food, spending_class: "discretionary")
    @groceries = category("Supermercado", parent: @food)
    @investments = category("Inversiones", spending_class: "savings")
    @other = category("Sin tipo")
    @month = Date.new(2026, 9, 1)
  end

  test "splits the month's income into necessary, discretionary and what is left" do
    move(-2_000, @income)
    move(600, @groceries)      # inherits necessary from Comida y bebida
    move(300, @bars)           # discretionary on its own
    move(100, @other)          # not classified: discretionary
    move(500, @investments)    # saving: not taken from what is left

    essential, discretionary, savings = split.parts

    assert_equal Money.new(2_000, @family.currency), split.income
    assert_equal [ 600, 30 ], [ essential.amount.amount, essential.share ]
    assert_equal [ 400, 20 ], [ discretionary.amount.amount, discretionary.share ]
    assert_equal [ 1_000, 50 ], [ savings.amount.amount, savings.share ]
    assert_equal Money.new(100, @family.currency), split.unclassified
    assert_equal [ 50, 30, 20 ], [ essential.target, discretionary.target, savings.target ]
  end

  test "income and spending with no category are kept apart" do
    move(-1_850, nil)
    move(637.64, nil)

    essential, discretionary, savings = split.parts

    assert_equal Money.new(1_850, @family.currency), split.income
    assert_equal Money.new(637.64, @family.currency), split.unclassified
    assert_equal 0, essential.amount.amount
    assert_equal BigDecimal("637.64"), discretionary.amount.amount
    assert_equal BigDecimal("1212.36"), savings.amount.amount
  end

  test "a target that does not add up to 100 falls back to 50/30/20" do
    assert_equal [ 50, 30, 20 ], Category::SpendingSplit.new(@family, range: range, account_ids: [], target: [ 70, 30, 20 ]).target
    assert_equal [ 60, 25, 15 ], Category::SpendingSplit.new(@family, range: range, account_ids: [], target: [ 60, 25, 15 ]).target
  end

  private
    def range
      @month..@month.end_of_month
    end

    def split
      Category::SpendingSplit.new(@family, range: range, account_ids: [ @account.id ])
    end

    def category(name, parent: nil, spending_class: nil)
      @family.categories.create!(name: name, parent: parent, spending_class: spending_class, color: "#506cd8", lucide_icon: "shapes")
    end

    def move(amount, category)
      create_transaction(account: @account, amount: amount, date: @month + 10, category: category, currency: @family.currency)
    end
end
