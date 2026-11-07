# Fulas Bank: the guided month close ("Cierre de octubre"). Once a month
# ends, a short checklist of what is still to do so its numbers are right,
# each step worked out from the data, so it ticks itself as things get done:
#
#   1. statements: every cash or card account kept by hand has movements up
#      to the last days of the month (statements are imported by hand);
#   2. balances: every investment, property, vehicle, loan or other account
#      kept by hand has had its balance updated since late in the month;
#   3. categorize: no movement of the month is left without a category;
#   4. duplicates: no charge of the month looks taken twice;
#   5. payments: no recurring payment of the month is still overdue;
#   6. recap: then the month's recap (Recap), to read; it is not ticked.
#
# Inicio offers it for the first days of the next month while anything is
# pending.
class MonthClose
  # Statements and balances count as up to date from this many days before
  # the month ends.
  STATEMENT_GRACE_DAYS = 5
  BALANCE_GRACE_DAYS = 7
  OFFER_DAYS = 10

  BALANCE_TYPES = %w[Investment Crypto Property Vehicle OtherAsset Loan OtherLiability].freeze

  # One account to act on in a step.
  Item = Data.define(:account, :last_date, :href_kind)

  Step = Data.define(:key, :count, :items) do
    def done?
      count.zero?
    end

    def checkable?
      key != :recap
    end
  end

  attr_reader :recap

  delegate :family, :user, :today, :start_date, :end_date, :title, to: :recap

  def self.latest(family, user:, today: Date.current)
    new(Recap.latest(family, user: user, kind: "month", today: today))
  end

  def initialize(recap)
    raise ArgumentError, "A month close needs a month" unless recap.month?

    @recap = recap
  end

  def to_param
    recap.to_param
  end

  def steps
    @steps ||= [
      Step.new(key: :statements, count: stale_statement_accounts.size, items: stale_statement_accounts),
      Step.new(key: :balances, count: stale_balance_accounts.size, items: stale_balance_accounts),
      Step.new(key: :categorize, count: uncategorized_count, items: []),
      Step.new(key: :duplicates, count: duplicate_pairs.size, items: []),
      Step.new(key: :payments, count: overdue_payments.size, items: []),
      Step.new(key: :recap, count: 0, items: [])
    ]
  end

  def checkable_steps
    steps.select(&:checkable?)
  end

  def pending_steps
    checkable_steps.reject(&:done?)
  end

  def done?
    pending_steps.empty?
  end

  def offer_on_inicio?
    recap.closed? && (today - end_date) <= OFFER_DAYS && !done?
  end

  def overdue_payments
    @overdue_payments ||= MonthPlan.new(family, user: user, month: start_date, today: today)
                                   .payments.select { |payment| payment.state == :overdue }
  end

  def duplicate_pairs
    @duplicate_pairs ||= DuplicateCharges.new(family, user: user, today: today)
                                         .pairs.select { |pair| (start_date..end_date).cover?(pair.first.date) }
  end

  private
    def range
      start_date..end_date
    end

    def manual_accounts
      @manual_accounts ||= family.accounts.accessible_by(user).writable_by(user).manual.where(status: "active").to_a
    end

    # Cash and card accounts whose last movement is older than the last days
    # of the month. An account that never had a movement is left alone.
    def stale_statement_accounts
      @stale_statement_accounts ||= begin
        accounts = manual_accounts.select { |account| account.accountable_type.in?(Account::MOVABLE_TRANSACTION_TYPES) }
        last_dates = Entry.where(account_id: accounts.map(&:id), entryable_type: "Transaction")
                          .where(date: ..today).group(:account_id).maximum(:date)

        accounts.filter_map do |account|
          last = last_dates[account.id]
          Item.new(account: account, last_date: last, href_kind: :import) if last && last < end_date - STATEMENT_GRACE_DAYS.days
        end.sort_by(&:last_date)
      end
    end

    # Accounts whose value is set by hand and was not updated late in the
    # month or after it.
    def stale_balance_accounts
      @stale_balance_accounts ||= begin
        accounts = manual_accounts.select { |account| account.accountable_type.in?(BALANCE_TYPES) }
        last_dates = Entry.where(account_id: accounts.map(&:id), entryable_type: "Valuation")
                          .where(date: ..today).group(:account_id).maximum(:date)

        accounts.filter_map do |account|
          last = last_dates[account.id]
          next if last && last >= end_date - BALANCE_GRACE_DAYS.days

          Item.new(account: account, last_date: last, href_kind: :valuation)
        end.sort_by { |item| item.last_date || Date.new(1900) }
      end
    end

    def uncategorized_count
      @uncategorized_count ||= family.entries
                                     .where(account_id: manual_and_linked_ids, date: range)
                                     .uncategorized_transactions.count
    end

    def manual_and_linked_ids
      family.accounts.accessible_by(user).pluck(:id)
    end
end
