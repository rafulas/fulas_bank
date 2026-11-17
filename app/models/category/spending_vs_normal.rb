# Fulas Bank: "Gasto frente a lo normal" in the Resumen. For the month the
# period ends in, each main category's spending against what is normal for
# it: the average of the six full months before (a month without spending
# counts as zero). While the month is still going, normal is what is usually
# spent by this day (the average times the share of the month gone by), so
# the 10th is not compared with a whole month.
#
# Counts as the Resumen does (Category::Analysis), net of refunds in the same
# category.
class Category::SpendingVsNormal
  MONTHS = 6
  # A category is above or below normal when it is at least this far from
  # it, both as a share and as an amount, so small amounts are not flagged.
  MIN_SHARE = BigDecimal("0.15")
  MIN_AMOUNT = 15

  Row = Data.define(:id, :name, :color, :spent, :normal, :month_average) do
    def difference
      spent - normal
    end

    def share
      normal.positive? ? difference / normal : nil
    end
  end

  attr_reader :family, :account_ids, :month, :today

  def initialize(family, account_ids:, month:, today: Date.current)
    @family = family
    @account_ids = account_ids
    @month = month.beginning_of_month
    @today = today
  end

  def currency
    family.currency
  end

  # Whether the month is still going: then normal is pro-rated.
  def in_progress?
    today.between?(month, month.end_of_month)
  end

  # The share of the month gone by (1 for a finished month).
  def elapsed
    return BigDecimal("1") unless in_progress?

    BigDecimal(today.day.to_s) / month.end_of_month.day
  end

  def rows
    @rows ||= begin
      current = current_analysis.spending_slices.index_by(&:id)
      averages = month_averages

      (current.keys | averages.keys).filter_map do |id|
        slice = current[id] || averages[id][:slice]
        average = averages.dig(id, :average) || 0.to_d
        spent = current[id]&.amount.to_d
        next if spent.zero? && average.zero?

        Row.new(id: id, name: slice.name, color: slice.color, spent: spent,
                normal: (average * elapsed).round(2), month_average: average.round(2))
      end
    end
  end

  def above
    rows.select { |row| notable?(row) && row.difference.positive? }.sort_by { |row| -row.difference }
  end

  def below
    rows.select { |row| notable?(row) && row.difference.negative? }.sort_by(&:difference)
  end

  def any?
    above.any? || below.any?
  end

  def spent
    rows.sum(&:spent)
  end

  def normal
    rows.sum(&:normal)
  end

  # Whether there is any history to compare with.
  def history?
    rows.any? { |row| row.month_average.positive? }
  end

  private
    def notable?(row)
      return false if row.difference.abs < MIN_AMOUNT
      return true if row.normal.zero?

      row.difference.abs >= row.normal * MIN_SHARE
    end

    def current_analysis
      last = in_progress? ? today : month.end_of_month
      Category::Analysis.new(family, period: Period.custom(start_date: month, end_date: last), account_ids: account_ids, today: today)
    end

    # { id => { slice:, average: } } over the six months before.
    def month_averages
      previous_end = month - 1
      analysis = Category::Analysis.new(family, period: Period.custom(start_date: month << MONTHS, end_date: previous_end),
                                                account_ids: account_ids, today: previous_end)
      bars = analysis.month_bars
      bars.flat_map(&:spending).group_by(&:id).transform_values do |slices|
        { slice: slices.first, average: slices.sum(&:amount) / bars.size }
      end
    end
end
