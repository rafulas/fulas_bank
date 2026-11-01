# Fulas Bank: brings a position to the number of shares the user says it
# has. The difference becomes an operation of its own on the chosen day
# ("Ajuste de acciones"), at the price given, zero by default: shares
# received without paying for them (a bonus issue, shares from the
# employer...) lower the average cost and the gain counts them as such.
# Fewer shares than now take shares out the same way.
class Holding::ShareAdjustment
  attr_reader :holding, :shares, :date, :price, :errors

  def initialize(holding, shares:, date: Date.current, price: nil)
    @holding = holding
    @shares = parse(shares)
    @date = date
    @price = parse(price) || 0.to_d
    @errors = []
  end

  # What the new operation adds (negative: takes out).
  def difference
    shares ? shares - holding.qty.to_d : 0.to_d
  end

  # @return [Entry, nil] the operation, or nil with nothing to change or an error
  def apply!
    @errors << :invalid if shares.nil? || shares.negative? || price.negative? || date.nil? || date > Date.current
    return if errors.any? || difference.zero?

    entry = account.entries.create!(
      name: I18n.t("holdings.share_adjustment.name", ticker: holding.ticker, difference: format_difference),
      date: date,
      amount: difference * price,
      currency: holding.currency,
      entryable: Trade.new(qty: difference, price: price, fee: 0, currency: holding.currency,
                           security: holding.security, investment_activity_label: "Other")
    )
    entry.lock_saved_attributes!
    account.sync_later
    entry
  end

  private
    def account
      holding.account
    end

    def format_difference
      formatted = difference.to_s("F").sub(/\.0+\z/, "")
      difference.positive? ? "+#{formatted}" : formatted
    end

    def parse(value)
      return if value.blank?

      value.to_s.strip.tr(",", ".").to_d
    rescue ArgumentError
      nil
    end
end
