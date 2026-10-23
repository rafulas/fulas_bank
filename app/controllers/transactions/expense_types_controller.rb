# Fulas Bank: marks a movement as variable, fixed, a bill or a subscription
# from its detail panel (see Transaction::ExpenseTypeChange).
class Transactions::ExpenseTypesController < ApplicationController
  def update
    @entry = Current.accessible_entries.transactions.find(params[:transaction_id])
    return unless require_account_permission!(@entry.account, :annotate, redirect_path: transaction_path(@entry))

    change = Transaction::ExpenseTypeChange.new(
      @entry.transaction,
      expense_type: expense_type_params[:expense_type],
      end_on: (expense_type_params[:end_on] if expense_type_params[:ends_by] == "date"),
      periods: (expense_type_params[:periods] if expense_type_params[:ends_by] == "periods"),
      never_ends: expense_type_params[:ends_by] == "never"
    )

    if change.save
      redirect_back_or_to transaction_path(@entry), notice: t(".success")
    else
      redirect_back_or_to transaction_path(@entry), alert: t(".errors.#{change.error}")
    end
  end

  private
    def expense_type_params
      params.require(:expense_type).permit(:expense_type, :ends_by, :end_on, :periods)
    end
end
