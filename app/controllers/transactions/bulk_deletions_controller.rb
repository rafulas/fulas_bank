class Transactions::BulkDeletionsController < ApplicationController
  def create
    # Exclude split children from bulk delete - they must be deleted via unsplit on parent
    # Only allow deletion from accounts where user has owner or full_control permission
    writable_account_ids = writable_accounts.pluck(:id)
    entries_scope = Current.family.entries
                      .where(account_id: writable_account_ids)
                      .where(parent_entry_id: nil)
    destroyed = entries_scope.destroy_by(id: with_transfer_partners(bulk_delete_params[:entry_ids]))
    destroyed.map(&:account).uniq.each(&:sync_later)
    redirect_back_or_to transactions_url, notice: "#{destroyed.count} transaction#{destroyed.count == 1 ? "" : "s"} deleted"
  end

  private
    # Fulas Bank: a transfer is one row in the list but two movements. Deleting
    # it deletes both, so the other account is not left with half of it.
    def with_transfer_partners(entry_ids)
      ids = Array(entry_ids).map(&:to_s)
      transaction_ids = Current.family.entries.where(id: ids, entryable_type: "Transaction").pluck(:entryable_id)
      return ids if transaction_ids.empty?

      legs = Transfer.where(inflow_transaction_id: transaction_ids)
                     .or(Transfer.where(outflow_transaction_id: transaction_ids))
                     .pluck(:inflow_transaction_id, :outflow_transaction_id).flatten
      ids | Current.family.entries.where(entryable_type: "Transaction", entryable_id: legs).pluck(:id).map(&:to_s)
    end

    def bulk_delete_params
      params.require(:bulk_delete).permit(entry_ids: [])
    end

    def writable_accounts
      Current.family.accounts.writable_by(Current.user)
    end
end
