# Fulas Bank's "Resumen": what was spent and earned in each category for a
# period, with the analysis around it (see Category::Analysis), and, for one
# category, the breakdown by subcategory.
class CategorySummariesController < ApplicationController
  include Periodable

  def index
    @summary = build_summary
    @analysis = Category::Analysis.new(Current.family, period: @period, account_ids: report_account_ids)
  end

  def show
    @category = Current.family.categories.roots.find(params[:id])
    @summary = build_summary
    @own_row, @subcategory_rows = @summary.breakdown(@category)
  end

  private
    def build_summary
      Category::Summary.new(Current.family, period: @period, account_ids: report_account_ids)
    end

    def report_account_ids
      @report_account_ids ||= Current.family.accounts.accessible_by(Current.user).included_in_reports.pluck(:id)
    end
end
