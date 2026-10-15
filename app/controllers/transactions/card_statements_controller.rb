# Fulas Bank: sends a credit card movement to the next statement, or back
# to its own, from its detail panel (see CreditCard::Cycle).
class Transactions::CardStatementsController < ApplicationController
  def update
    @entry = Current.accessible_entries.transactions.find(params[:transaction_id])
    return unless require_account_permission!(@entry.account, :annotate, redirect_path: transaction_path(@entry))

    next_statement = ActiveModel::Type::Boolean.new.cast(params.dig(:card_statement, :next_card_statement))
    @entry.transaction.update!(next_card_statement: next_statement)

    redirect_back_or_to transaction_path(@entry), notice: t(".success")
  end
end
