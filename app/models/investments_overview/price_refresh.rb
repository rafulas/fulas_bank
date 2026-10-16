# Fulas Bank: the "Actualizar precios" button of the Inversiones screen. It
# does for every share the user holds what the "Actualizar" button inside a
# single position does: fetch the last month of closing prices from the
# market data provider (Yahoo Finance) and recalculate the value of the
# accounts that hold it.
#
# Shares no provider found ("offline") are asked for again and skipped if
# still unknown, and so are the funds held by participaciones, whose valor
# liquidativo the user types.
class InvestmentsOverview::PriceRefresh
  LOOKBACK_DAYS = 31

  Result = Data.define(:updated, :failed) do
    def nothing_to_do?
      updated.empty? && failed.empty?
    end
  end

  attr_reader :overview

  # @param overview [InvestmentsOverview] the accounts the user can see
  def initialize(overview)
    @overview = overview
  end

  # @return [Result] the tickers updated and the ones the provider failed on
  def run
    updated = []
    failed = []
    refreshed_ids = []

    securities.each do |security|
      count, _error = security.import_provider_prices(
        start_date: LOOKBACK_DAYS.days.ago.to_date,
        end_date: Date.current,
        clear_cache: true
      )

      if count.to_i.positive?
        updated << security.ticker
        refreshed_ids << security.id
      else
        failed << security.ticker
      end
    end

    recalculate(refreshed_ids) if refreshed_ids.any?

    Result.new(updated: updated, failed: failed)
  end

  private
    def holdings_by_account
      @holdings_by_account ||= overview.rows.to_h do |row|
        [ row.account, row.account.current_holdings.includes(:security).to_a ]
      end
    end

    # Fulas Bank: a share no provider found when it was created is asked for
    # again first (Security#try_bring_online!), so it joins the refresh as
    # soon as Yahoo Finance knows it.
    def securities
      holdings = holdings_by_account.values.flatten
      holdings.map(&:security).compact.uniq.select do |security|
        next true unless security.offline?
        next false if security.cash?

        currency = holdings.find { |holding| holding.security_id == security.id }&.currency
        security.try_bring_online!(currency: currency)
      end
    end

    # Each account recalculated once, only for the shares it holds that
    # changed, as the per-position button does.
    def recalculate(security_ids)
      holdings_by_account.each do |account, holdings|
        ids = holdings.map(&:security_id) & security_ids
        next if ids.empty?

        strategy = account.linked? ? :reverse : :forward
        Balance::Materializer.new(account, strategy: strategy, security_ids: ids).materialize_balances
      end
    end
end
