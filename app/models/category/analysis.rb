# Fulas Bank: everything the "Resumen" screen shows around its list of
# categories, like Bilance's:
#   - what was spent and earned in the period, by main category (the two
#     rings), the total and the savings rate;
#   - the tags with the most spending;
#   - a calendar of the period's last month, with each day's total and what
#     it went on;
#   - the merchants where the most was spent;
#   - the last six months, income up and spending down, by main category,
#     and their average;
#   - the average daily spending of the period, by main category.
#
# What counts is the same as in Category::Summary: the user's accounts
# included in reports, leaving out matched transfers, the Excluded and
# Transfers categories, and movements excluded by hand. A subcategory counts
# in its main category. Amounts are in the family's currency.
class Category::Analysis
  MONTHS = 6
  TOP_TAGS = 5
  TOP_MERCHANTS = 10
  TOP_DAILY_CATEGORIES = 4

  # One main category (or "uncategorized") with what it adds up to.
  Slice = Data.define(:id, :name, :color, :amount)
  CalendarDay = Data.define(:date, :total, :slices) do
    # Spending of the day, positive (net of any income that day).
    def spent
      -total
    end
  end
  MonthBar = Data.define(:month, :income, :spending)

  attr_reader :family, :period, :account_ids, :today

  def initialize(family, period:, account_ids:, today: Date.current)
    @family = family
    @period = period
    @account_ids = account_ids
    @today = today
  end

  def currency
    family.currency
  end

  def start_date
    period.date_range.begin
  end

  def end_date
    [ period.date_range.end, today ].min
  end

  # ---- The two rings ----

  def spending_slices
    @spending_slices ||= slices_by_category(start_date..end_date, :spending)
  end

  def income_slices
    @income_slices ||= slices_by_category(start_date..end_date, :income)
  end

  def spent
    money(spending_slices.sum(&:amount))
  end

  def income
    money(income_slices.sum(&:amount))
  end

  # Income minus spending.
  def net
    income - spent
  end

  # Share of the income left after spending, as a whole percentage (zero
  # with no income or when spending was higher).
  def savings_rate
    return 0 unless income.amount.positive?

    [ ((income.amount - spent.amount) / income.amount * 100).round, 0 ].max
  end

  # ---- Tags ----

  # [ [Tag, spending], ... ] with the most spending first (net, positive).
  def tag_totals
    @tag_totals ||= begin
      totals = base_scope(start_date..end_date)
                 .joins("INNER JOIN taggings tg ON tg.taggable_type = 'Transaction' AND tg.taggable_id = t.id")
                 .group("tg.tag_id")
                 .sum(Arel.sql(converted_amount_sql))
      tags = family.tags.where(id: totals.keys).index_by(&:id)

      totals.filter_map { |tag_id, amount| [ tags[tag_id], amount.to_d ] if tags[tag_id] }
            .sort_by { |_, amount| -amount.abs }
    end
  end

  def top_tags
    tag_totals.first(TOP_TAGS)
  end

  # ---- Calendar ----

  # The month the calendar shows: the period's last one.
  def calendar_month
    end_date.beginning_of_month
  end

  # Every day of that month inside the period, with what was spent (net)
  # and by main category, biggest first. Days after today are left empty.
  def calendar_days
    @calendar_days ||= begin
      range = [ calendar_month, start_date ].max..[ calendar_month.end_of_month, end_date ].min
      rows = base_scope(range)
               .joins(category_joins_sql)
               .group(Arel.sql("entries.date"), *category_group_sql)
               .sum(Arel.sql(converted_amount_sql))

      by_day = rows.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |((date, id, name, color), amount), days|
        days[date.to_date] << build_slice(id, name, color, -amount.to_d)
      end

      (calendar_month..calendar_month.end_of_month).map do |date|
        slices = range.cover?(date) ? by_day[date].sort_by { |slice| slice.amount } : []
        CalendarDay.new(date: date, total: slices.sum(&:amount), slices: slices)
      end
    end
  end

  # ---- Merchants ----

  # [ [name, spending], ... ] with the most spending first. Movements with no
  # merchant count under their own name, as in the movements list.
  def merchant_totals
    @merchant_totals ||= base_scope(start_date..end_date)
                           .where("entries.amount > 0")
                           .joins("LEFT JOIN merchants m ON m.id = t.merchant_id")
                           .group(Arel.sql("COALESCE(m.name, entries.name)"))
                           .sum(Arel.sql(converted_amount_sql))
                           .map { |name, amount| [ name, amount.to_d ] }
                           .sort_by { |_, amount| -amount }
  end

  def top_merchants
    merchant_totals.first(TOP_MERCHANTS)
  end

  # ---- Last six months ----

  def month_bars
    @month_bars ||= begin
      months = (0...MONTHS).map { |back| end_date.beginning_of_month << back }.reverse
      range = months.first..end_date
      rows = base_scope(range)
               .joins(category_joins_sql)
               .group(Arel.sql("date_trunc('month', entries.date)"), *category_group_sql)
               .group(Arel.sql("entries.amount < 0"))
               .sum(Arel.sql(converted_amount_sql))

      income = Hash.new { |hash, key| hash[key] = [] }
      spending = Hash.new { |hash, key| hash[key] = [] }
      rows.each do |(month, id, name, color, inflow), amount|
        target = inflow ? income : spending
        target[month.to_date] << build_slice(id, name, color, amount.to_d.abs)
      end

      months.map do |month|
        MonthBar.new(month: month, income: merge_slices(income[month]), spending: merge_slices(spending[month]))
      end
    end
  end

  # The highest income or spending of any of the months, for one scale.
  def month_bars_max
    month_bars.flat_map { |bar| [ bar.income.sum(&:amount), bar.spending.sum(&:amount) ] }.max.to_d
  end

  # Average result (income minus spending) of the six months.
  def month_bars_average
    return money(0) if month_bars.empty?

    money(month_bars.sum { |bar| bar.income.sum(&:amount) - bar.spending.sum(&:amount) } / month_bars.size)
  end

  # ---- Average daily spending ----

  def days_elapsed
    [ (end_date - start_date).to_i + 1, 1 ].max
  end

  def daily_average
    money(spent.amount / days_elapsed)
  end

  # [ main categories with the most daily spending, what the rest add up to ]
  def daily_average_slices
    top = spending_slices.first(TOP_DAILY_CATEGORIES).map { |slice| slice.with(amount: slice.amount / days_elapsed) }
    rest = spending_slices.drop(TOP_DAILY_CATEGORIES)
    [ top, rest.size, money(rest.sum(&:amount) / days_elapsed) ]
  end

  private
    def money(amount)
      Money.new(amount, currency)
    end

    # Transactions that count, in the user's accounts and the date range,
    # with `t` for the transaction and `rates` for the exchange rate.
    def base_scope(range)
      family.entries
            .excluding_split_parents
            .where(account_id: account_ids, entryable_type: "Transaction", excluded: false, date: range)
            .joins("INNER JOIN transactions t ON t.id = entries.entryable_id")
            .joins(ActiveRecord::Base.sanitize_sql_array([
              "LEFT JOIN exchange_rates rates ON (rates.date = entries.date AND rates.from_currency = entries.currency AND rates.to_currency = ?)",
              currency
            ]))
            .where(Transaction.counts_by_kind_sql("t"))
            .where("t.category_id IS NULL OR t.category_id NOT IN (#{Category::ANALYTICS_NEUTRAL_IDS_SQL})")
    end

    def converted_amount_sql
      "entries.amount * COALESCE(rates.rate, 1)"
    end

    def category_joins_sql
      "LEFT JOIN categories c ON c.id = t.category_id LEFT JOIN categories parent_c ON parent_c.id = c.parent_id"
    end

    def category_group_sql
      [
        Arel.sql("COALESCE(parent_c.id, c.id)"),
        Arel.sql("COALESCE(parent_c.name, c.name)"),
        Arel.sql("COALESCE(parent_c.color, c.color)")
      ]
    end

    def build_slice(id, name, color, amount)
      Slice.new(
        id: id || "uncategorized",
        name: name.presence || I18n.t("category_summaries.analysis.uncategorized"),
        color: color.presence || Category::UNCATEGORIZED_COLOR,
        amount: amount
      )
    end

    # Spending (positive) or income (positive) by main category, biggest
    # first. A category whose net goes the other way (refunds bigger than
    # spending) counts on the other side.
    def slices_by_category(range, side)
      rows = base_scope(range)
               .joins(category_joins_sql)
               .group(*category_group_sql)
               .sum(Arel.sql(converted_amount_sql))

      rows.filter_map do |(id, name, color), amount|
        value = side == :spending ? amount.to_d : -amount.to_d
        build_slice(id, name, color, value) if value.positive?
      end.sort_by { |slice| -slice.amount }
    end

    def merge_slices(slices)
      slices.group_by(&:id).map do |_, same|
        same.first.with(amount: same.sum(&:amount))
      end.sort_by { |slice| -slice.amount }
    end
end
