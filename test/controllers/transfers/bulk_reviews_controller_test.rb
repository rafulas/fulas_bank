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

  test "from the list, both movements are drawn again in place" do
    post transfers_bulk_review_url, params: { bulk_transfer: { status: "confirmed", entry_ids: [ @entry.id ] } }, as: :turbo_stream

    assert_response :success
    [ @transfer.outflow_transaction.entry, @transfer.inflow_transaction.entry ].each do |entry|
      assert_select "turbo-stream[action='replace'][target='#{ActionView::RecordIdentifier.dom_id(entry)}']"
    end
    assert_select "turbo-stream[action='update'][target='bulk_transaction_edit_drawer']"
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
