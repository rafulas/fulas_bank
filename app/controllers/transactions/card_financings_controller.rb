# Fulas Bank: a credit card purchase paid in instalments (CardFinancing),
# set from the purchase's detail panel with the figures the bank shows.
class Transactions::CardFinancingsController < ApplicationController
  before_action :set_entry

  def new
    @financing = CardFinancing.from_entry(@entry)
  end

  def create
    @financing = CardFinancing.from_entry(@entry)
    @financing.assign_attributes(financing_params)

    if @financing.save
      redirect_back_or_to account_path(@entry.account), notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @financing = financing
  end

  def update
    @financing = financing

    if @financing.update(financing_params)
      redirect_back_or_to account_path(@entry.account), notice: t(".success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    financing.destroy!
    redirect_back_or_to account_path(@entry.account), notice: t(".success")
  end

  private
    def set_entry
      @entry = Current.accessible_entries.transactions.find(params[:transaction_id])
      return unless require_account_permission!(@entry.account, :annotate, redirect_path: transaction_path(@entry))

      head :unprocessable_entity unless @entry.account.accountable_type == "CreditCard"
    end

    def financing
      CardFinancing.find_by!(entry_id: @entry.id, account_id: @entry.account_id)
    end

    def financing_params
      params.require(:card_financing).permit(:financed_amount, :installments_count, :installment_amount, :fee_amount)
    end
end
