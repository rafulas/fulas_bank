require "test_helper"

class Transaction::CategorySuggesterTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
    @physio = @family.categories.create!(name: "Fisio sugerencia", color: "#4da568")
    @health = @family.categories.create!(name: "Salud sugerencia", color: "#4da568")
    @suggester = Transaction::CategorySuggester.new(@family, scope: Entry.where(account_id: @family.accounts.select(:id)))
  end

  test "matches names that only differ in case, digits and punctuation" do
    spend("FISIO GARCIA 03/11", @physio)
    spend("Fisio Garcia - 17/10", @physio)

    suggestion = @suggester.suggest(name: "fisio garcia 2026-11-17")

    assert_equal @physio, suggestion.category
    assert_equal 2, suggestion.count
  end

  test "the most used category wins, and a split one is not suggested" do
    2.times { spend("Farmacia Centro", @health) }
    spend("Farmacia Centro", @physio)

    assert_equal @health, @suggester.suggest(name: "FARMACIA CENTRO").category
    assert_equal [ @health, @physio ], @suggester.ranked(name: "farmacia centro").map(&:category)

    # Two, two and one: none has half of them.
    spend("Farmacia Centro", @physio)
    spend("Farmacia Centro", @family.categories.create!(name: "Otra sugerencia", color: "#4da568"))
    assert_nil @suggester.suggest(name: "farmacia centro")
  end

  test "only movements in the same direction count" do
    spend("Seguro Sanitas", @health)
    @account.entries.create!(name: "Seguro Sanitas", date: Date.current, amount: -45, currency: "USD",
                             entryable: Transaction.new(category: @physio))

    assert_equal @health, @suggester.suggest(name: "Seguro Sanitas").category
    assert_equal @physio, @suggester.suggest(name: "Seguro Sanitas", inflow: true).category
  end

  test "movements older than two years do not count" do
    spend("Clinica Antigua", @physio, date: Date.current - 3.years)

    assert_nil @suggester.suggest(name: "Clinica Antigua")
  end

  test "a movement is suggested from the others, not itself" do
    spend("Fisio Garcia", @physio)
    entry = @account.entries.create!(name: "FISIO GARCIA", date: Date.current, amount: 55, currency: "USD", entryable: Transaction.new)

    assert_equal @physio, @suggester.suggest_for(entry).category
  end

  private
    def spend(name, category, date: Date.current - 1)
      @account.entries.create!(name: name, date: date, amount: 55, currency: "USD", entryable: Transaction.new(category: category))
    end
end
