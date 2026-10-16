# Fulas Bank: FlowVista's "saved and invested": the money moved in a period
# from the everyday accounts to savings and investment accounts, net of what
# came back, and the share of income that is.
class SavingsFlow
  SAVINGS_SUBTYPES = %w[savings cd money_market].freeze
  INVESTING_TYPES = %w[Investment Crypto].freeze

  attr_reader :family, :user, :period, :income

  def initialize(family, user:, period:, income:)
    @family = family
    @user = user
    @period = period
    @income = income
  end

  def currency
    family.currency
  end

  def any_saving_accounts?
    saving_ids.any?
  end

  def saved
    @saved ||= transfers_total(into_savings: true)
  end

  def withdrawn
    @withdrawn ||= transfers_total(into_savings: false)
  end

  def net
    saved - withdrawn
  end

  # Net saved as a share of income, in percent; nil without income.
  def share_of_income
    return unless income.amount.positive?

    (net.amount / income.amount * 100).round(1)
  end

  private
    def accounts
      @accounts ||= family.accounts.visible.accessible_by(user).includes(:accountable).to_a
    end

    def saving_ids
      @saving_ids ||= accounts.select { |account| saving_account?(account) }.map(&:id)
    end

    def everyday_ids
      @everyday_ids ||= accounts.map(&:id) - saving_ids
    end

    def saving_account?(account)
      INVESTING_TYPES.include?(account.accountable_type) ||
        (account.accountable_type == "Depository" && SAVINGS_SUBTYPES.include?(account.subtype))
    end

    # Transfers from the everyday accounts into the savings ones
    # (`into_savings`), or back out of them, by the date money left.
    def transfers_total(into_savings:)
      return Money.new(0, currency) if saving_ids.empty? || everyday_ids.empty?

      from_ids, to_ids = into_savings ? [ everyday_ids, saving_ids ] : [ saving_ids, everyday_ids ]

      totals = Transfer.where.not(status: "rejected")
                       .joins("INNER JOIN entries outflow_entries ON outflow_entries.entryable_id = transfers.outflow_transaction_id AND outflow_entries.entryable_type = 'Transaction'")
                       .joins("INNER JOIN entries inflow_entries ON inflow_entries.entryable_id = transfers.inflow_transaction_id AND inflow_entries.entryable_type = 'Transaction'")
                       .where("outflow_entries.account_id IN (?)", from_ids)
                       .where("inflow_entries.account_id IN (?)", to_ids)
                       .where("outflow_entries.date BETWEEN ? AND ?", period.start_date, period.end_date)
                       .group("outflow_entries.currency")
                       .sum("transfers.amount")

      Money.new(totals.sum { |entry_currency, amount| converted(amount, entry_currency) }, currency)
    end

    def converted(amount, from_currency)
      return amount.to_d if from_currency == currency

      Money.new(amount, from_currency).exchange_to(currency).amount
    rescue Money::ConversionError
      amount.to_d
    end
end
