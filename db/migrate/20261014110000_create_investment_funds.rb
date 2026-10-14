class CreateInvestmentFunds < ActiveRecord::Migration[8.1]
  def change
    create_table :investment_funds, id: :uuid do |t|
      t.references :family, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :name, null: false
      t.string :isin
      t.decimal :units, precision: 19, scale: 6, null: false, default: 0
      t.decimal :price, precision: 19, scale: 6
      t.date :price_date
      t.decimal :cost, precision: 19, scale: 4
      t.timestamps
    end

    create_table :investment_fund_prices, id: :uuid do |t|
      t.references :investment_fund, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: false
      t.date :date, null: false
      t.decimal :price, precision: 19, scale: 6, null: false
      t.timestamps
    end
    add_index :investment_fund_prices, %i[investment_fund_id date], unique: true
    add_check_constraint :investment_funds, "units >= 0", name: "chk_investment_funds_units_not_negative"
    add_check_constraint :investment_fund_prices, "price > 0", name: "chk_investment_fund_prices_price_positive"
  end
end
