# Fulas Bank: the family's plan to pay off its loans sooner (the debt
# reduction spreadsheet: "Calculator", "PaymentSchedule" and "Plan Reducc
# Deuda"). It keeps the choices; DebtPlan::Schedule does the sums.
#
# - `strategy`: which loan gets the extra money first (DebtPlan::Schedule).
# - `monthly_extra`: a fixed amount added every month on top of the payments.
# - `extra_payments`: one-off contributions, such as 15.000 € of the bonus
#   each March.
# - `loan_settings`, by loan account id: the custom order ("order"), a
#   payment to use instead of the loan's ("payment"), whether it is left out
#   of the plan ("excluded"), and the recurring movement that pays it today
#   ("recurring_transaction_id").
# - `feeds_forecast`: when on, the Forecast takes the plan's payments, from
#   `account` (the main account by default), instead of the recurring
#   movements linked to the loans.
class DebtPlan < ApplicationRecord
  belongs_to :family
  belongs_to :account, optional: true
  has_many :extra_payments, -> { order(:date) }, class_name: "DebtPlan::ExtraPayment", dependent: :destroy, inverse_of: :debt_plan

  validates :strategy, inclusion: { in: DebtPlan::Schedule::STRATEGIES }
  validates :monthly_extra, numericality: { greater_than_or_equal_to: 0 }
  validate :account_belongs_to_family

  # The loans the user can see, each with what the plan needs from it.
  def loan_accounts(user)
    family.accounts.accessible_by(user).visible.where(accountable_type: "Loan")
          .includes(:accountable).order(:created_at).to_a
  end

  def setting(account, name)
    loan_settings.fetch(account.id, {})[name.to_s]
  end

  def excluded?(account)
    ActiveModel::Type::Boolean.new.cast(setting(account, :excluded)) || false
  end

  # The usual monthly payment: the one typed in the plan, else the loan's
  # (the payment typed in the loan, or the one worked out from its terms).
  def payment_for(account)
    typed = setting(account, :payment).presence
    return typed.to_d if typed

    loan = account.accountable
    return loan.payment_amount.to_d if loan.payment_amount.present?

    calculated = loan.monthly_payment&.amount&.to_d
    calculated if calculated&.positive?
  end

  def order_for(account)
    setting(account, :order).presence&.to_i
  end

  def recurring_transaction_for(account)
    id = setting(account, :recurring_transaction_id).presence
    family.recurring_transactions.find_by(id: id) if id
  end

  # Replaces the per-loan settings with those of the form, only for the given
  # loans and keys.
  def assign_loan_settings(accounts, params)
    params = params.to_h.stringify_keys
    own_series = family.recurring_transactions.pluck(:id).to_set
    self.loan_settings = accounts.to_h do |account|
      values = params.fetch(account.id, {}).to_h.stringify_keys.slice("order", "payment", "excluded", "recurring_transaction_id")
      values.delete("recurring_transaction_id") unless own_series.include?(values["recurring_transaction_id"])
      values.delete("excluded") unless ActiveModel::Type::Boolean.new.cast(values["excluded"])
      [ account.id, values.compact_blank ]
    end.compact_blank
  end

  def schedule(user, today: Date.current, strategy: self.strategy, with_extras: true)
    DebtPlan::Schedule.new(
      loans: schedule_loans(user),
      strategy: strategy,
      start: today.next_month.beginning_of_month,
      monthly_extra: with_extras ? monthly_extra : 0,
      extra_payments: with_extras ? extra_payments_by_month(today) : {}
    )
  end

  def schedule_loans(user)
    loan_accounts(user).reject { |account| excluded?(account) }.map do |account|
      DebtPlan::Schedule::Loan.new(
        key: account.id,
        name: account.name,
        balance: account.balance.to_d.abs,
        rate: account.accountable.interest_rate.to_d,
        payment: payment_for(account).to_d,
        order: order_for(account)
      )
    end
  end

  # { first day of a month => contributions that month }, from next month
  # on, with the yearly repeats.
  def extra_payments_by_month(today = Date.current)
    extra_payments.each_with_object(Hash.new(BigDecimal(0))) do |payment, totals|
      payment.dates.each do |date|
        totals[date.beginning_of_month] += payment.amount.to_d if date > today.end_of_month
      end
    end
  end

  # The recurring movements the plan's payments replace in the Forecast.
  def replaced_recurring_ids(user)
    loan_accounts(user).reject { |account| excluded?(account) }
                       .filter_map { |account| setting(account, :recurring_transaction_id).presence }
  end

  # What the Forecast needs to show the plan's payments, or nil when the plan
  # does not feed it.
  def forecast_feed(user, today: Date.current)
    return unless feeds_forecast?

    accounts = loan_accounts(user).reject { |account| excluded?(account) }
    DebtPlan::ForecastFeed.new(
      schedule: schedule(user, today: today),
      account_id: account_id,
      replaced_recurring_ids: replaced_recurring_ids(user),
      loan_names: accounts.to_h { |account| [ account.id, account.name ] },
      payment_days: accounts.to_h { |account| [ account.id, payment_day_for(account) ] },
      extra_payments: extra_payments.to_a
    )
  end

  # The day of the month the loan is paid: the loan's own, else the day of
  # its recurring movement, else the 1st.
  def payment_day_for(account)
    account.accountable.payment_day.presence ||
      recurring_transaction_for(account)&.expected_day_of_month.presence || 1
  end

  private
    def account_belongs_to_family
      errors.add(:account, :invalid) if account && account.family_id != family_id
    end
end
