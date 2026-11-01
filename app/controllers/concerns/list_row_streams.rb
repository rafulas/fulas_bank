# Fulas Bank: answers a change made from the movements list in place. The
# rows it touched are drawn again where they are (or taken out), the bulk
# drawer closes and the notice shows, without loading the page again: a
# reload brings only the first block of the list, so the blocks loaded by
# scrolling went away and the list jumped back up.
#
# A plain request (no Turbo) still goes back to the page it came from.
module ListRowStreams
  extend ActiveSupport::Concern

  private
    # `changed`: entries to draw again; `removed`: entries no longer there.
    # Set the flash before calling.
    def respond_with_list_rows(changed: [], removed: [], fallback: transactions_path)
      respond_to do |format|
        format.turbo_stream do
          @accessible_account_ids ||= Current.user.accessible_accounts.pluck(:id)
          rows = Entry.where(id: changed.map(&:id)).includes(:account, :entryable).to_a
          streams = rows.map { |entry| turbo_stream.replace(helpers.dom_id(entry), partial: "entries/entry", locals: { entry: entry }) }
          streams += removed.map { |entry| turbo_stream.remove(helpers.dom_id(entry)) }
          streams << turbo_stream.update("bulk_transaction_edit_drawer", "")
          render turbo_stream: streams + flash_notification_stream_items
        end
        format.html { redirect_back_or_to fallback }
      end
    end
end
