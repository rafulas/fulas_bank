# Fulas Bank: the "Conciliar ahora" button of a card's statement tab (see
# CreditCard::Reconciler). It also runs on its own after every import.
class CreditCards::ReconciliationsController < ApplicationController
  def create
    account = Current.family.accounts.accessible_by(Current.user).where(accountable_type: "CreditCard").find(params[:credit_card_id])
    return unless require_account_permission!(account, :write)

    filed = CreditCard::Reconciler.new(account).run!
    redirect_to account_path(account, tab: "card_statement"), notice: t(".success", count: filed)
  end
end
