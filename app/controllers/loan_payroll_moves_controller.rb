# Fulas Bank: moves a payroll-deducted loan's months, booked in another
# account (the «Cuenta Fake»), into the loan itself (Loan::PayrollDeduction).
class LoanPayrollMovesController < ApplicationController
  def create
    loan_account = accessible_accounts.where(accountable_type: "Loan").find(params.require(:loan_account_id))
    return unless require_account_permission!(loan_account)

    loan = loan_account.loan
    since = params[:desde] == "todo" ? (loan.start_date || Date.current - 10.years) : Date.current.beginning_of_year
    deduction = Loan::PayrollDeduction.new(loan)
    pairs = deduction.pairs_elsewhere(since: since).select do |pair|
      pair.account.permission_for(Current.user).in?([ :owner, :full_control ])
    end
    count = deduction.move!(pairs)

    redirect_to account_path(loan_account, tab: "payments"), notice: t(".success", count: count, loan: loan_account.name)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to account_path(loan_account, tab: "payments"), alert: t(".failure")
  end
end
