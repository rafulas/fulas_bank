# Fulas Bank: «Escenarios» of the Forecast. A scenario is a named set of
# "what if" changes (stop a recurring payment, cancel a loan, change an
# amount, add an income or expense, spend more or less) applied on top of
# the forecast to compare both, without touching the real data.
class CreateScenarios < ActiveRecord::Migration[8.1]
  def change
    create_table :scenarios, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.text :notes
      t.timestamps
    end

    create_table :scenario_changes, id: :uuid do |t|
      t.references :scenario, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :kind, null: false
      t.date :starts_on, null: false
      t.date :ends_on
      t.string :name
      t.decimal :amount, precision: 19, scale: 4
      # Income or expense, for a movement added by the scenario.
      t.string :nature, null: false, default: "outflow"
      # once, monthly or yearly, for a movement added by the scenario.
      t.string :frequency, null: false, default: "once"
      # For a cancelled loan: what is left to pay that day (pending) or an
      # amount typed in (manual).
      t.string :payoff_mode, null: false, default: "pending"
      t.references :recurring_transaction, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :loan_account, foreign_key: { to_table: :accounts, on_delete: :cascade }, type: :uuid
      # Where a movement added by the scenario (or a loan's payoff) goes; the
      # forecast's main account when empty.
      t.references :account, foreign_key: { on_delete: :nullify }, type: :uuid
      t.timestamps
    end
  end
end
