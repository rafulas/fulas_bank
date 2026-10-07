class Vehicles::LogsController < Vehicles::BaseController
  TABS = { "fuel" => "refuels", "service" => "workshop", "expense" => "running_costs" }.freeze

  before_action :require_write_access!
  before_action :set_log, only: %i[edit update destroy]

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
