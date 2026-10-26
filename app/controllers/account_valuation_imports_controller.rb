# Fulas Bank: loads a list of dated values into an account from a file
# (see Account::ValuationImport), in two steps like the RoadTrip import:
#
# 1. The person uploads the file and sees what each line would do.
# 2. Confirming saves it. The file travels back in the confirmation form, so
#    nothing is stored between the two steps.
class AccountValuationImportsController < ApplicationController
  include AccountAuthorizable

  MAX_FILE_SIZE = 5.megabytes

  before_action :set_account

  def new
  end

  def create
    content = params[:content].present? ? confirmed_content : uploaded_content
    return render_upload_error(:missing_file) if content.blank?

    @import = Account::ValuationImport.new(@account, content)
    @import.rows

    if params[:confirm].present?
      count = @import.import!(start_at_first_row: params[:start_at_first_row] == "1")
      notice = count.positive? ? t(".success", count: count) : t(".nothing_imported")

      respond_to do |format|
        format.html { redirect_to account_path(@account), notice: notice }
        format.turbo_stream { stream_redirect_to(account_path(@account), notice: notice) }
      end
    else
      @content = Base64.strict_encode64(content)
      render :preview, formats: [ :html ]
    end
  rescue Account::ValuationImport::InvalidFile => e
    render_upload_error(e.reason)
  end

  private
    def set_account
      @account = accessible_accounts.find(params[:account_id])
      return unless require_account_permission!(@account)

      redirect_to account_path(@account), alert: t("account_valuation_imports.not_supported") unless @account.valuation_import_supported?
    end

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
      @error = t("account_valuation_imports.errors.#{key}")
      render :new, formats: [ :html ], status: :unprocessable_entity
    end
end
