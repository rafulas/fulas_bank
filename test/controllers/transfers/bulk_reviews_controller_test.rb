require "test_helper"

class Transfers::BulkReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @transfer = transfers(:one)
    @transfer.update!(status: "pending")
    @entry = @transfer.outflow_transaction.entry
  end

  test "confirms the selected auto-matched transfers" do
    post transfers_bulk_review_url, params: { bulk_transfer: { status: "confirmed", entry_ids: [ @entry.id ] } }

    assert_redirected_to transactions_url
    assert @transfer.reload.confirmed?
  end

  test "rejects them, unpairing the movements" do
    post transfers_bulk_review_url, params: { bulk_transfer: { status: "rejected", entry_ids: [ @entry.id ] } }

    assert_not Transfer.exists?(@transfer.id)
    assert RejectedTransfer.exists?(inflow_transaction_id: @transfer.inflow_transaction_id, outflow_transaction_id: @transfer.outflow_transaction_id)
  end

  test "leaves a confirmed transfer and other families' movements alone" do
    @transfer.update!(status: "confirmed")
    post transfers_bulk_review_url, params: { bulk_transfer: { status: "rejected", entry_ids: [ @entry.id ] } }
    assert Transfer.exists?(@transfer.id)

    post transfers_bulk_review_url, params: { bulk_transfer: { status: "deleted", entry_ids: [ @entry.id ] } }
    assert_response :unprocessable_entity
  end
end
