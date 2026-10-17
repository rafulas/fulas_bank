# Fulas Bank: "Añadir a recurrente" (see RecurringAssignment), from a
# movement's detail or for every movement selected in the list: pick a
# series, or create one with its name and frequency, and they all become its
# payments.
class Transactions::RecurringAssignmentsController < ApplicationController
  def new
    @entry_ids = Array(params[:entry_ids]).compact_blank
    @standalone = @entry_ids.any?
    newest = annotatable_entries.where(id: @entry_ids).order(date: :desc).first
    @default_name = newest&.name
    @series = Current.family.recurring_transactions.accessible_by(Current.user).active
                     .includes(:merchant, :category)
                     .sort_by { |series| series.display_name.to_s.downcase }
  end

  def create
    entries = annotatable_entries.transactions.where(id: assignment_params[:entry_ids]).includes(:entryable)
    assignment = RecurringAssignment.new(
      family: Current.family,
      entries: entries,
      series_id: assignment_params[:series_id],
      name: assignment_params[:name],
      frequency: assignment_params[:frequency]
    )
    count = assignment.apply!

    if count.positive?
      notice = t(".success", count: count, name: assignment.series.display_name)
      notice = "#{notice} #{t(".skipped", count: assignment.skipped)}" if assignment.skipped.positive?
      redirect_back_or_to transactions_path, notice: notice
    else
      redirect_back_or_to transactions_path, alert: t(".nothing")
    end
  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_back_or_to transactions_path, alert: t(".failed")
  end

  private
    def assignment_params
      params.require(:recurring_assignment).permit(:series_id, :name, :frequency, entry_ids: [])
    end

    # Only movements of accounts the user may annotate.
    def annotatable_entries
      Current.family.entries.joins(:account).merge(Account.annotatable_by(Current.user))
    end
end
