# Fulas Bank: the "Inversiones" screen (see InvestmentsOverview).
class InvestmentsOverviewsController < ApplicationController
  def show
    @overview = InvestmentsOverview.new(Current.family, user: Current.user)
    # Fulas Bank: the year's sales and what they gained (average cost and FIFO).
    @realized = InvestmentsOverview::RealizedGains.new(Current.family, user: Current.user, year: params[:year])
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("investments_overviews.show.title"), nil ] ]
  end

  # Fetches today's prices of every share held (see
  # InvestmentsOverview::PriceRefresh) and comes back to the screen.
  def refresh_prices
    overview = InvestmentsOverview.new(Current.family, user: Current.user)
    result = InvestmentsOverview::PriceRefresh.new(overview).run

    flash_type, message =
      if result.nothing_to_do?
        [ :notice, t(".nothing") ]
      elsif result.failed.empty?
        [ :notice, t(".success", count: result.updated.size) ]
      else
        [ :alert, t(".partial", count: result.updated.size, failed: result.failed.join(", ")) ]
      end

    redirect_to investments_overview_path, flash_type => message
  end
end
