# Fulas Bank's "Resumen": what was spent and earned in each category for a
# period, with the analysis around it (see Category::Analysis), and, for one
# category, the breakdown by subcategory.
class CategorySummariesController < ApplicationController
  include Periodable

  def index
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("category_summaries.index.title"), nil ] ]
    @summary = build_summary
    @analysis = Category::Analysis.new(Current.family, period: @period, account_ids: report_account_ids)
  end

  def show
    @category = Current.family.categories.roots.find(params[:id])
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("category_summaries.index.title"), category_summaries_path ], [ @category.name, nil ] ]
    @summary = build_summary
    @own_row, @subcategory_rows = @summary.breakdown(@category)
  end

  private
    # The Resumen opens on the current month; a period picked in it applies
    # to that visit (and, as elsewhere, becomes the user's default period).
    def set_period
      if params[:period].blank? && params[:start_date].blank?
        @period = Period.current_month_for(Current.family)
      else
        super
      end
    end

    def build_summary
      Category::Summary.new(Current.family, period: @period, account_ids: report_account_ids)
    end

    def report_account_ids
      @report_account_ids ||= Current.family.accounts.accessible_by(Current.user).included_in_reports.pluck(:id)
    end
end
