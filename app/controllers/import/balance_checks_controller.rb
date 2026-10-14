# Fulas Bank: the balance check shown once an import is done (see
# Import::BalanceCheck). It lives in its own frame on the import's success
# page, which reloads itself while balances are being recalculated.
class Import::BalanceChecksController < ApplicationController
  include AccountAuthorizable

  before_action :set_balance_check
  before_action :set_account, only: %i[update adjust]

  def show
    render partial: "import/balance_checks/balance_check", locals: { balance_check: @balance_check }
  end

  def update
    amount = params.dig(:balance_check, :amount).to_s.strip
    if amount.match?(/\A-?\d+(\.\d+)?\z/)
      @balance_check.record!(@account, BigDecimal(amount))
      redirect_to import_balance_check_path(@import)
    else
      redirect_to import_balance_check_path(@import), alert: t(".invalid_amount")
    end
  end

  def adjust
    return unless require_account_permission!(@account, redirect_path: import_path(@import))

    if @balance_check.adjust!(@account)
      redirect_to import_balance_check_path(@import), notice: t(".adjusted", account: @account.name)
    else
      redirect_to import_balance_check_path(@import), alert: t(".not_adjusted")
    end
  end

  private
    def set_balance_check
      @import = Current.family.imports.find(params[:import_id])
      @balance_check = Import::BalanceCheck.new(@import, user: Current.user)
      raise ActiveRecord::RecordNotFound unless @balance_check.available?
    end

    def set_account
      @account = @balance_check.accounts.find { |account| account.id == params[:account_id] }
      raise ActiveRecord::RecordNotFound if @account.nil?
    end
end
