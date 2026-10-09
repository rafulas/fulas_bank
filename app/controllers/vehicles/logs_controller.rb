class Vehicles::LogsController < Vehicles::BaseController
  TABS = { "fuel" => "refuels", "service" => "workshop", "expense" => "running_costs" }.freeze

  before_action :require_write_access!
  before_action :set_log, only: %i[edit update destroy]

  # The "Bank charge" options for the date and amount being typed in the
  # form, so the suggestions follow the log rather than the day it was opened.
  def bank_charges
    log = params[:log_id].present? ? @vehicle.logs.find(params[:log_id]) : @vehicle.logs.new
    log.date = parsed_date(params[:date]) || log.date
    amount = params[:amount].to_s.tr(",", ".")
    log.amount = amount.to_d if amount.match?(/\A\d+(\.\d+)?\z/)
    log.entry = Current.accessible_entries.find_by(id: params[:selected]) if params[:selected].present?

    render partial: "vehicles/logs/bank_charge_options", locals: { log: log }
  end

  # Also opened from a bank movement ("Link to my car"), with that charge
  # already chosen: `entry_id` fills in the date, amount and charge.
  def new
    kind = Vehicle::Log::KINDS.include?(params[:kind]) ? params[:kind] : "fuel"
    category = Vehicle::Log::CATEGORIES.include?(params[:category]) ? params[:category] : "other"

    @log = @vehicle.logs.new(
      kind: kind,
      date: Date.current,
      currency: @account.currency,
      maintenance_item_id: params[:maintenance_item_id].presence,
      category: (category if kind == "expense"),
      odometer: @vehicle.logbook.odometer
    )

    if (entry = linkable_entry(params[:entry_id]))
      # A refuel already typed for those days takes the charge instead of a
      # second, duplicate one.
      if (match = AssetLinker.new(@account.family).match_for(@account, kind, entry))
        return redirect_to edit_vehicle_log_path(@account, match, entry_id: entry.id)
      end

      @log.assign_attributes(entry: entry, date: entry.date, amount: entry.amount.abs)
      @log.notes = entry.name unless @log.fuel?
    end
  end

  def create
    @log = @vehicle.logs.new(log_params)
    @log.attachments.attach(attachment_files) if attachment_files.any?

    if @log.save
      redirect_to_tab TABS.fetch(@log.kind), notice: t(".success")
    else
      render :new, formats: [ :html ], status: :unprocessable_entity
    end
  end

  # Opened from a bank movement for a record that already exists: the charge
  # comes preselected, and is saved with the rest of the form.
  def edit
    if (entry = linkable_entry(params[:entry_id])) && @log.entry_id.nil?
      @log.entry = entry
      @linking_entry = entry
    end
  end

  # Saving the form confirms a link the app had proposed.
  def update
    kept = @log.attachments.map(&:id)
    @log.assign_attributes(log_params.merge(suggestion: nil))
    @log.attachments.attach(attachment_files) if attachment_files.any?

    if @log.save
      redirect_to_tab TABS.fetch(@log.kind), notice: t(".success")
    else
      # A file that was already stored before the record was rejected (an
      # unchanged record saves its new attachments at once) goes again.
      @log.attachments.select { |attachment| attachment.persisted? && kept.exclude?(attachment.id) }.each(&:purge)
      render :edit, formats: [ :html ], status: :unprocessable_entity
    end
  end

  def destroy
    @log.destroy!
    redirect_to_tab TABS.fetch(@log.kind), notice: t(".success")
  end

  private
    def parsed_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    def set_log
      @log = @vehicle.logs.find(params[:id])
    end

    def linkable_entry(id)
      return if id.blank?

      Current.accessible_entries.where(entryable_type: "Transaction").find_by(id: id)
    end

    # Invoices and receipts chosen in the form, added to the ones the log has.
    def attachment_files
      @attachment_files ||= Array(params.dig(:vehicle_log, :attachments)).select { |file| file.respond_to?(:read) }
    end

    # The linked bank charge is looked up among the transactions this user can
    # see, so an id from another family or an unshared account is dropped.
    def log_params
      permitted = params.require(:vehicle_log).permit(
        :kind, :date, :odometer, :quantity, :unit_price, :amount, :full_tank,
        :category, :maintenance_item_id, :entry_id, :notes
      )

      permitted[:entry_id] = linkable_entry(permitted[:entry_id])&.id if permitted.key?(:entry_id)

      permitted.merge(currency: @account.currency)
    end
end
