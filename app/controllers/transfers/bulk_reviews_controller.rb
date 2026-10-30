# Fulas Bank: the transfers the app paired on its own («Auto»), confirmed or
# rejected several at a time from the movements list, instead of one by one.
class Transfers::BulkReviewsController < ApplicationController
  def create
    status = params.dig(:bulk_transfer, :status).to_s
    return head(:unprocessable_entity) unless %w[confirmed rejected].include?(status)

    transfers = pending_transfers
    Transfer.transaction do
      transfers.each { |transfer| status == "confirmed" ? transfer.confirm! : transfer.reject! }
    end
    transfers.each(&:sync_account_later) if status == "rejected"

    redirect_back_or_to transactions_url, notice: t(".#{status}", count: transfers.size)
  end

  private
    # The pending transfers behind the selected movements, in accounts the
    # user can write to on both sides.
    def pending_transfers
      writable = Current.family.accounts.writable_by(Current.user).pluck(:id)
      transaction_ids = Current.family.entries
                               .where(id: Array(params.dig(:bulk_transfer, :entry_ids)), account_id: writable, entryable_type: "Transaction")
                               .pluck(:entryable_id)

      Transfer.where(status: "pending")
              .where("inflow_transaction_id IN (:ids) OR outflow_transaction_id IN (:ids)", ids: transaction_ids)
              .includes(inflow_transaction: { entry: :account }, outflow_transaction: { entry: :account })
              .select { |transfer| [ transfer.inflow_transaction.entry.account_id, transfer.outflow_transaction.entry.account_id ].all? { |id| writable.include?(id) } }
              .uniq
    end
end
