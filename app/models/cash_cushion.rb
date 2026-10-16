# Fulas Bank: FlowVista's "cash cushion": how many months of ordinary
# spending the money in the user's current and savings accounts would cover.
# Three to six months is the usual advice for an emergency fund.
class CashCushion
  RECOMMENDED_MONTHS = 3..6

  attr_reader :family, :user

  def initialize(family, user:)
    @family = family
    @user = user
  end

  def currency
    family.currency
  end

  # Cash in the depository accounts the user reaches, in the family currency.
  def cash
    @cash ||= Money.new(accounts.sum { |account| converted_balance(account) }, currency)
  end

  # A typical month's spending: the median of the months on record.
  def monthly_expense
    @monthly_expense ||= Money.new(IncomeStatement.new(family, user: user).median_expense(interval: "month").to_d, currency)
  end

  # Months covered, to one decimal; nil without spending to compare with.
  def months
    return unless monthly_expense.amount.positive?

    (cash.amount / monthly_expense.amount).round(1)
  end

  # :low under the recommended range, :ok within it, :high above it.
  def level
    return unless months

    if months < RECOMMENDED_MONTHS.min
      :low
    elsif months <= RECOMMENDED_MONTHS.max
      :ok
    else
      :high
    end
  end

  private
    def accounts
      @accounts ||= family.accounts.visible.included_in_reports.accessible_by(user).where(accountable_type: "Depository").to_a
    end

    def converted_balance(account)
      return account.balance.to_d if account.currency == currency

      account.balance_money.exchange_to(currency).amount
    rescue Money::ConversionError
      account.balance.to_d
    end
end
