# Fulas Bank: the panel at the top of the movements list, like Bilance's:
#   - the balance of the accounts the user chose to see there,
#   - the spending of each day of the last three weeks (two weeks ago, last
#     week and this one), stacked by main category,
#   - and the total balance of those accounts over the last 90 days.
#
# Which accounts it shows is the user's choice, kept in their preferences
# ("transactions_panel_account_ids"); until they choose, it shows their
# current accounts.
class Transaction::Panel
  WEEKS = 3
  BALANCE_DAYS = 90
  PREFERENCE_KEY = "transactions_panel_account_ids".freeze

  Segment = Data.define(:name, :color, :amount)
  Day = Data.define(:date, :segments) do
    def total
      segments.sum(&:amount)
    end
  end
  Week = Data.define(:start_date, :days) do
    def end_date
      start_date + 6
    end

    def total
      days.sum(&:total)
    end
  end

  attr_reader :family, :user, :today

  def initialize(family, user:, today: Date.current)
    @family = family
    @user = user
    @today = today
  end

  def currency
    family.currency
  end

  # Every account the user can see and could put in the panel.
  def selectable_accounts
    @selectable_accounts ||= family.accounts.accessible_by(user).visible.alphabetically.to_a
  end

  def accounts
    @accounts ||= begin
      chosen = user.transactions_panel_account_ids
      if chosen.nil?
        selectable_accounts.select { |account| account.accountable_type == "Depository" }
      else
        selectable_accounts.select { |account| chosen.include?(account.id) }
      end
    end
  end

  def weeks
    @weeks ||= begin
      first_monday = today.beginning_of_week(:monday) - (7 * (WEEKS - 1))
      spending = daily_spending(first_monday..today)

      WEEKS.times.map do |index|
        start_date = first_monday + (7 * index)
        days = (start_date..(start_date + 6)).map { |date| Day.new(date: date, segments: spending.fetch(date, [])) }
        Week.new(start_date: start_date, days: days)
      end
    end
  end

  # The highest day of the three weeks, so every bar shares one scale.
  def max_day_total
    @max_day_total ||= weeks.flat_map(&:days).map(&:total).max.to_d
  end

  # The chosen accounts together over the last 90 days (what is in them
  # minus what is owed on cards), for the line chart.
  def balance_series
    return nil if accounts.empty?

    Balance::ChartSeriesBuilder.new(
      account_ids: accounts.map(&:id),
      currency: currency,
      period: Period.custom(start_date: today - BALANCE_DAYS, end_date: today)
    ).balance_series
  end

  # The chosen accounts together today, in the family's currency: what is
  # in them minus what is owed on cards.
  def accounts_total
    Money.new(accounts.sum { |account| signed_balance(account) }, currency)
  end

  # The same total at the end of each of the last twelve weeks, oldest
  # first, as [date, amount] pairs for a small line.
  def weekly_balances
    return [] if accounts.empty?

    Balance::ChartSeriesBuilder.new(
      account_ids: accounts.map(&:id),
      currency: currency,
      period: Period.custom(start_date: today - 84, end_date: today),
      interval: "1 week"
    ).balance_series.values.map { |value| [ value.date, value.value.amount.to_d ] }
  end

  private
    def signed_balance(account)
      amount = account.currency == currency ? account.balance.to_d : account.balance_money.exchange_to(currency).amount
      account.liability? ? -amount : amount
    rescue Money::ConversionError
      account.liability? ? -account.balance.to_d : account.balance.to_d
    end

    # { date => [Segment] } with what was spent each day, by main category
    # (a subcategory counts in its parent), biggest first. Spending means
    # money going out that is not a transfer, nor in the Excluded or
    # Transfers categories, in any account the user can see.
    def daily_spending(range)
      rows = family.entries
                   .excluding_split_parents
                   .where(account_id: selectable_accounts.map(&:id), entryable_type: "Transaction", excluded: false, date: range)
                   .where("entries.amount > 0")
                   .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
                   .joins("LEFT JOIN categories panel_categories ON panel_categories.id = transactions.category_id")
                   .joins("LEFT JOIN categories panel_parents ON panel_parents.id = panel_categories.parent_id")
                   .where.not(transactions: { kind: Transaction::TRANSFER_KINDS })
                   .where("transactions.category_id IS NULL OR transactions.category_id NOT IN (#{Category::ANALYTICS_NEUTRAL_IDS_SQL})")
                   .group(:date, Arel.sql("COALESCE(panel_parents.name, panel_categories.name)"), Arel.sql("COALESCE(panel_parents.color, panel_categories.color)"))
                   .sum(:amount)

      rows.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |((date, name, color), amount), days|
        days[date.to_date] << Segment.new(
          name: name.presence || I18n.t("transactions.panel.uncategorized"),
          color: color.presence || Category::UNCATEGORIZED_COLOR,
          amount: amount.to_d
        )
      end.transform_values { |segments| segments.sort_by { |segment| -segment.amount } }
    end
end
