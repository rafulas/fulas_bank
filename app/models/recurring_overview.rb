# Fulas Bank: the "Recurrentes" page, after FlowVista's "Detected Recurring":
# every active recurring movement in one list, split into tabs by its kind
# (see RecurringTransaction::Kind), with what each kind adds up to a month.
#
#   - Fixed: the mortgage, loans, the salary, transfers to savings. They may
#     end (a loan after its last payment).
#   - Bills: essential services paid by direct debit (power, phone,
#     insurance), which can be switched off to change company.
#   - Subscriptions: what can be cancelled and taken up again at will.
#
# The bills and subscriptions switched off are listed apart, to switch them
# on again.
class RecurringOverview
  TABS = %w[all fixed bills subscriptions].freeze
  KINDS = TABS - %w[all]
  PRICE_CHANGE_MONTHS = 12
  # What a series' kind is called here.
  TAB_FOR_KIND = { "fixed" => "fixed", "bill" => "bills", "subscription" => "subscriptions" }.freeze

  Row = Data.define(:series, :kind, :amount, :monthly, :next_date, :price_change) do
    def name
      series.display_name
    end

    def income?
      series.amount.to_d.negative? && !series.transfer?
    end

    def price_up?
      price_change.present? && price_change.new_amount.abs > price_change.previous_amount.abs
    end

    # Every kind can be switched off and on: a rent left behind after a move
    # or a loan paid off early stops counting, like a cancelled subscription.
    def switchable?
      true
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
    TAB_FOR_KIND.fetch(series.fulas_kind)
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

  # What goes out every month for the series of a kind (income left out).
  def monthly_total(kind)
    Money.new(rows_for(kind).reject(&:income?).sum(0.to_d) { |row| row.monthly.amount }, currency)
  end

  # What the fixed income (the salary) brings every month.
  def monthly_income
    Money.new(rows.select(&:income?).sum(0.to_d) { |row| row.monthly.amount }, currency)
  end

  # What goes out every month for everything recurring.
  def fixed_costs
    KINDS.sum(Money.new(0, currency)) { |kind| monthly_total(kind) }
  end

  # The bills and subscriptions switched off (cancelled, or to change
  # company), to switch them on again; newest first.
  def switched_off(tab = "all")
    list = family.recurring_transactions.accessible_by(user).where(status: %w[paused inactive])
                 .where(bill_type: %w[bill subscription])
                 .includes(:merchant, category: :parent).order(updated_at: :desc).to_a
    tab == "all" ? list : list.select { |series| self.class.kind_for(series) == tab }
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
