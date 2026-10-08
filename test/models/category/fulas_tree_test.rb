require "test_helper"

class Category::FulasTreeTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
  end

  test "creates every category under its parent" do
    Category::FulasTree.new(@family).apply!

    Category::FulasTree::TREE.each do |name, color, _icon, children|
      root = @family.categories.find_by!(name: name)
      assert_nil root.parent_id, "#{name} should be a root category"
      assert_equal color, root.color

      children.each do |child_name, _child_icon|
        child = @family.categories.find_by!(name: child_name)
        assert_equal root.id, child.parent_id, "#{child_name} should be under #{name}"
      end
    end
  end

  test "leaves Otros, Excluido and Traspasos without subcategories" do
    Category::FulasTree.new(@family).apply!

    Category::FulasTree::LEAF_ROOTS.each do |name|
      assert_not @family.categories.find_by!(name: name).parent?
    end
  end

  test "is idempotent" do
    Category::FulasTree.new(@family).apply!

    assert_no_difference "Category.count" do
      Category::FulasTree.new(@family).apply!
    end
  end

  test "folds old default categories into their new equivalent with their transactions" do
    healthcare = @family.categories.create!(name: I18n.t("models.category.defaults.healthcare", locale: :es), color: "#4da568", lucide_icon: "pill")
    entry = create_transaction(category: healthcare)

    Category::FulasTree.new(@family).apply!

    target = @family.categories.find_by!(name: "Atención médica")
    assert_equal target, entry.transaction.reload.category
    assert_equal "Salud y educación", target.parent.name

    # The freed-up name is reused for the children's health subcategory,
    # and a second run doesn't fold it again.
    assert_equal "Niños", @family.categories.find_by!(name: "Salud").parent.name
    Category::FulasTree.new(@family).apply!
    assert @family.categories.exists?(name: "Salud")
  end

  test "keeps old defaults that already match a tree name and moves them into place" do
    groceries = @family.categories.create!(name: "Supermercado", color: "#407706", lucide_icon: "shopping-bag")

    Category::FulasTree.new(@family).apply!

    assert_equal "Comida y bebida", groceries.reload.parent.name
  end

  test "leaves categories outside the tree alone" do
    custom = categories(:one)

    Category::FulasTree.new(@family).apply!

    assert_equal "Test", custom.reload.name
    assert_nil custom.parent_id
  end

  test "a transaction moved into Excluido is excluded, and moved out is included again" do
    Category::FulasTree.new(@family).apply!
    excluded = @family.categories.find_by!(name: "Excluido")
    groceries = @family.categories.find_by!(name: "Supermercado")
    entry = create_transaction(category: groceries)

    entry.transaction.update!(category: excluded)
    assert entry.reload.excluded?

    entry.transaction.update!(category: groceries)
    assert_not entry.reload.excluded?
  end

  test "a transaction created in Excluido starts excluded" do
    Category::FulasTree.new(@family).apply!
    entry = create_transaction(category: @family.categories.find_by!(name: "Excluido"))

    assert entry.reload.excluded?
  end

  test "leaving Excluido keeps an exclusion the user set by hand" do
    Category::FulasTree.new(@family).apply!
    groceries = @family.categories.find_by!(name: "Supermercado")
    entry = create_transaction(category: groceries)
    entry.update!(excluded: true)

    entry.transaction.update!(category: @family.categories.find_by!(name: "Excluido"))
    entry.transaction.update!(category: groceries)

    assert entry.reload.excluded?
  end

  test "Traspasos keeps a transaction out of analytics until it is recategorized" do
    Category::FulasTree.new(@family).apply!
    transfers = @family.categories.find_by!(name: "Traspasos")
    groceries = @family.categories.find_by!(name: "Supermercado")
    entry = create_transaction(category: groceries)

    entry.transaction.update!(category: transfers)
    assert entry.transaction.reload.one_time?
    assert_not entry.reload.excluded?

    entry.transaction.update!(category: groceries)
    assert entry.transaction.reload.standard?
  end
end
