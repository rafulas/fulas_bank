# Fulas Bank: which accounts' balances the movements panel shows (see
# Transaction::Panel). Only accounts the user can see are kept.
class Transactions::PanelAccountsController < ApplicationController
  def edit
    @panel = Transaction::Panel.new(Current.family, user: Current.user)
  end

  def update
    panel = Transaction::Panel.new(Current.family, user: Current.user)
    allowed = panel.selectable_accounts.map(&:id)
    chosen = Array(params[:account_ids]).map(&:to_s) & allowed

    Current.user.update_transactions_panel_account_ids!(chosen)
    redirect_to transactions_path, notice: t(".success")
  end
end
