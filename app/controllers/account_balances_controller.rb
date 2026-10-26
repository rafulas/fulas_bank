# Fulas Bank: «Editar saldos», all the accounts' balances on one page (see
# Account::BalanceBulkUpdate).
class AccountBalancesController < ApplicationController
  def show
    @editor = new_editor
  end

  def update
    editor = new_editor
    editor.apply(params.fetch(:balances, {}).permit(*editor.accounts.map(&:id)))

    if editor.failures.any?
      flash[:alert] = t(".failed", count: editor.failures.size)
      # Listed on the page itself, which keeps them in view (a toast fades).
      flash[:balance_errors] = editor.failures.map { |failure| "#{failure.account.name}: #{failure.error}" }
    end

    if editor.updated.any?
      flash[:notice] = t(".success", count: editor.updated.size)
    elsif editor.failures.empty?
      flash[:notice] = t(".nothing_changed")
    end

    redirect_to account_balances_path
  end

  private
    def new_editor
      Account::BalanceBulkUpdate.new(family: Current.family, user: Current.user)
    end
end
