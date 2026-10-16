# Fulas Bank: ties a buy or a sale to the bank movement that paid for it, or
# unties it (see Trade::BankLink). The trade is reached by its entry, as in
# TradesController.
#
# The app also proposes links on its own (TradeLinker): the user confirms
# them, one by one or all at once, or turns them down.
class Trades::BankLinksController < ApplicationController
  before_action :set_entry, except: :confirm_all

  def create
    return unless require_account_permission!(@entry.account)

    bank_entry = visible_entries.find(params[:bank_entry_id])

    if @entry.trade.update(bank_entry: bank_entry, bank_entry_suggested: false)
      flash[:notice] = t(".success", name: bank_entry.account.name)
    else
      flash[:alert] = t(".error")
    end

    redirect_back_or_to account_path(@entry.account)
  end

  def destroy
    return unless require_account_permission!(@entry.account)

    @entry.trade.update!(bank_entry: nil, bank_entry_suggested: false)
    flash[:notice] = t(".success")

    redirect_back_or_to account_path(@entry.account)
  end

  def confirm
    return unless require_account_permission!(@entry.account)

    @entry.trade.update!(bank_entry_suggested: false)
    redirect_back_or_to account_path(@entry.account), notice: t(".success")
  end

  # Turned down: the movement is never proposed again for this account.
  def reject
    return unless require_account_permission!(@entry.account)

    trade = @entry.trade
    if trade.bank_entry_id
      AssetLinkRejection.find_or_create_by!(entry_id: trade.bank_entry_id, account_id: @entry.account_id)
    end
    trade.update!(bank_entry: nil, bank_entry_suggested: false)

    redirect_back_or_to account_path(@entry.account), notice: t(".success")
  end

  # Every proposal of the accounts the user may change.
  def confirm_all
    trades = Trade.joins(entry: :account)
                  .merge(Account.accessible_by(Current.user))
                  .where(accounts: { family_id: Current.family.id })
                  .where(bank_entry_suggested: true)
                  .to_a
                  .select { |trade| trade.entry.account.permission_for(Current.user).in?(%i[owner full_control]) }

    trades.each { |trade| trade.update!(bank_entry_suggested: false) }
    redirect_back_or_to investments_overview_path, notice: t(".success", count: trades.size)
  end

  private
    def set_entry
      @entry = visible_entries.where(entryable_type: "Trade").find(params[:trade_id])
    end

    def visible_entries
      Current.family.entries.joins(:account).merge(Account.accessible_by(Current.user))
    end
end
