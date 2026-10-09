class Vehicles::MaintenanceItemsController < Vehicles::BaseController
  before_action :require_write_access!
  before_action :set_item, only: %i[edit update destroy]

  def new
    preset = Vehicle::MaintenanceItem::PRESETS.find { |candidate| candidate[:key] == params[:preset] }

    # Starts from the last time the logbook shows this job was done (a service
    # imported from RoadTrip, say), so its status is right from the start.
    last = @vehicle.logbook.last_log_matching(preset) if preset

    @item = @vehicle.maintenance_items.new(
      name: (t("vehicles.maintenance_items.presets.#{preset[:key]}") if preset),
      interval_km: preset&.dig(:interval_km),
      interval_months: preset&.dig(:interval_months),
      last_done_on: last&.date,
      last_done_odometer: last&.odometer
    )
    @prefilled_from = last
  end

  def create
    @item = @vehicle.maintenance_items.new(item_params)

    if @item.save
      redirect_to_tab "workshop", notice: t(".success")
    else
      render :new, formats: [ :html ], status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @item.update(item_params)
      redirect_to_tab "workshop", notice: t(".success")
    else
      render :edit, formats: [ :html ], status: :unprocessable_entity
    end
  end

  def destroy
    @item.destroy!
    redirect_to_tab "workshop", notice: t(".success")
  end

  private
    def set_item
      @item = @vehicle.maintenance_items.find(params[:id])
    end

    def item_params
      params.require(:vehicle_maintenance_item).permit(
        :name, :interval_km, :interval_months, :last_done_on, :last_done_odometer, :notes
      )
    end
end
