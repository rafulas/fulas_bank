require "test_helper"

class Transactions::BulkDeletionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @entry = entries(:transaction)
  end

  test "bulk delete" do
    transactions = @user.family.entries.transactions
    delete_count = transactions.size

    assert_difference([ "Transaction.count", "Entry.count" ], -delete_count) do
      post transactions_bulk_deletion_url, params: {
        bulk_delete: {
          entry_ids: transactions.pluck(:id)
        }
      }
    end

    assert_redirected_to transactions_url
    assert_equal "#{delete_count} transactions deleted", flash[:notice]
  end

  test "deleting a transfer from the list deletes both of its movements" do
    transfer = transfers(:one)
    transfer.update!(status: "confirmed")
    outflow = transfer.outflow_transaction.entry
    inflow = transfer.inflow_transaction.entry

    assert_difference -> { Entry.count }, -2 do
      post transactions_bulk_deletion_url, params: { bulk_delete: { entry_ids: [ outflow.id ] } }
    end

    assert_not Entry.exists?(inflow.id)
    assert_not Transfer.exists?(transfer.id)
  end

  test "bulk delete with rejected transfers" do
    entry = entries(:transaction)
    other_entry = entries(:transfer_out)

    # Create a rejected_transfer referencing the entry's transaction
    RejectedTransfer.create!(
      inflow_transaction: entry.entryable,
      outflow_transaction: other_entry.entryable
    )

    assert_difference "RejectedTransfer.count", -1 do
      assert_difference [ "Transaction.count", "Entry.count" ], -1 do
        post transactions_bulk_deletion_url, params: {
          bulk_delete: {
            entry_ids: [ entry.id ]
          }
        }
      end
    end

    assert_redirected_to transactions_url
    assert_equal "1 transaction deleted", flash[:notice]
  end
end
