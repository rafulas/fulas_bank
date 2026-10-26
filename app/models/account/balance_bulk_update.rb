# Fulas Bank: «Editar saldos», every account's balance on one page, to check
# them all against the bank in one go. Only the ones typed differently from
# what the app has are changed, each exactly as from its own edit form
# (Account#set_current_balance): an account with movements keeps them and
# the balance moves to the figure typed; one tracked by its value gets that
# value today.
class Account::BalanceBulkUpdate
  Failure = Data.define(:account, :error)

  attr_reader :family, :user, :updated, :failures

  def initialize(family:, user:)
    @family = family
    @user = user
    @updated = []
    @failures = []
  end

  # The accounts the user can change by hand, by type (as in the sidebar)
  # and then by name.
  def accounts
    @accounts ||= family.accounts.visible.manual.writable_by(user)
                        .includes(:accountable).to_a
                        .sort_by { |account| [ Accountable::TYPES.index(account.accountable_type) || Accountable::TYPES.size, account.name.downcase ] }
  end

  def groups
    accounts.group_by(&:accountable_type)
  end

  # `amounts` is { account id => amount typed }. A blank or unchanged amount
  # leaves its account alone. @return [self]
  def apply(amounts)
    amounts = amounts.to_h.transform_keys(&:to_s)

    accounts.each do |account|
      raw = amounts[account.id].to_s.strip
      next if raw.empty?

      amount = parse(raw, account)
      if amount.nil?
        failures << Failure.new(account: account, error: I18n.t("account_balances.update.invalid_amount", amount: raw))
        next
      end
      next unless changed?(account, amount)

      result = account.set_current_balance(amount)
      if result.success?
        updated << account
      else
        failures << Failure.new(account: account, error: result.error.presence || I18n.t("account_balances.update.not_saved"))
      end
    end

    self
  end

  private
    # The field sends "1234.56"; a comma decimal is accepted too, in case the
    # page's script did not run. A loan's balance is what is owed, typed with
    # or without a minus (as in its own form).
    def parse(raw, account)
      text = raw.delete(" ")
      text = text.delete(".").tr(",", ".") if text.include?(",")
      amount = BigDecimal(text)
      account.accountable_type == "Loan" ? amount.abs : amount
    rescue ArgumentError
      nil
    end

    def changed?(account, amount)
      precision = Money::Currency.new(account.currency).default_precision
      amount.round(precision) != account.balance.to_d.round(precision)
    end
end
