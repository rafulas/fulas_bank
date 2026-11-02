# Fulas Bank: current accounts and cards now keep a running balance, as in
# Bilance (see Account::BalanceAdjuster). Their fixed balances («saldo
# fijado») become «Ajuste de saldo» movements of the same size, so every
# balance shown today stays the same (Account::PinsToAdjustments checks it,
# day by day, and leaves alone any account where it would not).
class TurnFixedBalancesIntoAdjustments < ActiveRecord::Migration[8.1]
  def up
    result = Account::PinsToAdjustments.run

    say "Saldos fijados convertidos en ajustes: #{result.converted.size} cuenta(s)"
    result.skipped.each do |account|
      say "Sin cambios (los saldos no cuadraban al convertir): #{account.name} (#{account.id})"
    end

    result.converted.each do |account|
      account.sync_later
    rescue StandardError => e
      say "No se ha podido recalcular #{account.name}: #{e.message}"
    end
  end

  def down
    # The adjustments stay: they keep the same balances the fixed ones gave.
  end
end
