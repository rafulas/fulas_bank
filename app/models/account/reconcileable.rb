module Account::Reconcileable
  extend ActiveSupport::Concern

  # Fulas Bank: on a current account or a card, «Nuevo saldo» and the
  # import's «Ajustar» write an «Ajuste de saldo» on that day instead of
  # fixing the balance there (see Account::BalanceAdjuster).
  def create_reconciliation(balance:, date:, dry_run: false)
    result =
      if Account::BalanceAdjuster.applies_to?(self)
        Account::BalanceAdjuster.new(self).adjust_to(balance: balance, date: date, dry_run: dry_run)
      else
        reconciliation_manager.reconcile_balance(balance: balance, date: date, dry_run: dry_run)
      end
    sync_later if result.success? && !dry_run
    result
  end

  def update_reconciliation(existing_valuation_entry, balance:, date:, dry_run: false)
    result = reconciliation_manager.reconcile_balance(balance: balance, date: date, existing_valuation_entry: existing_valuation_entry, dry_run: dry_run)
    sync_later if result.success? && !dry_run
    result
  end

  private
    def reconciliation_manager
      @reconciliation_manager ||= Account::ReconciliationManager.new(self)
    end
end
