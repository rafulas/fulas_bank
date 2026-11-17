# Fulas Bank: what was spent at each merchant ("Comercios"), counted as in
# the Resumen (Category::Analysis#base_scope): a movement's merchant, or its
# own name when it has none, so imported movements without a merchant still
# group. Amounts are in the family's currency.
#
#   list         every merchant of the period, most spent first.
#   detail(name) one merchant: its totals in the period, the last twelve
#                months, its categories and its latest movements.
class MerchantActivity
  NAME_SQL = "COALESCE(m.name, entries.name)".freeze
  MERCHANT_JOIN_SQL = "LEFT JOIN merchants m ON m.id = t.merchant_id".freeze
  # The amount in the family's currency, as Category::Analysis#converted_amount_sql.
  AMOUNT_SQL = "entries.amount * COALESCE(rates.rate, 1)".freeze
  MONTHS = 12
  LATEST = 30

  # One merchant in the list. `spent` is spending net of what came back;
  # `refunded` what came back.
  Row = Data.define(:name, :spent, :refunded, :count, :last_date) do
    def average
      count.zero? ? 0.to_d : spent / count
    end
  end

  Month = Data.define(:month, :spent)
  CategoryShare = Data.define(:category, :spent)

  Detail = Data.define(:name, :row, :months, :categories, :entries, :first_date) do
    # Average spending of the months with any.
    def monthly_average
      active = months.select { |month| month.spent.positive? }
      active.empty? ? 0.to_d : active.sum(&:spent) / active.size
    end

    def months_max
      months.map(&:spent).max.to_d
    end
  end

  attr_reader :family, :period, :account_ids, :today

  def initialize(family, period:, account_ids:, today: Date.current)
    @family = family
    @period = period
    @account_ids = account_ids
    @today = today
    @analysis = Category::Analysis.new(family, period: period, account_ids: account_ids, today: today)
  end

  def currency
    family.currency
  end

  def range
    @analysis.start_date..@analysis.end_date
  end

  # [ Row, ... ] with the most spent first. A merchant that only brought
  # money in (a refund, a sale) goes last. `search` narrows it by name.
  def list(search: nil)
    scope = named_scope(range)
    scope = scope.where("#{NAME_SQL} ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(search.to_s.strip)}%") if search.present?

    rows_from(scope.group(Arel.sql(NAME_SQL))).sort_by { |row| [ -row.spent, row.name.to_s.downcase ] }
  end

  # The merchant with this name, or nil when it has no movement at all.
  def detail(name)
    totals = rows_from(named_scope(range).where("#{NAME_SQL} = ?", name).group(Arel.sql(NAME_SQL))).first
    first_date = named_scope(nil).where("#{NAME_SQL} = ?", name).minimum("entries.date")
    return if first_date.nil?

    Detail.new(
      name: name,
      row: totals || Row.new(name: name, spent: 0.to_d, refunded: 0.to_d, count: 0, last_date: nil),
      months: months_for(name),
      categories: categories_for(name),
      entries: latest_entries(name),
      first_date: first_date
    )
  end

  private
    def named_scope(range)
      scope = range ? @analysis.base_scope(range) : @analysis.base_scope(Entry.min_supported_date..today)
      scope.joins(MERCHANT_JOIN_SQL)
    end

    def rows_from(grouped)
      grouped.pluck(
        Arel.sql(NAME_SQL),
        Arel.sql("SUM(#{AMOUNT_SQL})"),
        Arel.sql("SUM(CASE WHEN entries.amount < 0 THEN -#{AMOUNT_SQL} ELSE 0 END)"),
        Arel.sql("COUNT(*) FILTER (WHERE entries.amount > 0)"),
        Arel.sql("MAX(entries.date)")
      ).map do |name, net, refunded, count, last_date|
        Row.new(name: name, spent: [ net.to_d, 0.to_d ].max, refunded: refunded.to_d, count: count.to_i, last_date: last_date)
      end
    end

    def months_for(name)
      last = today.beginning_of_month
      months = (0...MONTHS).map { |back| last << back }.reverse
      sums = named_scope(months.first..today).where("#{NAME_SQL} = ?", name)
                                             .group(Arel.sql("date_trunc('month', entries.date)"))
                                             .sum(Arel.sql(AMOUNT_SQL))
                                             .transform_keys(&:to_date)
      months.map { |month| Month.new(month: month, spent: [ sums[month].to_d, 0.to_d ].max) }
    end

    def categories_for(name)
      sums = named_scope(range).where("#{NAME_SQL} = ?", name).group("t.category_id").sum(Arel.sql(AMOUNT_SQL))
      categories = family.categories.where(id: sums.keys.compact).index_by(&:id)
      sums.filter_map do |category_id, amount|
        next unless amount.to_d.positive?

        CategoryShare.new(category: categories[category_id], spent: amount.to_d)
      end.sort_by { |share| -share.spent }
    end

    def latest_entries(name)
      ids = named_scope(nil).where("#{NAME_SQL} = ?", name).reorder(date: :desc, created_at: :desc).limit(LATEST).pluck(:id)
      Entry.where(id: ids).includes(:account, recurring_allocations: { recurring_occurrence: :recurring_transaction },
                                    entryable: [ :tags, { category: :parent } ])
           .order(date: :desc, created_at: :desc).to_a
    end
end
