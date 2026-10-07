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

  def new
    kind = Vehicle::Log::KINDS.include?(params[:kind]) ? params[:kind] : "fuel"

    @log = @vehicle.logs.new(
      kind: kind,
      date: Date.current,
      currency: @account.currency,
      maintenance_item_id: params[:maintenance_item_id].presence,
      category: ("other" if kind == "expense"),
      odometer: @vehicle.logbook.odometer
    )
  end

  def create
    @log = @vehicle.logs.new(log_params)

    if @log.save
      redirect_to_tab TABS.fetch(@log.kind), notice: t(".success")
    else
      render :new, formats: [ :html ], status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @log.update(log_params)
      redirect_to_tab TABS.fetch(@log.kind), notice: t(".success")
    else
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

    # The linked bank charge is looked up among the transactions this user can
    # see, so an id from another family or an unshared account is dropped.
    def log_params
      permitted = params.require(:vehicle_log).permit(
        :kind, :date, :odometer, :quantity, :unit_price, :amount, :full_tank,
        :category, :maintenance_item_id, :entry_id, :notes
      )

      if permitted.key?(:entry_id)
        entry_id = permitted[:entry_id].presence
        permitted[:entry_id] = entry_id && Current.accessible_entries.where(entryable_type: "Transaction").find_by(id: entry_id)&.id
      end

      permitted.merge(currency: @account.currency)
    end
end
