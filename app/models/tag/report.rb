# What a tag adds up to, for the tag page: the total for a period, the
# breakdown by category, the last months month by month with their average,
# and the tagged transactions themselves.
#
# Amounts are signed the way people read them (expenses negative, income
# positive) and follow the same rules as the "Resumen" screen
# (Category::Summary): matched transfers and Excluido don't add to the total.
class Tag::Report
  MONTHS = 6
  TRANSACTIONS_LIMIT = 200

  Month = Data.define(:date, :total)

  attr_reader :tag, :family, :period

  def initialize(tag, period:, user:)
    @tag = tag
    @family = tag.family
    @period = period
    @user = user
  end

  def total
    counted_total(summary_for(period))
  end

  # Categories with tagged transactions in the period, largest first.
  def category_rows
    summary_for(period).rows.select { |row| row.total.nonzero? }
  end

  # The MONTHS calendar months ending with the period's last month.
  def months
    @months ||= begin
      last_month = period.end_date.beginning_of_month

      (MONTHS - 1).downto(0).map do |offset|
        start_date = last_month << offset
        month_period = Period.custom(start_date: start_date, end_date: start_date.end_of_month)
        Month.new(date: start_date, total: counted_total(summary_for(month_period)))
      end
    end
  end

  def average
    months.sum(&:total) / MONTHS
  end

  def months_total
    months.sum(&:total)
  end

  # Tagged transactions in the period, newest first.
  def transactions
    @transactions ||= search.transactions_scope
                            .reverse_chronological
                            .includes({ entry: :account }, :category, :merchant, :tags)
                            .limit(TRANSACTIONS_LIMIT)
                            .to_a
  end

  def transactions_count
    @transactions_count ||= search.transactions_scope.count
  end

  # Filters that open this tag and period in the Transactions page.
  def search_filters
    { tags: [ tag.name ], start_date: period.start_date.iso8601, end_date: period.end_date.iso8601 }
  end

  private
    def summary_for(a_period)
      @summaries ||= {}
      @summaries[[ a_period.start_date, a_period.end_date ]] ||=
        Category::Summary.new(family, period: a_period, account_ids: report_account_ids, tag: tag)
    end

    def counted_total(summary)
      summary.rows.reject(&:excluded?).sum(&:total)
    end

    def search
      @search ||= Transaction::Search.new(family, filters: search_filters, accessible_account_ids: accessible_account_ids)
    end

    def report_account_ids
      @report_account_ids ||= family.accounts.accessible_by(@user).included_in_reports.pluck(:id)
    end

    def accessible_account_ids
      @accessible_account_ids ||= @user.accessible_accounts.pluck(:id)
    end
end
