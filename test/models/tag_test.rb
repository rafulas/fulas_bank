require "test_helper"

class TagTest < ActiveSupport::TestCase
  test "replace and destroy" do
    old_tag = tags(:one)
    new_tag = tags(:two)

    assert_difference "Tag.count", -1 do
      old_tag.replace_and_destroy!(new_tag)
    end

    old_tag.transactions.each do |txn|
      txn.reload
      assert_includes txn.tags, new_tag
      assert_not_includes txn.tags, old_tag
    end
  end

  test "rejects the reserved Untagged filter sentinel as a name" do
    tag = families(:dylan_family).tags.new(name: Tag::UNTAGGED_FILTER_VALUE, color: "#e99537")

    assert_not tag.valid?
    assert_includes tag.errors[:name], "is reserved"
  end

  test "filter_value returns the sentinel for the synthetic Untagged tag and the name for real tags" do
    assert_equal Tag::UNTAGGED_FILTER_VALUE, Tag.untagged.filter_value
    assert_equal tags(:one).name, tags(:one).filter_value
  end

  test "recent tags go by the date of their newest movement, not by when they were put on" do
    family = families(:dylan_family)
    recent = family.tags.create!(name: "Reciente prueba")
    old = family.tags.create!(name: "Antigua prueba")
    account = accounts(:depository)

    account.entries.create!(name: "Hoy", date: Date.current, amount: 10, currency: "USD", entryable: Transaction.new(tags: [ recent ]))
    travel_to 1.minute.from_now do
      account.entries.create!(name: "Hace dos años", date: 2.years.ago.to_date, amount: 10, currency: "USD", entryable: Transaction.new(tags: [ old ]))
    end

    ordered = family.tags.where(id: [ recent.id, old.id ]).recently_used.pluck("tags.id")
    assert_equal [ recent.id, old.id ], ordered
  end
end
