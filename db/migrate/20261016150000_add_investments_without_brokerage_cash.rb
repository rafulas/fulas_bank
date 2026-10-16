# Fulas Bank: two improvements to investments.
#
# 1. A price typed by hand. securities_prices.manual marks the prices the user
#    wrote in the holding's drawer, so that a health check that gives up on a
#    security (and wipes its provider prices) keeps them, and the drawer can
#    say where the price came from.
#
# 2. Investment accounts without brokerage cash. Many people in Spain buy
#    shares straight from their current account, or receive them as part of
#    their pay: there is no cash inside the investment account.
#    investments.brokerage_cash = false makes the account worth just its
#    positions, and trades.bank_entry_id ties a buy or a sale to the bank
#    movement that paid for it (or received the money).
class AddInvestmentsWithoutBrokerageCash < ActiveRecord::Migration[8.1]
  def change
    add_column :security_prices, :manual, :boolean, default: false, null: false

    add_column :investments, :brokerage_cash, :boolean, default: true, null: false

    add_reference :trades, :bank_entry, type: :uuid,
                  foreign_key: { to_table: :entries, on_delete: :nullify },
                  index: { unique: true }
  end
end
