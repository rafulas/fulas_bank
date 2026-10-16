# Fulas Bank: import any file, dropped on the Transactions page or chosen in
# Importar, without saying what it is or which account it is for:
#
#   - A RoadTrip export goes to the vehicle whose plate it carries (or the
#     only vehicle), straight to its preview.
#   - A Bilance export imports every account at once, as it names them.
#   - A bank statement (Excel or CSV) goes to the account it is for
#     (Import::AccountGuess): its IBAN, its balance, or the only current
#     account. When it cannot tell, the user chooses.
#
# Then the usual import steps follow, with everything already filled in.
class SmartImportsController < ApplicationController
  MAX_FILE_SIZE = Import::MAX_CSV_SIZE

  before_action :set_import, only: %i[edit update]

  def create
    file = params[:file] || params.dig(:import, :import_file)
    return redirect_to(new_import_path, alert: t(".missing_file")) unless file.respond_to?(:read)
    return redirect_to(new_import_path, alert: t(".file_too_large", max_size: MAX_FILE_SIZE / 1.megabyte)) if file.size > MAX_FILE_SIZE

    content = file.read

    if Vehicle::RoadtripImport.roadtrip?(content)
      roadtrip(content)
    else
      statement(content, file)
    end
  end

  # Which account a statement is for, when the app could not tell or got it
  # wrong.
  def edit
    @accounts = writable_accounts.where(accountable_type: Import::AccountGuess::CASH_TYPES).alphabetically
  end

  def update
    account = writable_accounts.find(params[:account_id])
    @import.update!(account: account, account_col_label: nil)
    redirect_to import_configuration_path(@import), notice: t(".success", account: account.name)
  end

  private
    def set_import
      @import = Current.family.imports.where(type: "TransactionImport").pending.find(params[:id])
    end

    def writable_accounts
      Current.family.accounts.writable_by(Current.user).visible
    end

    # ---- RoadTrip ----

    def roadtrip(content)
      vehicles = writable_accounts.where(accountable_type: "Vehicle").includes(:accountable).alphabetically.to_a
      return redirect_to(new_import_path, alert: t(".no_vehicle")) if vehicles.empty?

      @content = Base64.strict_encode64(content)
      @account = vehicle_for(vehicles, content)

      if @account
        @vehicle = @account.vehicle
        @import = Vehicle::RoadtripImport.new(@vehicle, content)
        @summary = @import.summary
        flash.now[:notice] = t(".roadtrip_detected", vehicle: @account.name)
        render "vehicles/roadtrip_imports/preview"
      else
        @vehicles = vehicles
        render :choose_vehicle
      end
    rescue Vehicle::RoadtripImport::InvalidFile
      redirect_to new_import_path, alert: t(".invalid_roadtrip")
    end

    # The vehicle whose plate the export carries, or the only one.
    def vehicle_for(vehicles, content)
      plate = normalize_plate(Vehicle::RoadtripImport.new(vehicles.first.vehicle, content).license_plate)
      by_plate = vehicles.find { |account| plate.present? && normalize_plate(account.vehicle.license_plate) == plate }
      by_plate || (vehicles.first if vehicles.one?)
    end

    def normalize_plate(plate)
      plate.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    end

    # ---- Bank statements and Bilance ----

    def statement(content, file)
      spreadsheet = Import::XLSX_MIME_TYPES.include?(file.content_type) || Import::XlsxConverter.xlsx?(content)
      unless spreadsheet || Import::ALLOWED_CSV_MIME_TYPES.include?(file.content_type) || file.original_filename.to_s.downcase.end_with?(".csv")
        return redirect_to(new_import_path, alert: t(".unknown_file"))
      end

      import = Current.family.imports.create!(
        type: "TransactionImport",
        date_format: Current.family.date_format,
        statement_reference: Import::StatementReference.from(content)
      )

      if spreadsheet
        import.update!(raw_file_str: Import::XlsxConverter.new(content).to_csv, col_sep: ",")
      else
        import.update!(raw_file_str: content)
      end

      preset = Import::BankPreset.apply(import)

      if preset&.key == "bilance"
        redirect_to import_configuration_path(import), notice: t(".bilance_detected")
      elsif (guess = Import::AccountGuess.new(import, accounts: writable_accounts.to_a).guess)
        import.update!(account: guess.account)
        redirect_to import_configuration_path(import),
                    notice: t(".account_detected.#{guess.reason}", bank: preset&.bank_name || t(".statement"), account: guess.account.name)
      else
        redirect_to edit_smart_import_path(import), notice: t(".choose_account", bank: preset&.bank_name || t(".statement"))
      end
    rescue Import::XlsxConverter::Error
      import&.destroy
      redirect_to new_import_path, alert: t(".invalid_spreadsheet")
    end
end
