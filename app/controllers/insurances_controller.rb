# Fulas Bank: the Seguros page, with every insurance policy of the family,
# and the forms to add and edit them. A policy can be tied to the vehicle or
# property it insures; the form is also opened from that asset's page, with
# the asset already chosen.
class InsurancesController < ApplicationController
  before_action :set_insurance, only: %i[edit update destroy]

  def index
    # Fulas Bank: a policy not renewed is no longer in force from its end.
    Current.family.insurances.expire_ended!
    @overview = Insurance::Overview.new(Current.family, assets: insurable_assets)
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t(".title"), nil ] ]
  end

  def new
    account = insurable_assets.find { |asset| asset.id == params[:account_id].to_s }
    kind = Insurance::KINDS.include?(params[:kind]) ? params[:kind] : Insurance.kind_for(account)
    @insurance = Current.family.insurances.new(account: account, kind: kind, name: default_name(kind, account))
  end

  def create
    @insurance = Current.family.insurances.new(insurance_params)
    @insurance.documents.attach(document_files) if document_files.any?

    if @insurance.save
      redirect_back_to_list notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    kept = @insurance.documents.map(&:id)
    @insurance.assign_attributes(insurance_params)
    @insurance.documents.attach(document_files) if document_files.any?

    if @insurance.save
      redirect_back_to_list notice: t(".success")
    else
      @insurance.documents.select { |document| document.persisted? && kept.exclude?(document.id) }.each(&:purge)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @insurance.destroy!
    redirect_back_to_list notice: t(".success")
  end

  private
    def set_insurance
      @insurance = Current.family.insurances.find(params[:id])
    end

    # The vehicles and properties the user can see: the assets a policy can
    # be tied to.
    def insurable_assets
      @insurable_assets ||= accessible_accounts.visible.where(accountable_type: Insurance::LINKABLE_TYPES).alphabetically.to_a
    end
    helper_method :insurable_assets

    # Fulas Bank: the current accounts and cards the user can see, where the
    # instalments may be charged.
    def insurance_payment_accounts
      @insurance_payment_accounts ||= accessible_accounts.visible.where(accountable_type: %w[Depository CreditCard]).alphabetically.to_a
    end
    helper_method :insurance_payment_accounts

    # "Seguro Cupra Ateca" for a car policy opened from the car's page.
    def default_name(kind, account)
      [ t("insurances.default_name"), account&.name ].compact.join(" ") if account
    end

    # Back to the asset's page when the form was opened from there.
    def redirect_back_to_list(notice:)
      account = insurable_assets.find { |asset| asset.id == params[:return_to_account].to_s }
      redirect_to(account ? account_path(account) : insurances_path, notice: notice)
    end

    def document_files
      @document_files ||= Array(params.dig(:insurance, :documents)).select { |file| file.respond_to?(:read) }
    end

    # The asset must be one of the user's vehicles or properties; any other
    # account is not found.
    def insurance_params
      permitted = params.require(:insurance).permit(
        :name, :kind, :insurer, :policy_number, :coverage, :assistance_phone,
        :premium, :payment_frequency, :start_date, :renewal_date, :active, :notes, :renews,
        installments: %i[date amount]
      )
      if params[:insurance].key?(:payment_account_id)
        payment_id = params.dig(:insurance, :payment_account_id).to_s
        permitted = permitted.merge(payment_account: payment_id.blank? ? nil : (insurance_payment_accounts.find { |account| account.id == payment_id } || raise(ActiveRecord::RecordNotFound)))
      end
      return permitted unless params[:insurance].key?(:account_id)

      account_id = params.dig(:insurance, :account_id).to_s
      return permitted.merge(account: nil) if account_id.blank?

      permitted.merge(account: insurable_assets.find { |asset| asset.id == account_id } || raise(ActiveRecord::RecordNotFound))
    end
end
