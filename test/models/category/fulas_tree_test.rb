require "test_helper"

class Category::FulasTreeTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
  end

  test "creates every category under its parent, in order" do
    Category::FulasTree.new(@family).apply!

    Category::FulasTree::TREE.each_with_index do |(name, color, _icon, special, children), index|
      root = @family.categories.find_by!(name: name)
      assert_nil root.parent_id, "#{name} should be a root category"
      assert_equal color, root.color
      assert_equal index + 1, root.position
      assert_equal special, root.special

      children.each_with_index do |(child_name, _child_icon), child_index|
        child = @family.categories.find_by!(name: child_name)
        assert_equal root.id, child.parent_id, "#{child_name} should be under #{name}"
        assert_equal child_index + 1, child.position
      end
    end
  end

  test "marks Otros, Excluido and Traspasos as special, without subcategories" do
    Category::FulasTree.new(@family).apply!

    { "other" => "Otros", "excluded" => "Excluido", "transfers" => "Traspasos" }.each do |special, name|
      category = @family.categories.find_by!(special: special)
      assert_equal name, category.name
      assert_not category.parent?
    end
  end

  test "is idempotent" do
    Category::FulasTree.new(@family).apply!

    assert_no_difference "Category.count" do
      Category::FulasTree.new(@family).apply!
    end
  end

  test "finds a renamed special by its marker and keeps the family's changes" do
    Category::FulasTree.new(@family).apply!
    excluded = @family.categories.find_by!(special: "excluded")
    excluded.update!(name: "No contar", color: "#123456")

    assert_no_difference "Category.count" do
      Category::FulasTree.new(@family).apply!
    end

    excluded.reload
    assert_equal "No contar", excluded.name
    assert_equal "#123456", excluded.color
  end

  test "first rollout folds old default categories into their new equivalent" do
    healthcare = @family.categories.create!(name: I18n.t("models.category.defaults.healthcare", locale: :es), color: "#4da568", lucide_icon: "pill")
    entry = create_transaction(category: healthcare)

    Category::FulasTree.new(@family).apply!(first_rollout: true)

    target = @family.categories.find_by!(name: "Atención médica")
    assert_equal target, entry.transaction.reload.category
    assert_equal "Salud y educación", target.parent.name

    # The freed-up name is reused for the children's health subcategory,
    # and a second rollout doesn't fold it again.
    assert_equal "Niños", @family.categories.find_by!(name: "Salud").parent.name
    Category::FulasTree.new(@family).apply!(first_rollout: true)
    assert @family.categories.exists?(name: "Salud")
  end

  test "without first rollout, old default names are left alone" do
    income = categories(:income)

    Category::FulasTree.new(@family).apply!

    assert_equal "Income", income.reload.name
  end

  test "leaves categories outside the tree alone" do
    custom = categories(:one)

    Category::FulasTree.new(@family).apply!(first_rollout: true)

    assert_equal "Test", custom.reload.name
    assert_nil custom.parent_id
  end

  test "a transaction moved into Excluido is excluded, and moved out is included again" do
    Category::FulasTree.new(@family).apply!
    excluded = @family.categories.find_by!(special: "excluded")
    groceries = @family.categories.find_by!(name: "Supermercado")
    entry = create_transaction(category: groceries)

    entry.transaction.update!(category: excluded)
    assert entry.reload.excluded?

    entry.transaction.update!(category: groceries)
    assert_not entry.reload.excluded?
  end

  test "a transaction created in Excluido starts excluded" do
    Category::FulasTree.new(@family).apply!
    entry = create_transaction(category: @family.categories.find_by!(special: "excluded"))

    assert entry.reload.excluded?
  end

  test "leaving Excluido keeps an exclusion the user set by hand" do
    Category::FulasTree.new(@family).apply!
    groceries = @family.categories.find_by!(name: "Supermercado")
    entry = create_transaction(category: groceries)
    entry.update!(excluded: true)

    entry.transaction.update!(category: @family.categories.find_by!(special: "excluded"))
    entry.transaction.update!(category: groceries)

    assert entry.reload.excluded?
  end

  test "Traspasos leaves the transaction as it is" do
    Category::FulasTree.new(@family).apply!
    entry = create_transaction(category: @family.categories.find_by!(name: "Supermercado"))

    entry.transaction.update!(category: @family.categories.find_by!(special: "transfers"))

    assert entry.transaction.reload.standard?
    assert_not entry.reload.excluded?
  end
end
