# Opens, downloads and removes the files (invoices, receipts) attached to a
# property expense.
class Properties::ExpenseAttachmentsController < Properties::BaseController
  before_action :require_write_access!, only: :destroy
  before_action :set_attachment

  def show
    disposition = params[:disposition] == "attachment" ? "attachment" : "inline"
    redirect_to rails_blob_url(@attachment, disposition: disposition)
  end

  def destroy
    @attachment.purge
    redirect_to edit_property_expense_path(@account, @expense), notice: t(".success")
  end

  private
    def set_attachment
      @expense = @property.expenses.find(params[:expense_id])
      @attachment = @expense.attachments.find(params[:id])
    end
end
