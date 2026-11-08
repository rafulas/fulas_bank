require "test_helper"

class Import::RevertImpactTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @import = imports(:transaction)
    @import.update_columns(status: "complete")
    @checking = accounts(:depository)
  end

  test "counts the movements of the import and the accounts it created, whole" do
    2.times { |i| @checking.entries.create!(name: "Importado #{i}", date: Date.current, amount: 10, currency: "USD", import: @import, entryable: Transaction.new) }

    created = @family.accounts.create!(name: "Cuenta Fake BBVA Nómina", balance: 0, currency: "USD", import: @import, accountable: Depository.new)
    created.entries.create!(name: "De la importación", date: Date.current, amount: 5, currency: "USD", import: @import, entryable: Transaction.new)
    created.entries.create!(name: "A mano", date: Date.current, amount: 7, currency: "USD", entryable: Transaction.new)

    impact = Import::RevertImpact.new([ @import, imports(:trade) ]).for(@import)

    assert_equal 3, impact.entries_count
    assert impact.deletes_accounts?
    assert_equal [ [ "Cuenta Fake BBVA Nómina", 2 ] ], impact.accounts.map { |account| [ account.name, account.entries_count ] }

    other = Import::RevertImpact.new([ @import, imports(:trade) ]).for(imports(:trade))
    assert_equal 0, other.entries_count
    assert_not other.deletes_accounts?
  end

  test "an import is recent for a week" do
    @import.updated_at = 6.days.ago
    assert @import.recent?
    @import.updated_at = 8.days.ago
    assert_not @import.recent?
  end
end
