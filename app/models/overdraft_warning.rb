# Fulas Bank: the overdraft warning on Inicio ("El día 5 pasa la luz y te
# quedarán −80 € en BBVA"). It runs the Forecast over the next weeks with
# the known movements only (recurring payments, loans, insurance, card
# charges, one-offs typed in; no "Gastos varios" estimate, so a warning is
# never a guess) and reports, for each current account, the first day its
# balance would go below zero, with the charge that pushes it there. For the
# forecast's main account with a cushion set ("colchón"), dropping below the
# cushion is reported too, more softly.
#
# The result is cached for an hour per state of the movements, since the
# forecast is too heavy to run on every visit to Inicio.
class OverdraftWarning
  HORIZON_DAYS = 30
  CACHE_VERSION = 1

  Warning = Data.define(:account, :date, :balance, :culprit_name, :culprit_amount, :below_cushion) do
    def overdraft?
      !below_cushion
    end
  end

  # What is cached: plain values, the accounts are looked up again.
  Row = Data.define(:account_id, :date, :balance, :culprit_name, :culprit_amount, :below_cushion)
  private_constant :Row

  attr_reader :family, :user, :today

  def initialize(family, user:, today: Date.current)
    @family = family
    @user = user
    @today = today
  end

  def warnings
    @warnings ||= begin
      rows = Rails.cache.fetch(cache_key, expires_in: 1.hour) { compute.map(&:to_h) }
      by_id = accounts.index_by(&:id)

      rows.filter_map do |row|
        row = row.symbolize_keys
        account = by_id[row[:account_id]]
        next unless account

        Warning.new(account: account, date: row[:date], balance: Money.new(row[:balance], account.currency),
                    culprit_name: row[:culprit_name], culprit_amount: row[:culprit_amount] && Money.new(row[:culprit_amount], account.currency),
                    below_cushion: row[:below_cushion])
      end
    end
  end

  def any?
    warnings.any?
  end

  private
    def cache_key
      [ "overdraft_warning", CACHE_VERSION, family.id, user.id, family.entries_version, today.to_s, cushion.to_s, main_account&.id ].join("/")
    end

    def compute
      return [] if current_accounts.empty?

      current_accounts.filter_map do |account|
        if (found = forecast.first_below(account, 0))
          row(account, *found, below_cushion: false)
        elsif account == main_account && cushion && (found = forecast.first_below(account, cushion))
          row(account, *found, below_cushion: true)
        end
      end.sort_by(&:date)
    rescue => e
      # A warning must never take Inicio down with it.
      Rails.logger.warn("[OverdraftWarning] #{e.class}: #{e.message}")
      []
    end

    def row(account, date, balance, below_cushion:)
      culprit = forecast.active_flows
                        .select { |flow| flow.date == date && flow.account&.id == account.id && !flow.inflow? }
                        .max_by(&:amount)

      Row.new(account_id: account.id, date: date, balance: balance.amount.to_d,
              culprit_name: culprit&.name, culprit_amount: culprit&.amount&.to_d, below_cushion: below_cushion)
    end

    def forecast
      @forecast ||= Forecast.new(
        family,
        accounts: accounts,
        through: today + HORIZON_DAYS.days,
        include_variable: false,
        today: today,
        main_account: main_account,
        card_accounts: card_accounts,
        debt_plan: family.debt_plan&.forecast_feed(user, today: today)
      )
    end

    def visible_accounts
      family.accounts.accessible_by(user).visible.alphabetically
    end

    def accounts
      @accounts ||= visible_accounts.where(accountable_type: Forecast::ACCOUNT_TYPES).to_a
    end

    def card_accounts
      @card_accounts ||= visible_accounts.where(accountable_type: Forecast::CARD_TYPES).to_a
    end

    # Only current and savings accounts can run out of money.
    def current_accounts
      accounts.select { |account| account.accountable_type == "Depository" }
    end

    def main_account
      @main_account ||= begin
        saved = user.preferences&.dig(Forecast::MAIN_ACCOUNT_PREFERENCE)
        accounts.find { |account| account.id == saved } || Forecast.default_main_account(accounts)
      end
    end

    def cushion
      @cushion ||= user.preferences&.dig(Forecast::CUSHION_PREFERENCE).presence&.to_d
    end
end
