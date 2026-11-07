# Fulas Bank: the user has seen a price rise on Inicio; it is not shown
# again (see PriceRises).
class PriceRiseDismissalsController < ApplicationController
  def create
    change = RecurringPriceChange.joins(:recurring_transaction)
                                 .merge(RecurringTransaction.accessible_by(Current.user))
                                 .find_by(id: params[:change_id], recurring_transactions: { family_id: Current.family.id })
    PriceRises.dismiss!(Current.user, change.id) if change

    redirect_back_or_to root_path, notice: t(".dismissed")
  end
end
