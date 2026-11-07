require "test_helper"

class QuickEntryTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @checking = accounts(:depository)
    @card = accounts(:credit_card)
  end

  test "reads Spanish and plain amounts" do
    assert_equal BigDecimal("12"), quick("12 café").amount
    assert_equal BigDecimal("12.5"), quick("12,50 café").amount
    assert_equal BigDecimal("12.5"), quick("12.5 café").amount
    assert_equal BigDecimal("1250"), quick("1.250 nómina").amount
    assert_equal BigDecimal("1250.5"), quick("1.250,50 € nómina").amount
    assert_equal BigDecimal("3.2"), quick("pan 3,20€").amount
  end

  test "an expense unless marked as income" do
    assert_not quick("12 café").income?
    assert quick("+1.250 nómina").income?
    assert quick("cobro 40 bizum").income?
  end

  test "the name is what is left, keeping accents" do
    assert_equal "Café con Ana", quick("12 café con Ana").name
    I18n.with_locale(:es) { assert_equal "Gasto", quick("12").name }
    assert_equal "Nómina", quick("+1.250 nómina").name
  end

  test "a word naming a single account picks it and leaves the name" do
    entry = quick("35,90 gasolina credit")

    assert_equal @card, entry.account
    assert_equal "Gasolina", entry.name
  end

  test "a word shared by several accounts does not pick any" do
    @user.family.accounts.create!(name: "Savings Account", owner: @user, balance: 0, currency: "USD", accountable: Depository.new)
    @user.update!(default_account: @checking)

    entry = quick("20 account")

    assert_equal @checking, entry.account
    assert_equal "Account", entry.name
  end

  test "never guesses an account that is not cash or a card" do
    entry = quick("40 honda")

    assert_includes Account::MOVABLE_TRANSACTION_TYPES, entry.account.accountable_type
    assert_equal "Honda", entry.name
  end

  test "an explicit account wins over any word" do
    entry = quick("35 credit", account_id: @checking.id)

    assert_equal @checking, entry.account
  end

  test "an unknown explicit account is an error" do
    entry = quick("35 café", account_id: SecureRandom.uuid)

    assert_not entry.save
    assert_includes entry.errors.full_messages, I18n.t("quick_entries.errors.account_missing")
  end

  test "saves an expense that borrows the category and merchant of the last one with that name" do
    entry = quick("4,50 starbucks", account_id: @checking.id)

    assert_difference -> { @checking.entries.count }, 1 do
      assert entry.save
    end

    saved = entry.entry
    assert_equal "Starbucks", saved.name
    assert_equal BigDecimal("4.5"), saved.amount
    assert_equal Date.current, saved.date
    assert_equal categories(:food_and_drink), saved.transaction.category
    assert_equal merchants(:amazon), saved.transaction.merchant
    assert_includes entry.summary, "Starbucks"
  end

  test "saves income with a negative amount" do
    entry = quick("+1.250 nómina", account_id: @checking.id)

    assert entry.save
    assert_equal BigDecimal("-1250"), entry.entry.amount
  end

  test "without an amount it does not save" do
    entry = quick("café")

    assert_no_difference -> { Entry.count } do
      assert_not entry.save
    end
    assert_includes entry.errors.full_messages, I18n.t("quick_entries.errors.amount_missing")
  end

  private
    def quick(text, account_id: nil)
      QuickEntry.new(user: @user, text: text, account_id: account_id)
    end
end
