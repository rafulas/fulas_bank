# Fulas Bank: "RoadTrip", the cars and motorbikes in one place (the vehicle
# accounts and their logbooks, whose data comes from the RoadTrip app).
class RoadtripsController < ApplicationController
  def show
    @vehicles = accessible_accounts.visible.where(accountable_type: "Vehicle").includes(:accountable).alphabetically.to_a
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t(".title"), nil ] ]
  end
end
