# Fulas Bank: "Comercios", a tab of the Resumen: what was spent at each
# merchant in a period, and the page of one merchant (MerchantActivity).
class MerchantActivitiesController < ApplicationController
  include Periodable

  def index
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("merchant_activities.index.title"), nil ] ]
    @activity = build_activity
    @search = params[:search].to_s.strip.first(100)
    @rows = @activity.list(search: @search)
  end

  def show
    @activity = build_activity
    @detail = @activity.detail(params[:name].to_s)
    raise ActiveRecord::RecordNotFound unless @detail

    @breadcrumbs = [
      [ t("breadcrumbs.home"), root_path ],
      [ t("merchant_activities.index.title"), merchant_activities_path(period: @period.key.presence) ],
      [ @detail.name, nil ]
    ]
  end

  private
    # Like the Resumen, it opens on the current month.
    def set_period
      if params[:period].blank? && params[:start_date].blank?
        @period = Period.current_month_for(Current.family)
      else
        super
      end
    end

    def build_activity
      account_ids = Current.family.accounts.accessible_by(Current.user).included_in_reports.pluck(:id)
      MerchantActivity.new(Current.family, period: @period, account_ids: account_ids)
    end
end
