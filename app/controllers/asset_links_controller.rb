# Answers the links between bank charges and vehicle logs or property
# expenses that the app proposed on its own (see AssetLinker): confirm or
# reject one, or all of an account's at once, undo a link from the bank
# movement, and search the whole bank history again.
class AssetLinksController < ApplicationController
  include AccountAuthorizable

  before_action :set_record, only: %i[confirm reject unlink]
  before_action :set_account, only: %i[search confirm_all reject_all]

  def confirm
    @record.confirm_link!
    redirect_back_or_to asset_tab_path, notice: t(".success")
  end

  def reject
    @record.reject_link!
    redirect_back_or_to asset_tab_path, notice: t(".success")
  end

  # From the bank movement: the record keeps its data, without the charge. A
  # record the app created and nobody confirmed is a rejection instead.
  def unlink
    if @record.pending?
      @record.reject_link!
    else
      @record.update!(entry: nil, suggestion: nil)
    end

    redirect_back_or_to asset_tab_path, notice: t(".success")
  end

  def search
    count = AssetLinker.new(Current.family, since: nil).run!
    redirect_to asset_tab_path, notice: t(".success", count: count)
  end

  def confirm_all
    AssetLink.suggestions_for(@account).find_each(&:confirm_link!)
    redirect_to asset_tab_path, notice: t(".success")
  end

  def reject_all
    AssetLink.suggestions_for(@account).find_each(&:reject_link!)
    redirect_to asset_tab_path, notice: t(".success")
  end

  private
    def set_record
      @record = Vehicle::Log.find_by(id: params[:id]) || Property::Expense.find_by(id: params[:id])
      raise ActiveRecord::RecordNotFound if @record.nil?

      @account = asset_accounts.find(@record.asset_account.id)
      require_account_permission!(@account)
    end

    def set_account
      @account = asset_accounts.find(params[:account_id])
      require_account_permission!(@account)
    end

    def asset_accounts
      accessible_accounts.where(accountable_type: %w[Vehicle Property])
    end

    # Where the account shows its suggestions.
    def asset_tab_path
      account_path(@account, tab: @account.vehicle? ? "overview" : "expenses")
    end
end
