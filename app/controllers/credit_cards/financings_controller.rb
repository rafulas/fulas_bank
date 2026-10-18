# Fulas Bank: one purchase paid in instalments (CardFinancing), from the
# card's statement tab: the purchase, and each fee and instalment with the
# day it is charged and the bank's charge once imported. Shown in a dialog.
class CreditCards::FinancingsController < ApplicationController
  def show
    @account = Current.family.accounts.accessible_by(Current.user).where(accountable_type: "CreditCard").find(params[:credit_card_id])
    @financing = @account.card_financings.includes(entry: :entryable).find(params[:id])
    @cycle = CreditCard::Cycle.new(@account)
    @lines = @financing.charge_lines(cycle: @cycle)
  end
end
