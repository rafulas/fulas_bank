module HoldingsHelper
  # Fulas Bank: the price shown as "current market price" (see
  # Security#current_price_record). Asking the provider can fail (network,
  # rate limits); the drawer then shows "Unknown" instead of an error.
  def current_price_record_for(security)
    security.current_price_record
  rescue StandardError => e
    Rails.logger.error("Error fetching current price for security #{security.id}: #{e.message}")
    nil
  end
end
