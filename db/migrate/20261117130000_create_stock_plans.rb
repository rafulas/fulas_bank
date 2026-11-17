# Fulas Bank: «Plan de acciones» of the Forecast. Part of a yearly bonus is
# paid in the company's shares (with free ones on top), which cannot be sold
# for some years; the forecast expects the bonus cash and the new shares'
# value on the day they are delivered, and the sale of each year's shares
# once they can be sold.
class CreateStockPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :stock_plans, id: :uuid do |t|
      t.references :family, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :name, null: false
      # Where the shares are kept, and which ones.
      t.references :investment_account, null: false, foreign_key: { to_table: :accounts, on_delete: :cascade }, type: :uuid
      t.references :security, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      # Where the bonus cash and the sales land; the forecast's main account when empty.
      t.references :cash_account, foreign_key: { to_table: :accounts, on_delete: :nullify }, type: :uuid
      # The bonus at 100 % of the target, before taxes.
      t.decimal :base_bonus, precision: 19, scale: 4, null: false, default: 0
      t.string :currency, null: false
      # Defaults for each year: the share of the bonus taken in shares, the
      # income tax withheld from the cash part, one free share for every
      # `gift_every` bought, and the years they cannot be sold.
      t.decimal :stock_percent, precision: 7, scale: 4, null: false, default: 28
      t.decimal :tax_percent, precision: 7, scale: 4, null: false, default: 0
      t.integer :gift_every, null: false, default: 10
      t.integer :lock_years, null: false, default: 3
      t.timestamps
    end

    # One year's bonus: the shares bought (and the cash) on `granted_on`, sold
    # on `sell_on`.
    create_table :stock_plan_grants, id: :uuid do |t|
      t.references :stock_plan, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.date :granted_on, null: false
      t.date :sell_on, null: false
      # The bonus achieved (100 = the base) and the share of it in shares.
      t.decimal :achievement_percent, precision: 7, scale: 4, null: false, default: 100
      t.decimal :stock_percent, precision: 7, scale: 4, null: false, default: 28
      # Once known: the shares bought and the free ones. Empty, they are worked out.
      t.decimal :shares, precision: 19, scale: 4
      t.decimal :gift_shares, precision: 19, scale: 4
      t.text :notes
      t.timestamps
    end
  end
end
