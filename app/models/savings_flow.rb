# Fulas Bank: FlowVista's "saved and invested": the money moved in a period
# from the everyday accounts to savings and investment accounts, net of what
# came back, and the share of income that is. Pay that lands straight in a
# savings or investment account (a bonus in shares, a pension plan paid
# from payroll) counts as saved too: it is money that could have been taken
# as cash.
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

  # Investment and crypto accounts, and the savings kinds of depository one.
  def self.saving_account?(account)
    return false if account.nil?

    INVESTING_TYPES.include?(account.accountable_type) ||
      (account.accountable_type == "Depository" && SAVINGS_SUBTYPES.include?(account.subtype))
  end

  def currency
    family.currency
  end

  def any_saving_accounts?
    saving_ids.any?
  end

  def saved
    @saved ||= transfers_total(into_savings: true) + received_directly
  end

  # Income booked in the savings and investment accounts themselves: money
  # in that is not a transfer (dividends and interest are trades, not this).
  def received_directly
    @received_directly ||= begin
      return Money.new(0, currency) if saving_ids.empty?

      totals = family.entries
                     .where(account_id: saving_ids, entryable_type: "Transaction", excluded: false)
                     .where(date: period.start_date..period.end_date)
                     .where("entries.amount < 0")
                     .joins("INNER JOIN transactions t ON t.id = entries.entryable_id")
                     .where(t: { kind: "standard" })
                     .where("NOT EXISTS (SELECT 1 FROM transfers tr WHERE tr.inflow_transaction_id = t.id OR tr.outflow_transaction_id = t.id)")
                     .group("entries.currency")
                     .sum("entries.amount")

      Money.new(totals.sum { |entry_currency, amount| converted(-amount, entry_currency) }, currency)
    end
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
      @saving_ids ||= accounts.select { |account| self.class.saving_account?(account) }.map(&:id)
    end

    def everyday_ids
      @everyday_ids ||= accounts.map(&:id) - saving_ids
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
