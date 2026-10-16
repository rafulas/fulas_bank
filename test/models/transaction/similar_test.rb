require "test_helper"

class Transaction::SimilarTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
  end

  test "movements from the same merchant or with the same name, newest first" do
    mercadona = @family.merchants.create!(name: "Mercadona")
    entry = create_transaction(account: @account, name: "Mercadona online", amount: 120, date: 2.days.ago.to_date, merchant: mercadona)
    older = create_transaction(account: @account, name: "MERCADONA VALENCIA", amount: 80, date: 40.days.ago.to_date, merchant: mercadona)
    newer = create_transaction(account: @account, name: "mercadona online ", amount: 60, date: 1.day.ago.to_date)
    other = create_transaction(account: @account, name: "Lidl", amount: 30, date: 3.days.ago.to_date)

    similar = Transaction::Similar.new(entry, scope: @family.entries).entries

    assert_equal [ newer, older ], similar.select { |candidate| [ newer, older, other ].include?(candidate) }
    assert_not_includes similar, entry
    assert_not_includes similar, other
  end
end
