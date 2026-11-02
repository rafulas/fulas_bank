# Fulas Bank: turns the fixed balances («saldo fijado») of a current account
# or a card into «Ajuste de saldo» movements (see Account::BalanceAdjuster),
# so that from then on every movement moves the balance, as in Bilance,
# without changing any balance the account shows today.
#
# A fixed balance on a day was a reconciliation valuation: the balance at the
# end of that day was its amount, whatever that day's movements said. The
# jump it made is in the balance calculation as that day's cash adjustment
# (end balance - start balance - that day's movements). That jump becomes an
# adjustment movement of the same size on the same day, and the valuation
# goes. Walking forward again then lands on exactly the same balance every
# day from the account's first day on.
#
# Fixed balances dated before the account's opening balance did not move
# anything from the opening day on (the opening balance resets it there), so
# they are simply removed.
#
# Each account is checked before it is kept: its balances are worked out
# again with the adjustments and compared, day by day from the opening day,
# with the ones it had. If any differs by a cent, nothing is changed in that
# account and it keeps its fixed balances (reported in #skipped).
class Account::PinsToAdjustments
  TOLERANCE = BigDecimal("0.005")

  attr_reader :converted, :skipped

  def self.run(scope = Account.all)
    new.tap { |runner| runner.run(scope) }
  end

  def initialize
    @converted = []
    @skipped = []
  end

  def run(scope)
    scope.where(accountable_type: %w[Depository CreditCard]).find_each do |account|
      next unless Account::BalanceAdjuster.applies_to?(account)
      next unless pins(account).exists?

      convert(account)
    end
    self
  end

  # Converts one account. Returns whether it did.
  def convert(account)
    before = balances(account)
    jumps = before.index_by(&:date)

    # A savepoint of its own: a migration already runs inside a transaction,
    # and a plain nested one would swallow the rollback without undoing.
    Account.transaction(requires_new: true) do
      pins(account).includes(:entryable).order(:date).each do |pin|
        day = jumps[pin.date]
        if day && !before_opening?(account, pin.date)
          jump = day.cash_adjustments.to_d
          Account::BalanceAdjuster.new(account).write_adjustment(jump, pin.date) unless jump.zero?
        end
        pin.destroy!
      end

      account.reload
      unless same_balances?(account, before, balances(account))
        skipped << account
        raise ActiveRecord::Rollback
      end

      converted << account
    end

    converted.include?(account)
  ensure
    account.reload
  end

  private
    def pins(account)
      account.entries.where(entryable_type: "Valuation")
             .joins("INNER JOIN valuations ON valuations.id = entries.entryable_id")
             .where(valuations: { kind: "reconciliation" })
    end

    def balances(account)
      Balance::ForwardCalculator.new(account).calculate
    end

    def before_opening?(account, date)
      account.has_opening_anchor? && date < account.opening_anchor_date
    end

    # Every day from the opening day (or the first day when there is none)
    # must keep its balance.
    def same_balances?(account, before, after)
      from = account.has_opening_anchor? ? account.opening_anchor_date : nil
      after_by_date = after.index_by(&:date)

      before.all? do |row|
        next true if from && row.date < from

        other = after_by_date[row.date]
        other && (other.balance.to_d - row.balance.to_d).abs <= TOLERANCE
      end
    end
end
