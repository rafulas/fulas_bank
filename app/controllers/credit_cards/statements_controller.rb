# Fulas Bank: one statement of a credit card, from the card's statement tab:
# the movements it is made of, what was financed out of it and the bank's
# charge (see CreditCard::Cycle). Shown in a dialog.
class CreditCards::StatementsController < ApplicationController
  def show
    @account = Current.family.accounts.accessible_by(Current.user).where(accountable_type: "CreditCard").find(params[:credit_card_id])
    @cycle = CreditCard::Cycle.new(@account)
    @statement = @cycle.statement(month) if @cycle.configured?
    return redirect_to(account_path(@account, tab: "card_statement")) unless @statement

    @reconciler = CreditCard::Reconciler.new(@account)
    @bank_entry = @reconciler.statement_charge_for(@statement)
    @financings = @account.card_financings.includes(entry: :entryable).select { |financing| financing.statement_month(@cycle) == @statement.month }
  end

  private
    # The statement's month, as "2026-10" (the month it closes in).
    def month
      Date.strptime(params[:id].to_s, "%Y-%m")
    rescue Date::Error
      Date.current.beginning_of_month
    end
end
