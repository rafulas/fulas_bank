# Fulas Bank: the "Préstamos" screen (see LoansOverview).
class LoansOverviewsController < ApplicationController
  def show
    @overview = LoansOverview.new(Current.family, user: Current.user)
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("loans_overviews.show.title"), nil ] ]
  end
end
