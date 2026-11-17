# Fulas Bank: «Informe» of the Resumen (see StatusReport). The accounts,
# sections and period come from the form, from a saved configuration
# (ReportPreset) or, the first time, are every visible account, every
# section and last month.
class StatusReportsController < ApplicationController
  include ForecastBuilding

  def show
    @presets = Current.user.report_presets.alphabetically
    @preset = @presets.find { |preset| preset.id == params[:preset_id].to_s } if params[:preset_id].present?
    @available_accounts = available_accounts
    @report = StatusReport.new(Current.family, user: Current.user, accounts: chosen_accounts,
                               sections: chosen_sections, period_key: chosen_period)
    @forecast = build_report_forecast if @report.show?("forecast")
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("category_summaries.index.title"), category_summaries_path ], [ t(".title"), nil ] ]
  end

  private
    def available_accounts
      @available_accounts ||= accessible_accounts.visible.alphabetically.to_a
    end

    # The accounts ticked in the form (only those the user can see), the
    # preset's, or all.
    def chosen_accounts
      ids = if params.key?(:account_ids) then Array(params[:account_ids]).map(&:to_s)
      elsif @preset then @preset.account_ids.map(&:to_s)
      end
      ids ? available_accounts.select { |account| ids.include?(account.id) } : available_accounts
    end

    def chosen_sections
      if params.key?(:sections) then Array(params[:sections]).map(&:to_s)
      elsif @preset then @preset.sections
      else StatusReport::SECTIONS
      end
    end

    def chosen_period
      params[:period].presence || @preset&.period || "last_month"
    end

    # The Forecast of the chosen everyday accounts and cards, built like the
    # Forecast page's, for the next twelve months.
    def build_report_forecast
      accounts = @report.forecast_accounts
      return nil if accounts.empty?

      @card_accounts = @report.forecast_cards
      build_forecast_for(accounts: accounts, through: Date.current >> StatusReport::FORECAST_MONTHS,
                         main_account: saved_main_account(accounts))
    end
end
