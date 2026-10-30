# Fulas Bank: when the user first saw an imported movement. Movements that
# come in from an import (or a bank sync) carry a blue dot in the list until
# their detail is opened or the list is marked as seen. Those already there
# count as seen, so only what comes in from now on is marked.
class AddSeenAtToEntries < ActiveRecord::Migration[8.1]
  def up
    add_column :entries, :seen_at, :datetime
    execute "UPDATE entries SET seen_at = NOW() WHERE import_id IS NOT NULL OR external_id IS NOT NULL"
  end

  def down
    remove_column :entries, :seen_at
  end
end
