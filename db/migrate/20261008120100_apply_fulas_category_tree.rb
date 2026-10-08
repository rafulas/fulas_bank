class ApplyFulasCategoryTree < ActiveRecord::Migration[8.1]
  # Gives every existing family the Fulas Bank categories and subcategories,
  # folding Sure's old defaults into their new equivalent. New families get
  # them when they sign up.
  def up
    Category.reset_column_information

    # An earlier version marked "Traspasos" transactions as one-time ones.
    # That is now handled by the category itself, so undo it.
    execute <<~SQL
      UPDATE transactions
      SET kind = 'standard', extra = extra - 'fulas_auto_one_time'
      WHERE extra ? 'fulas_auto_one_time' AND kind = 'one_time'
    SQL
    execute <<~SQL
      UPDATE transactions
      SET extra = extra - 'fulas_auto_one_time'
      WHERE extra ? 'fulas_auto_one_time'
    SQL

    Family.find_each do |family|
      Category::FulasTree.new(family).apply!(first_rollout: true)
    end
  end

  def down
    # The categories stay; only the markers added above can't be restored.
  end
end
