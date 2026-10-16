# Fulas Bank: what to do when a security has no price from the market data
# provider.
#
# A security is "offline" when, the day it was created, no provider found it
# (for example because Yahoo Finance was not set up yet, or did not answer).
# Offline securities are never asked for prices again, so a share like
# BBVA.MC would show "Unknown" for ever. Two ways out:
#
#   - #try_bring_online! asks the enabled providers again and, if one of them
#     knows the ticker, puts the security back online with that provider.
#   - #set_manual_price! stores a price typed by the user for a day. Holdings
#     carry the last known price forward, so the position is worth
#     shares x that price from that day on, until a newer price arrives.
module Security::ManualPricing
  extend ActiveSupport::Concern

  # Asks every enabled provider for today's price of this ticker. When one
  # answers (in the expected currency, if one is given), the security goes
  # back online with that provider and the daily price import picks it up.
  #
  # The currency check matters: a bare ticker can be another listing of the
  # same name (BBVA is the bank's ADR in New York, in dollars; BBVA.MC is the
  # Madrid share, in euros).
  #
  # @param currency [String, nil] the currency the holding is in
  # @return [Boolean] whether the security is now online
  def try_bring_online!(currency: nil)
    return true unless offline?
    return false if cash?

    self.class.providers.compact.each do |provider|
      response = provider.fetch_security_price(
        symbol: ticker,
        exchange_operating_mic: exchange_operating_mic,
        date: Date.current
      )
      next unless response.success?

      price = response.data
      next unless price&.price.to_d.positive?
      next if currency.present? && price.currency.present? && price.currency.to_s.upcase != currency.to_s.upcase

      update!(
        offline: false,
        offline_reason: nil,
        failed_fetch_count: 0,
        failed_fetch_at: nil,
        price_provider: provider.class.name.demodulize.underscore
      )
      return true
    rescue StandardError => e
      Rails.logger.warn("Could not bring #{ticker} online with #{provider.class.name}: #{e.class} - #{e.message}")
    end

    false
  end

  # Stores the price the user typed for a day (today by default). It replaces
  # whatever price that day had, and is kept until a provider brings a newer
  # day, or the user syncs the prices again.
  #
  # @return [Security::Price]
  def set_manual_price!(amount, currency:, date: Date.current)
    amount = amount.to_d
    raise ArgumentError, "Price must be positive" unless amount.positive?

    record = prices.find_or_initialize_by(date: date, currency: currency.to_s.upcase)
    record.update!(price: amount, manual: true, provisional: false)
    @current_price = nil
    record
  end

  # The most recent stored price on or before a day: what the holding is
  # valued at when the day itself has none (weekends, or a price typed by
  # hand a few days ago).
  #
  # @return [Security::Price, nil]
  def latest_price(on: Date.current)
    prices.where(date: ..on).order(date: :desc).first
  end
end
