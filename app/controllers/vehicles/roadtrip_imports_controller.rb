# Imports a vehicle's history from a RoadTrip CSV export in two steps:
#
# 1. The user uploads the file and sees what would be imported (how many
#    refuels, services and expenses, which readings were left out).
# 2. Confirming imports it. The file travels back in the confirmation form, so
#    nothing is stored between the two steps.
class Vehicles::RoadtripImportsController < Vehicles::BaseController
  MAX_FILE_SIZE = 5.megabytes

  before_action :require_write_access!

  def new
  end

  def create
    content = params[:confirm].present? ? confirmed_content : uploaded_content
    return render_upload_error(:missing_file) if content.blank?

    @import = Vehicle::RoadtripImport.new(@vehicle, content)
    @import.logs

    if params[:confirm].present?
      count = @import.import!
      redirect_to_tab "refuels", notice: t(".success", count: count)
    else
      @content = Base64.strict_encode64(content)
      @summary = @import.summary
      render :preview, formats: [ :html ]
    end
  rescue Vehicle::RoadtripImport::InvalidFile
    render_upload_error(:invalid_file)
  end

  private
    def uploaded_content
      file = params[:file]
      return unless file.respond_to?(:read)
      return if file.size > MAX_FILE_SIZE

      file.read
    end

    def confirmed_content
      Base64.strict_decode64(params[:content].to_s).presence
    rescue ArgumentError
      nil
    end

    def render_upload_error(key)
      @error = t(".#{key}")
      render :new, formats: [ :html ], status: :unprocessable_entity
    end
end
