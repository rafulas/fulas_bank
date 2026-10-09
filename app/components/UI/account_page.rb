class UI::AccountPage < ApplicationComponent
  attr_reader :account, :chart_view, :chart_period, :loan_chart, :as_of, :statement_coverage, :statements,
              :reconciliation_statuses, :can_manage_statements

  renders_one :activity_feed, ->(feed_data:, pagy:, search:) { UI::Account::ActivityFeed.new(feed_data: feed_data, pagy: pagy, search: search) }

  # `loan_chart` is the Loan::PayoffChart payload the controller built for a
  # loan account, nil for every other type and for a loan with no schedule.
  # `as_of` is the page's one reference date, captured by the controller.
  # `loan_projection` is the projection the controller already built for the
  # chart, so the Schedule tab's forecast card does not simulate it again.
  def initialize(account:, chart_view: nil, chart_period: nil, loan_chart: nil, as_of: Date.current, active_tab: nil,
                 statement_coverage: nil, statements: [], reconciliation_statuses: {}, can_manage_statements: false,
                 loan_projection: nil)
    @account = account
    @chart_view = chart_view
    @chart_period = chart_period
    @loan_chart = loan_chart
    @loan_projection = loan_projection
    @as_of = as_of
    @active_tab = active_tab
    @statement_coverage = statement_coverage
    @statements = statements
    @reconciliation_statuses = reconciliation_statuses
    @can_manage_statements = can_manage_statements
  end

  def id
    dom_id(account, :container)
  end

  def broadcast_channel
    account
  end

  def broadcast_refresh!
    Turbo::StreamsChannel.broadcast_replace_to(broadcast_channel, target: id, renderable: self, layout: false)
  end

  def title
    account.name
  end

  def subtitle
    return nil unless account.property?

    account.property.address
  end

  def active_tab
    tabs.find { |tab| tab == @active_tab&.to_sym } || tabs.first
  end

  def tabs
    base_tabs = case account.accountable_type
    when "Investment", "Crypto"
      [ :activity, :holdings ]
    when "Loan"
      account.loan.amortizable? ? [ :activity, :overview, :schedule, :payments ] : [ :activity, :overview, :payments ]
    when "Property"
      [ :activity, :overview, :expenses ]
    when "Vehicle"
      [ :overview, :activity, :refuels, :workshop, :running_costs ]
    else
      [ :activity ]
    end

    base_tabs + [ :statements ]
  end

  def fx_coverage_start_date
    return @fx_coverage_start_date if defined?(@fx_coverage_start_date)

    result = nil
    if account.family.present? && account.currency != account.family.currency
      pair = ExchangeRatePair.for_pair(from: account.currency, to: account.family.currency)
      if pair.first_provider_rate_on.present?
        oldest_entry = account.entries.minimum(:date)
        if oldest_entry.present? && oldest_entry < pair.first_provider_rate_on
          result = pair.first_provider_rate_on
        end
      end
    end

    @fx_coverage_start_date = result
  end

  # The controller's projection when it built one; otherwise built here, once
  # per render, for callers that construct the page without it.
  def loan_projection
    @loan_projection ||= account.loan.payoff_projection(as_of: as_of)
  end

  # Built once per render and shared by the vehicle's tabs, which are all in
  # the page at once.
  def vehicle_logbook
    @vehicle_logbook ||= account.vehicle.logbook(as_of: as_of)
  end

  def tab_content_for(tab)
    case tab
    when :activity
      activity_feed
    when :overview
      # Accountable is responsible for implementing the partial in the correct
      # folder. The loan's tab shows date-sensitive figures and takes the
      # page's one reference date, like its Schedule tab.
      locals = { account: account }
      locals[:as_of] = as_of if account.accountable_type == "Loan"
      locals[:logbook] = vehicle_logbook if account.accountable_type == "Vehicle"
      render "#{account.accountable_type.downcase.pluralize}/tabs/#{tab}", **locals
    when :refuels, :workshop, :running_costs
      render "vehicles/tabs/#{tab}", account: account, logbook: vehicle_logbook
    when :expenses
      render "properties/tabs/expenses", account: account, summary: Property::ExpenseSummary.new(account.property, as_of: as_of)
    when :holdings
      # Accountable is responsible for implementing the partial in the correct folder
      render "#{account.accountable_type.downcase.pluralize}/tabs/#{tab}", account: account
    when :schedule
      render "loans/tabs/schedule", account: account, as_of: as_of, projection: loan_projection
    when :payments
      render_payments_tab
    when :statements
      render_statement_tab
    end
  end

  # Loaded when opened, like the statements tab: finding candidate payments
  # searches the family's movements, which no other tab needs.
  def render_payments_tab
    frame_id = dom_id(account, :payments_tab)
    return turbo_frame_tag(frame_id) { render("loans/tabs/payments", account: account) } if active_tab == :payments

    turbo_frame_tag frame_id, src: helpers.account_path(account, tab: "payments"), loading: :lazy
  end

  def render_statement_tab
    return render "accounts/show/statements_frame", **statement_tab_locals if statement_tab_loaded?

    turbo_frame_tag statement_tab_frame_id, src: helpers.account_path(account, tab: "statements"), loading: :lazy
  end

  def statement_tab_loaded?
    statement_coverage.present?
  end

  def statement_tab_frame_id
    dom_id(account, :statements_tab)
  end

  def statement_tab_locals
    {
      account: account,
      coverage: statement_coverage,
      statements: statements,
      reconciliation_statuses: reconciliation_statuses,
      can_manage_statements: can_manage_statements
    }
  end
end
