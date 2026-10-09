class VehiclesController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes(
    :id, :make, :model, :year, :mileage_value, :mileage_unit, :fuel_type, :license_plate,
    :purchase_price, :purchase_date
  )
end
