# Fulas Bank: proposes the bank movement of each buy or sale in an investment
# account without brokerage cash (see Trade::BankLink), so the user only has
# to confirm it, as AssetLinker does for the car and the house.
#
# A trade is proposed the movement that best fits it among the ones
# Trade::BankLink#bank_entry_candidates offers (money out for a buy, money in
# for a sale, ten days either side), but only when its amount is close to
# the trade's: shares received with the pay are booked for exactly what they
# cost, and a broker's fee is a small part of the amount. A movement the user
# turned down for that account is never proposed again.
#
# It looks at the whole history: there are few trades, and the shares of a
# bonus go back years.
class TradeLinker
  # How far the movement's amount may be from the trade's, as a share of it.
  AMOUNT_TOLERANCE = BigDecimal("0.02")

  # Run after imports, syncs and rules: a failure here must never break them.
  def self.run_quietly(family)
    new(family).run!
  rescue => error
    Rails.logger.error("TradeLinker failed for family #{family.id}: #{error.message}")
    # Fulas Bank: visible in Ajustes › Registro de depuración, not only the log.
    DebugLogEntry.capture(
      category: "linkers", level: "error", source: "TradeLinker", family: family,
      message: "TradeLinker failed: #{error.class}: #{error.message}",
      metadata: { backtrace: Array(error.backtrace).first(5) }
    )
    Sentry.capture_exception(error) if defined?(Sentry)
    0
  end

  attr_reader :family

  def initialize(family)
    @family = family
  end

  # @return [Integer] how many trades were given a proposal
  def run!
    taken = Set.new
    count = 0

    unlinked_trades.each do |trade|
      match = best_match(trade, taken)
      next unless match

      trade.update!(bank_entry: match, bank_entry_suggested: true)
      taken << match.id
      count += 1
    end

    count
  end

  # The movement to propose for a trade, if one is close enough.
  def best_match(trade, taken = Set.new)
    target = trade.entry.amount.to_d.abs
    return if target.zero?

    rejected = rejected_entry_ids(trade.entry.account_id)

    trade.bank_entry_candidates(scope: family.entries).find do |candidate|
      next false if taken.include?(candidate.id) || rejected.include?(candidate.id)

      (candidate.amount.to_d.abs - target).abs <= target * AMOUNT_TOLERANCE
    end
  end

  private
    # Buys and sales of the family's accounts without brokerage cash that
    # have no movement yet, oldest first.
    def unlinked_trades
      Trade.joins(entry: :account)
           .includes(entry: :account)
           .where(accounts: { family_id: family.id, accountable_type: "Investment" })
           .where(accounts: { accountable_id: Investment.where(brokerage_cash: false).select(:id) })
           .where(bank_entry_id: nil, entries: { excluded: false })
           .where.not(qty: 0)
           .order("entries.date ASC")
           .to_a
    end

    def rejected_entry_ids(account_id)
      @rejected ||= AssetLinkRejection.where(account_id: family.accounts.select(:id)).pluck(:account_id, :entry_id)
                                      .group_by(&:first).transform_values { |pairs| pairs.map(&:last).to_set }
      @rejected.fetch(account_id, Set.new)
    end
end
