# Fulas Bank: the time of a movement, besides its day. Optional: a movement
# without one counts as 00:00. Within a day the list goes latest first (see
# Entry.reverse_chronological).
class AddTimeOfDayToEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :entries, :time_of_day, :time
  end
end
