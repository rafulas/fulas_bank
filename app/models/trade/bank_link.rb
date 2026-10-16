# Fulas Bank: the bank movement that paid for a buy, or received the money of
# a sale, in an investment account without brokerage cash
# (Account#brokerage_cash?).
#
# Such an account holds no money: a buy is paid from a current account (or,
# for shares received with the pay, from the account where the payslip is
# recorded) and a sale is paid into one. The money is already in those
# accounts, imported from the bank; the link just ties both sides together,
# so each one shows the other and nothing is counted twice:
#   - the investment account is worth its shares (the trade adds or removes
#     them, with no cash);
#   - the bank account has the money movement, with its own category.
#
# A bank movement pays for one trade at most.
module Trade::BankLink
  extend ActiveSupport::Concern

  # Movements up to this many days either side of the trade are offered: a
  # broker can take a couple of days to settle, and a bonus paid in shares is
  # booked around payday rather than on the day the shares arrive.
  MATCH_WINDOW = 10.days
  MATCH_LIMIT = 10

  included do
    belongs_to :bank_entry, class_name: "Entry", optional: true

    validates :bank_entry_id, uniqueness: true, allow_nil: true
    validate :bank_entry_fits
  end

  # Only buys and sales of an account without brokerage cash: a dividend or an
  # interest payment moves no shares, and an account with cash of its own
  # already records where its money comes from.
  def bank_linkable?
    entry.present? && qty.to_d.nonzero? && !entry.account.brokerage_cash?
  end

  # The bank movements this trade could be linked to: money out for a buy,
  # money in for a sale, in another account, around the trade's date, and not
  # linked to another trade yet. The closest amount comes first, then the
  # closest date.
  #
  # @param scope [ActiveRecord::Relation<Entry>] the entries the user can see
  # @return [Array<Entry>]
  def bank_entry_candidates(scope:)
    return [] unless bank_linkable?

    trade_entry = entry
    target = trade_entry.amount.to_d.abs
    direction = buy? ? "entries.amount > 0" : "entries.amount < 0"

    candidates = scope.where(entryable_type: "Transaction", excluded: false)
                      .excluding_split_parents
                      .where.not(account_id: trade_entry.account_id)
                      .where(date: (trade_entry.date - MATCH_WINDOW)..(trade_entry.date + MATCH_WINDOW))
                      .where(direction)
                      .where.not(id: Trade.where.not(bank_entry_id: nil).where.not(id: id).select(:bank_entry_id))
                      .includes(:account)
                      .limit(200)
                      .to_a

    candidates.sort_by do |candidate|
      amount_gap = target.positive? ? (candidate.amount.to_d.abs - target).abs / target : 0
      [ amount_gap, (candidate.date - trade_entry.date).abs ]
    end.first(MATCH_LIMIT)
  end

  private
    def bank_entry_fits
      return if bank_entry.blank?

      account = entry&.account
      if account.nil? || account.brokerage_cash? ||
         !bank_entry.transaction? ||
         bank_entry.account_id == account.id ||
         bank_entry.account.family_id != account.family_id
        errors.add(:bank_entry, :invalid)
      end
    end
end
