# Opens, downloads and removes the files (scanned invoices, receipts)
# attached to a logbook record.
class Vehicles::LogAttachmentsController < Vehicles::BaseController
  before_action :require_write_access!, only: :destroy
  before_action :set_attachment

  def show
    disposition = params[:disposition] == "attachment" ? "attachment" : "inline"
    redirect_to rails_blob_url(@attachment, disposition: disposition)
  end

  def destroy
    @attachment.purge
    redirect_to edit_vehicle_log_path(@account, @log), notice: t(".success")
  end

  private
    def set_attachment
      @log = @vehicle.logs.find(params[:log_id])
      @attachment = @log.attachments.find(params[:id])
    end
end
