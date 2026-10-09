class Tag::DropdownsController < ApplicationController
  def show
    @entry = Current.accessible_entries.where(entryable_type: "Transaction").find(params[:entry_id])
    @transaction = @entry.transaction
    @recent_tags, @other_tags = Current.family.tags.recent_and_rest
    @selected_tag_ids = @transaction.tag_ids.to_set
  end
end
