# Fulas Bank: the "Inversiones" screen (see InvestmentsOverview).
class InvestmentsOverviewsController < ApplicationController
  def show
    @overview = InvestmentsOverview.new(Current.family, user: Current.user)
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("investments_overviews.show.title"), nil ] ]
  end
end
