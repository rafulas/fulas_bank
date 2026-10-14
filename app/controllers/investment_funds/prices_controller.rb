# Fulas Bank: typing the latest valor liquidativo of every fund at once, the
# usual routine every week or so.
class InvestmentFunds::PricesController < ApplicationController
  def edit
    @funds = funds
    @date = Date.current
  end

  def update
    date = parse_date(params[:date]) || Date.current
    prices = params.fetch(:prices, {})
    updated = funds.select do |fund|
      value = prices[fund.id].to_s.strip.tr(",", ".")
      next false unless value.match?(/\A\d+(\.\d+)?\z/) && value.to_d.positive?

      fund.record_price!(value.to_d, date: date)
      true
    end

    updated.map(&:account).uniq.each { |account| InvestmentFund.update_account_balance!(account) }
    redirect_to investments_overview_path, notice: t(".success", count: updated.size)
  end

  private
    def funds
      accounts = accessible_accounts.visible.where(accountable_type: "Investment")
      Current.family.investment_funds.where(account: accounts).includes(:account).alphabetically.to_a
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end
end
