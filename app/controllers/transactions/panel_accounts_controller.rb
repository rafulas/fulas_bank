# Fulas Bank: which accounts' balances the movements panel shows (see
# Transaction::Panel). Only accounts the user can see are kept. With
# `scope=home`, Inicio's own choice, and the cards whose next statements it
# lists.
class Transactions::PanelAccountsController < ApplicationController
  def edit
    @panel = panel
  end

  def update
    allowed = panel.selectable_accounts.map(&:id)
    chosen = Array(params[:account_ids]).map(&:to_s) & allowed

    if panel.home?
      cards = Array(params[:card_ids]).map(&:to_s) & panel.selectable_cards.map(&:id)
      Current.user.update_home_panel!(account_ids: chosen, card_ids: cards)
      redirect_to root_path, notice: t(".success")
    else
      Current.user.update_transactions_panel_account_ids!(chosen)
      redirect_to transactions_path, notice: t(".success")
    end
  end

  private
    def panel
      @panel_for_scope ||= Transaction::Panel.new(Current.family, user: Current.user, scope: params[:scope] == "home" ? :home : :transactions)
    end
end
