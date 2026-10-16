# Fulas Bank: ties a buy or a sale to the bank movement that paid for it, or
# unties it (see Trade::BankLink). The trade is reached by its entry, as in
# TradesController.
class Trades::BankLinksController < ApplicationController
  before_action :set_entry

  def create
    return unless require_account_permission!(@entry.account)

    bank_entry = visible_entries.find(params[:bank_entry_id])

    if @entry.trade.update(bank_entry: bank_entry)
      flash[:notice] = t(".success", name: bank_entry.account.name)
    else
      flash[:alert] = t(".error")
    end

    redirect_back_or_to account_path(@entry.account)
  end

  def destroy
    return unless require_account_permission!(@entry.account)

    @entry.trade.update!(bank_entry: nil)
    flash[:notice] = t(".success")

    redirect_back_or_to account_path(@entry.account)
  end

  private
    def set_entry
      @entry = visible_entries.where(entryable_type: "Trade").find(params[:trade_id])
    end

    def visible_entries
      Current.family.entries.joins(:account).merge(Account.accessible_by(Current.user))
    end
end
