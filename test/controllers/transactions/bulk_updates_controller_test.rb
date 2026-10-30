require "test_helper"

class Transactions::BulkUpdatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "bulk update" do
    transactions = @user.family.entries.transactions

    assert_difference [ "Entry.count", "Transaction.count" ], 0 do
      post transactions_bulk_update_url, params: {
        bulk_update: {
          entry_ids: transactions.map(&:id),
          date: 1.day.ago.to_date,
          category_id: Category.second.id,
          merchant_id: Merchant.second.id,
          tag_ids: [ Tag.first.id, Tag.second.id ],
          notes: "Updated note"
        }
      }
    end

    assert_redirected_to transactions_url
    assert_equal "#{transactions.count} transactions updated", flash[:notice]

    transactions.reload.each do |transaction|
      assert_equal 1.day.ago.to_date, transaction.date
      assert_equal Category.second, transaction.transaction.category
      assert_equal Merchant.second, transaction.transaction.merchant
      assert_equal "Updated note", transaction.notes
      assert_equal [ Tag.first.id, Tag.second.id ], transaction.entryable.tag_ids.sort
    end
  end

  test "bulk update preloads transaction records" do
    transaction_ids = @user.family.entries.transactions.limit(4).pluck(:id)

    queries = capture_sql_queries do
      post transactions_bulk_update_url, params: {
        bulk_update: {
          entry_ids: transaction_ids,
          notes: "Updated in bulk"
        }
      }
    end

    assert_redirected_to transactions_url
    assert_empty queries.grep(
      /SELECT "transactions"\.\* FROM "transactions" WHERE "transactions"\."id" =/
    )
  end

  test "bulk update preserves tags when tag_ids not provided" do
    transaction_entry = @user.family.entries.transactions.first
    original_tags = [ Tag.first, Tag.second ]
    transaction_entry.transaction.tags = original_tags
    transaction_entry.transaction.save!

    # Update only the category, without providing tag_ids
    post transactions_bulk_update_url, params: {
      bulk_update: {
        entry_ids: [ transaction_entry.id ],
        category_id: Category.second.id
      }
    }

    assert_redirected_to transactions_url

    transaction_entry.reload
    assert_equal Category.second, transaction_entry.transaction.category
    # Tags should be preserved since tag_ids was not in the request
    assert_equal original_tags.map(&:id).sort, transaction_entry.transaction.tag_ids.sort
  end

  test "bulk update clears tags when tag_ids is blank string array (web multi-select None)" do
    transaction_entry = @user.family.entries.transactions.first
    original_tags = [ Tag.first, Tag.second ]
    transaction_entry.transaction.tags = original_tags
    transaction_entry.transaction.save!

    # For a multiple select, choosing the blank ("None") option submits a blank value.
    post transactions_bulk_update_url, params: {
      bulk_update: {
        entry_ids: [ transaction_entry.id ],
        category_id: Category.second.id,
        tag_ids: [ "" ]
      }
    }

    assert_redirected_to transactions_url

    transaction_entry.reload
    assert_equal Category.second, transaction_entry.transaction.category
    assert_empty transaction_entry.transaction.tags
  end

  test "bulk update clears tags when empty tag_ids explicitly provided (JSON)" do
    transaction_entry = @user.family.entries.transactions.first
    transaction_entry.transaction.tags = [ Tag.first, Tag.second ]
    transaction_entry.transaction.save!

    post transactions_bulk_update_url,
         params: {
           bulk_update: {
             entry_ids: [ transaction_entry.id ],
             category_id: Category.second.id,
             tag_ids: []
           }
         },
         as: :json

    assert_redirected_to transactions_url

    transaction_entry.reload
    assert_equal Category.second, transaction_entry.transaction.category
    assert_empty transaction_entry.transaction.tags
  end

  test "bulk update replaces tags when tag_ids explicitly provided" do
    transaction_entry = @user.family.entries.transactions.first
    transaction_entry.transaction.tags = [ Tag.first ]
    transaction_entry.transaction.save!

    new_tag = Tag.second

    post transactions_bulk_update_url, params: {
      bulk_update: {
        entry_ids: [ transaction_entry.id ],
        tag_ids: [ new_tag.id ]
      }
    }

    assert_redirected_to transactions_url

    transaction_entry.reload
    assert_equal [ new_tag.id ], transaction_entry.transaction.tag_ids
  end

  test "bulk update makes the selected movements payments of one new recurring series, and excludes them" do
    account = accounts(:depository)
    entries = [ 3, 2, 1 ].map do |months|
      Entry.create!(account: account, name: "Apple.com", date: months.months.ago.to_date, amount: 4.99, currency: "USD",
                    entryable: Transaction.new)
    end

    assert_difference -> { RecurringTransaction.count } => 1 do
      post transactions_bulk_update_url, params: {
        bulk_update: { entry_ids: entries.map(&:id), recurring: "new", expense_type: "fixed", excluded: "1" }
      }
    end

    assert_redirected_to transactions_url
    series = RecurringTransaction.order(:created_at).last
    entries.each do |entry|
      entry.reload
      assert entry.excluded?
      assert_equal series, entry.transaction.recurring_series
      assert_equal "fixed", entry.transaction.expense_type
    end
  end

  test "bulk update links the selected movements to an existing recurring series" do
    account = accounts(:depository)
    first = Entry.create!(account: account, name: "Netflix", date: 2.months.ago.to_date, amount: 12.99, currency: "USD", entryable: Transaction.new)
    series = RecurringTransaction.create_from_transaction(first.transaction)
    second = Entry.create!(account: account, name: "NETFLIX.COM", date: 1.month.ago.to_date, amount: 12.99, currency: "USD", entryable: Transaction.new)

    assert_no_difference -> { RecurringTransaction.count } do
      post transactions_bulk_update_url, params: { bulk_update: { entry_ids: [ first.id, second.id ], recurring: series.id } }
    end

    assert_equal series, first.reload.transaction.recurring_series
    assert_equal series, second.reload.transaction.recurring_series
  end

  test "bulk update adds and removes tags, keeping the others, and marks movements as one-off" do
    account = accounts(:depository)
    keep, add, remove = Tag.first, @user.family.tags.create!(name: "Boda bulk"), @user.family.tags.create!(name: "Quitar bulk")
    entries = 2.times.map do |i|
      Entry.create!(account: account, name: "Compra #{i}", date: Date.current, amount: 20, currency: "USD",
                    entryable: Transaction.new(tags: [ keep, remove ]))
    end

    post transactions_bulk_update_url, params: {
      bulk_update: { entry_ids: entries.map(&:id), add_tag_ids: [ add.id ], remove_tag_ids: [ remove.id ], one_time: "1" }
    }

    entries.each do |entry|
      transaction = entry.reload.transaction
      assert_equal [ keep.id, add.id ].sort, transaction.tag_ids.sort
      assert transaction.one_time?
    end
  end

  test "bulk update links the selected expenses as payments of a loan" do
    loan_account = accounts(:loan)
    loan_account.loan.update!(interest_rate: 0, rate_type: "fixed", term_months: 12, initial_balance: 12_000, start_date: Date.new(2026, 1, 1))
    payments = [ Date.new(2026, 2, 1), Date.new(2026, 3, 1) ].map do |date|
      Entry.create!(account: accounts(:depository), name: "Cuota", date: date, amount: 1_000, currency: "USD", entryable: Transaction.new)
    end

    post transactions_bulk_update_url, params: { bulk_update: { entry_ids: payments.map(&:id), loan_account_id: loan_account.id } }

    payments.each { |entry| assert Loan::PaymentLink.exists?(entry_id: entry.id, loan_id: loan_account.loan.id) }
  end
end
