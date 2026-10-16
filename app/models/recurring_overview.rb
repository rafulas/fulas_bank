# Fulas Bank: the "Recurrentes" page, after FlowVista's "Detected Recurring":
# every active recurring movement in one list, split into tabs — bills,
# subscriptions, income and savings — with what each kind adds up to a month.
#
#   - Income: series that bring money in.
#   - Savings: regular transfers into a savings or investment account (see
#     SavingsFlow.saving_account?).
#   - Subscriptions: what can be cancelled at will (bill type "subscription";
#     see SubscriptionsOverview).
#   - Bills: everything else that goes out — utilities, insurance, loans,
#     transfers to other accounts.
class RecurringOverview
  TABS = %w[all bills subscriptions income savings].freeze
  KINDS = TABS - %w[all]
  PRICE_CHANGE_MONTHS = 12

  Row = Data.define(:series, :kind, :amount, :monthly, :next_date, :price_change) do
    def name
      series.display_name
    end

    def income?
      kind == "income"
    end

    def price_up?
      price_change.present? && price_change.new_amount.abs > price_change.previous_amount.abs
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

  def self.kind_for(series)
    if series.typed_income? || (series.amount.to_d.negative? && !series.transfer?)
      "income"
    elsif series.transfer? && SavingsFlow.saving_account?(series.destination_account)
      "savings"
    elsif series.typed_subscription?
      "subscriptions"
    else
      "bills"
    end
  end

  def rows
    @rows ||= series_list.map { |series| build_row(series) }
                         .sort_by { |row| [ row.next_date || Date::Infinity.new, row.name.to_s ] }
  end

  def rows_for(tab)
    tab == "all" ? rows : rows.select { |row| row.kind == tab }
  end

  def count(tab)
    rows_for(tab).size
  end

  def monthly_total(kind)
    Money.new(rows_for(kind).sum(0.to_d) { |row| row.monthly.amount }, currency)
  end

  # What goes out every month for bills and subscriptions together.
  def fixed_costs
    monthly_total("bills") + monthly_total("subscriptions")
  end

  private
    def series_list
      family.recurring_transactions.accessible_by(user).active
            .includes(:merchant, :recurrence_rules, :recurring_price_changes, category: :parent, destination_account: :accountable)
            .to_a
    end

    def build_row(series)
      Row.new(
        series: series,
        kind: self.class.kind_for(series),
        amount: to_family_currency(series.amount_money.abs),
        monthly: to_family_currency(series.monthly_equivalent_amount.abs),
        next_date: series.next_due_date,
        price_change: series.recent_price_changes(1).first&.then { |change| change if change.effective_on >= today << PRICE_CHANGE_MONTHS }
      )
    end

    def to_family_currency(money)
      return money if money.currency.iso_code == currency

      money.exchange_to(currency)
    rescue Money::ConversionError
      Money.new(money.amount, currency)
    end
end
