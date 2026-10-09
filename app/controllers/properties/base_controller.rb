# Shared setup for the property's expense screens. Routes are nested under the
# property account (property_path takes the account, like the other
# accountable resources), so :property_id is the account id.
class Properties::BaseController < ApplicationController
  include AccountAuthorizable, StreamExtensions

  before_action :set_account

  private
    def set_account
      @account = accessible_accounts.where(accountable_type: "Property").find(params[:property_id])
      @property = @account.property
    end

    def require_write_access!
      require_account_permission!(@account)
    end

    def redirect_to_expenses(notice:)
      path = account_path(@account, tab: "expenses")

      respond_to do |format|
        format.html { redirect_to path, notice: notice }
        format.turbo_stream { stream_redirect_to(path, notice: notice) }
      end
    end
end
