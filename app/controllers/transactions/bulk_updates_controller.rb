class Transactions::BulkUpdatesController < ApplicationController
  def new
  end

  def create
    # Skip split parents from bulk update - update children instead.
    # Fulas Bank: transfers can now be selected (to confirm the «Auto» ones
    # at once) but are not edited here.
    entries = Current.family
                     .entries
                     .excluding_split_parents
                     .where(id: bulk_update_params[:entry_ids])
                     .where.not(entryable_id: Transfer.select(:inflow_transaction_id))
                     .where.not(entryable_id: Transfer.select(:outflow_transaction_id))
                     .includes(:entryable)

    updated = entries.bulk_update!(bulk_update_params, update_tags: tags_provided?)

    # Fulas Bank: recurring series, fixed/recurring/variable and excluded.
    classification = Transaction::BulkClassification.new(
      family: Current.family,
      entries: entries.reload,
      recurring: bulk_update_params[:recurring],
      expense_type: bulk_update_params[:expense_type],
      end_on: bulk_update_params[:end_on],
      excluded: bulk_update_params[:excluded]
    )
    updated = [ updated, classification.apply! ].max if classification.any_change?

    redirect_back_or_to transactions_path, notice: t(".success", count: updated)
  end

  private
    def bulk_update_params
      params.require(:bulk_update)
            .permit(:date, :notes, :name, :category_id, :merchant_id, :recurring, :expense_type, :end_on, :excluded,
                    entry_ids: [], tag_ids: [])
    end

    # Check if tag_ids was explicitly provided in the request.
    # This distinguishes between "user wants to update tags" vs "user didn't touch tags field".
    def tags_provided?
      bulk_update = params[:bulk_update]
      bulk_update.respond_to?(:key?) && bulk_update.key?(:tag_ids)
    end
end
