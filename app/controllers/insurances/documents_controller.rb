# Opens, downloads and removes the files (the policy, receipts) attached to an
# insurance.
class Insurances::DocumentsController < ApplicationController
  before_action :set_document

  def show
    disposition = params[:disposition] == "attachment" ? "attachment" : "inline"
    redirect_to rails_blob_url(@document, disposition: disposition)
  end

  def destroy
    @document.purge
    redirect_to edit_insurance_path(@insurance), notice: t(".success")
  end

  private
    def set_document
      @insurance = Current.family.insurances.find(params[:insurance_id])
      @document = @insurance.documents.find(params[:id])
    end
end
