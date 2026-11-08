# Fulas Bank: what reverting an import would delete, to say so before it is
# done (Import#revert).
#
# Reverting deletes the movements that came in with the import and, besides,
# every account the import created, whole: with all its movements, also those
# typed in by hand or brought by other imports later.
#
# Built for a page of imports at once (the Importaciones list), with a few
# grouped queries rather than one per row.
class Import::RevertImpact
  CreatedAccount = Data.define(:name, :entries_count)
  Impact = Data.define(:entries_count, :accounts) do
    def deletes_accounts?
      accounts.any?
    end
  end

  def initialize(imports)
    @imports = imports.to_a
  end

  # @return [Impact]
  def for(import)
    Impact.new(entries_count: entry_counts.fetch(import.id, 0), accounts: created_accounts.fetch(import.id, []))
  end

  private
    attr_reader :imports

    def ids
      @ids ||= imports.map(&:id)
    end

    def entry_counts
      @entry_counts ||= ids.empty? ? {} : Entry.where(import_id: ids).group(:import_id).count
    end

    def created_accounts
      @created_accounts ||= begin
        accounts = ids.empty? ? [] : Account.where(import_id: ids).order(:name).to_a
        counts = accounts.empty? ? {} : Entry.where(account_id: accounts.map(&:id)).group(:account_id).count

        accounts.group_by(&:import_id).transform_values do |list|
          list.map { |account| CreatedAccount.new(name: account.name, entries_count: counts.fetch(account.id, 0)) }
        end
      end
    end
end
