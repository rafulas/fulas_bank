# Fulas Bank: the funds held by participaciones (see InvestmentFund), added
# and edited from the Inversiones page.
class InvestmentFundsController < ApplicationController
  before_action :set_fund, only: %i[edit update destroy]

  def new
    @fund = Current.family.investment_funds.new(account: investment_accounts.first, price_date: Date.current)
  end

  def create
    @fund = Current.family.investment_funds.new

    if @fund.apply(fund_params)
      redirect_to investments_overview_path, notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @fund.apply(fund_params)
      redirect_to investments_overview_path, notice: t(".success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    account = @fund.account
    @fund.destroy!
    InvestmentFund.update_account_balance!(account) if Current.family.investment_funds.exists?(account: account)
    redirect_to investments_overview_path, notice: t(".success")
  end

  private
    def set_fund
      @fund = Current.family.investment_funds.where(account_id: investment_accounts.map(&:id)).find(params[:id])
    end

    def investment_accounts
      @investment_accounts ||= accessible_accounts.visible.where(accountable_type: "Investment").alphabetically.to_a
    end
    helper_method :investment_accounts

    # The account must be one of the user's investment accounts; anything
    # else is dropped and fails validation.
    def fund_params
      permitted = params.require(:investment_fund).permit(:name, :isin, :units, :price, :price_date, :cost)
      account_id = params.dig(:investment_fund, :account_id)
      return permitted if account_id.nil?

      permitted.merge(account: investment_accounts.find { |account| account.id == account_id.to_s })
    end
end
