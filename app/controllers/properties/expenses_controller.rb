# A property's costs (renovations, insurance, mortgage...), each tied to the
# bank charge that paid for it. Mirrors Vehicles::LogsController.
class Properties::ExpensesController < Properties::BaseController
  before_action :require_write_access!
  before_action :set_expense, only: %i[edit update destroy]

  # The "Bank charge" options for the date and amount being typed in the form.
  def bank_charges
    expense = params[:expense_id].present? ? @property.expenses.find(params[:expense_id]) : @property.expenses.new
    expense.date = parsed_date(params[:date]) || expense.date
    amount = params[:amount].to_s.tr(",", ".")
    expense.amount = amount.to_d if amount.match?(/\A\d+(\.\d+)?\z/)
    expense.entry = Current.accessible_entries.find_by(id: params[:selected]) if params[:selected].present?

    render partial: "properties/expenses/bank_charge_options", locals: { expense: expense }
  end

  # Also opened from a bank movement ("Link to my home"), with that charge
  # already chosen: `entry_id` fills in the date, amount and charge.
  def new
    kind = Property::Expense::KINDS.include?(params[:kind]) ? params[:kind] : "other"
    @expense = @property.expenses.new(kind: kind, date: Date.current, currency: @account.currency)

    if (entry = linkable_entry(params[:entry_id]))
      if (match = AssetLinker.new(@account.family).match_for(@account, kind, entry))
        return redirect_to edit_property_expense_path(@account, match, entry_id: entry.id)
      end

      @expense.assign_attributes(entry: entry, date: entry.date, amount: entry.amount.abs, notes: entry.name)
    end
  end

  def create
    @expense = @property.expenses.new(expense_params)
    @expense.attachments.attach(attachment_files) if attachment_files.any?

    if @expense.save
      redirect_to_expenses notice: t(".success")
    else
      render :new, formats: [ :html ], status: :unprocessable_entity
    end
  end

  # Opened from a bank movement for an expense that already exists: the
  # charge comes preselected, and is saved with the rest of the form.
  def edit
    if (entry = linkable_entry(params[:entry_id])) && @expense.entry_id.nil?
      @expense.entry = entry
      @linking_entry = entry
    end
  end

  # Saving the form confirms a link the app had proposed.
  def update
    kept = @expense.attachments.map(&:id)
    @expense.assign_attributes(expense_params.merge(suggestion: nil))
    @expense.attachments.attach(attachment_files) if attachment_files.any?

    if @expense.save
      redirect_to_expenses notice: t(".success")
    else
      @expense.attachments.select { |attachment| attachment.persisted? && kept.exclude?(attachment.id) }.each(&:purge)
      render :edit, formats: [ :html ], status: :unprocessable_entity
    end
  end

  def destroy
    @expense.destroy!
    redirect_to_expenses notice: t(".success")
  end

  private
    def parsed_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    def set_expense
      @expense = @property.expenses.find(params[:id])
    end

    # Only the user's own transactions can be linked: an id from another
    # family or an unshared account is dropped.
    def linkable_entry(id)
      return if id.blank?

      Current.accessible_entries.where(entryable_type: "Transaction").find_by(id: id)
    end

    def attachment_files
      @attachment_files ||= Array(params.dig(:property_expense, :attachments)).select { |file| file.respond_to?(:read) }
    end

    def expense_params
      permitted = params.require(:property_expense).permit(:kind, :date, :amount, :entry_id, :notes)
      permitted[:entry_id] = linkable_entry(permitted[:entry_id])&.id if permitted.key?(:entry_id)
      permitted.merge(currency: @account.currency)
    end
end
