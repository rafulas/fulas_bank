# Shared setup for the vehicle logbook screens. Routes are nested under the
# vehicle account (vehicle_path takes the account, like the other accountable
# resources), so :vehicle_id is the account id.
class Vehicles::BaseController < ApplicationController
  include AccountAuthorizable, StreamExtensions

  before_action :set_account

  private
    def set_account
      @account = accessible_accounts.where(accountable_type: "Vehicle").find(params[:vehicle_id])
      @vehicle = @account.vehicle
    end

    def require_write_access!
      require_account_permission!(@account)
    end

    def redirect_to_tab(tab, notice:)
      path = account_path(@account, tab: tab)

      respond_to do |format|
        format.html { redirect_to path, notice: notice }
        format.turbo_stream { stream_redirect_to(path, notice: notice) }
      end
    end
end
