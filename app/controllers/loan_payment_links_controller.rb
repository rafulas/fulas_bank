# Links a bank movement to the loan it paid, from either side: the loan's
# Payments tab (choosing among its candidates) or a transaction's detail
# drawer (choosing the loan).
class LoanPaymentLinksController < ApplicationController
  def create
    loan_account = accessible_accounts.where(accountable_type: "Loan").find(params.require(:loan_account_id))
    return unless require_account_permission!(loan_account)

    entry = Current.accessible_entries.find(params.require(:entry_id))
    return unless require_account_permission!(entry.account, :annotate)

    loan_account.loan.link_payment!(entry)
    redirect_back_or_to account_path(loan_account, tab: "payments"),
                        notice: t(".success", loan: loan_account.name)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_back_or_to account_path(loan_account, tab: "payments"), alert: t(".failure")
  end

  # Unlinking leaves the loan's balance where the link put it: that figure is
  # the schedule's, and still the best known one until the next update.
  def destroy
    link = Loan::PaymentLink.joins(loan: :account)
                            .where(accounts: { id: accessible_accounts.select(:id) })
                            .find(params[:id])
    loan_account = link.loan.account
    return unless require_account_permission!(loan_account)

    link.destroy!
    redirect_back_or_to account_path(loan_account, tab: "payments"), notice: t(".success")
  end
end
