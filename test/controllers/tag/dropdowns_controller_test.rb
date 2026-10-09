require "test_helper"

class Tag::DropdownsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    sign_in users(:family_admin)
    @entry = entries(:transaction)
    @entry.entryable.update!(tag_ids: [ tags(:one).id ])
    ensure_tailwind_build
  end

  test "lists the family's tags as checkboxes with the applied ones ticked" do
    get tag_dropdown_url(entry_id: @entry.id)

    assert_response :success
    assert_select "form[action=?]", tags_transaction_path(@entry) do
      assert_select "##{dom_id(@entry, :tag_checkbox)}_#{tags(:one).id}[checked]"
      assert_select "##{dom_id(@entry, :tag_checkbox)}_#{tags(:two).id}:not([checked])"
      assert_select "input[type=hidden][name=?][value='']", "tag_ids[]"
      assert_select "[data-tag-dropdown-save]"
    end
  end

  test "shows the most recently used tags first" do
    family = @entry.account.family
    old_tag = family.tags.create!(name: "AAA antigua")
    never_used = family.tags.create!(name: "000 sin usar")
    @entry.entryable.update!(tag_ids: [ old_tag.id ])
    Tagging.where(tag: old_tag).update_all(created_at: 2.days.ago)
    @entry.entryable.taggings.create!(tag: tags(:two))

    get tag_dropdown_url(entry_id: @entry.id)

    assert_response :success
    ids = css_select("[data-tag-option]").map { |node| node["id"] }
    assert_equal "#{dom_id(@entry, :tag_option)}_#{tags(:two).id}", ids.first
    # Used once, long ago: still listed among the recent ones, ahead of the
    # alphabetical rest even though "000 sin usar" sorts first by name.
    assert_operator ids.index("#{dom_id(@entry, :tag_option)}_#{old_tag.id}"),
      :<, ids.index("#{dom_id(@entry, :tag_option)}_#{never_used.id}")
    assert_equal ids.uniq, ids, "each tag is listed once"
  end

  test "does not load another family's transaction" do
    other_entry = entries(:transaction)
    sign_in users(:empty)

    get tag_dropdown_url(entry_id: other_entry.id)

    assert_response :not_found
  end
end
