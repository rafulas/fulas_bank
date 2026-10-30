require "application_system_test_case"

class TransactionsTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)

    Entry.delete_all # clean slate

    create_transaction("one", 12.days.ago.to_date, 100)
    create_transaction("two", 10.days.ago.to_date, 100)
    create_transaction("three", 9.days.ago.to_date, 100)
    create_transaction("four", 8.days.ago.to_date, 100)
    create_transaction("five", 7.days.ago.to_date, 100)
    create_transaction("six", 7.days.ago.to_date, 100)
    create_transaction("seven", 4.days.ago.to_date, 100)
    create_transaction("eight", 3.days.ago.to_date, 100)
    create_transaction("nine", 1.days.ago.to_date, 100)
    @uncategorized_transaction = create_transaction("ten", 1.days.ago.to_date, 100)
    create_transaction("eleven", Date.current, 100, category: categories(:food_and_drink), tags: [ tags(:one) ], merchant: merchants(:amazon))

    @transactions = @user.family.entries
                         .transactions
                         .reverse_chronological

    @transaction = @transactions.first

    @page_size = 10

    visit transactions_url(per_page: @page_size)
  end

  test "can search for a transaction" do
    assert_selector "h1", text: "Transactions"

    within "form#transactions-search" do
      fill_in "q_search", with: @transaction.name
      find("#q_search").send_keys(:tab) # Trigger blur to submit form
    end

    assert_selector "#" + dom_id(@transaction), count: 1

    within "#transaction-search-filters" do
      assert_text @transaction.name
    end
  end

  # Fulas Bank: account, category, dates and type have their own buttons in
  # the filter bar; the rest is under "More filters".
  test "can open filters and apply one or more" do
    find("#transaction-account-button").click
    within "#transaction-account-menu" do
      check(@transaction.account.name)
      click_button "Apply"
    end

    # Wait for the page with the account filter before opening the next one.
    within "#transaction-search-filters" do
      assert_text @transaction.account.name
    end

    find("#transaction-category-button").click
    within "#transaction-category-menu" do
      check(@transaction.transaction.category.name)
      click_button "Apply"
    end

    assert_selector "#" + dom_id(@transaction), count: 1

    within "#transaction-search-filters" do
      assert_text @transaction.account.name
      assert_text @transaction.transaction.category.name
    end
  end

  test "can filter uncategorized transactions" do
    find("#transaction-category-button").click

    within "#transaction-category-menu" do
      check("Uncategorized")
      click_button "Apply"
    end

    assert_selector "#" + dom_id(@uncategorized_transaction), count: 1
    assert_no_selector("#" + dom_id(@transaction))
    within "#transaction-search-filters" do
      assert_text "Uncategorized"
    end

    find("#transaction-category-button").click

    within "#transaction-category-menu" do
      check(@transaction.transaction.category.name)
      click_button "Apply"
    end

    assert_selector "#" + dom_id(@transaction), count: 1
    assert_selector "#" + dom_id(@uncategorized_transaction), count: 1
  end

  test "the period and type buttons filter the list" do
    find("#transaction-period-button").click
    # Fulas Bank: the custom range opens the calendar, where the dates can
    # be tapped or typed.
    within "#transaction-period-menu" do
      click_button "Custom range"
      fill_in "transaction-period-menu-from", with: 2.days.ago.to_date
      fill_in "transaction-period-menu-to", with: Date.current
      click_button "Apply"
    end

    assert_selector "#" + dom_id(@transaction), count: 1
    assert_no_text "seven"

    within "[aria-label='Type']" do
      click_link "Income"
    end
    assert_text "No entries found"

    within "[aria-label='Type']" do
      click_link "All"
    end
    assert_selector "#" + dom_id(@transaction), count: 1
  end

  test "the period picker applies a shortcut and all time at once" do
    find("#transaction-period-button").click
    within("#transaction-period-menu") { click_button "Last 30 days" }

    assert_selector "#transaction-period-button", text: (Date.current - 29).strftime("%d/%m/%Y")

    find("#transaction-period-button").click
    within("#transaction-period-menu") { click_button "All time" }
    assert_selector "#transaction-period-button", text: I18n.t("transactions.searches.bar.periods.all")
  end

  test "all filters work and empty state shows if no match" do
    account = @transaction.account
    category = @transaction.transaction.category
    merchant = @transaction.transaction.merchant

    visit transactions_url(q: {
      accounts: [ account.name ], categories: [ category.name ], types: [ "income" ],
      start_date: 10.days.ago.to_date, end_date: 1.day.ago.to_date
    })

    find("#transaction-filters-button").click

    within "#transaction-filters-menu" do
      click_button "Amount"
      select "Less than"
      fill_in "q_amount", with: 200

      click_button "Merchant"
      check(merchant.name)

      click_button "Apply"
    end

    assert_text "No entries found"

    # Wait for Turbo to finish updating the DOM
    sleep 0.5

    # Page reload doesn't affect results
    visit current_url

    assert_text "No entries found"

    # Remove all filters by clicking their X buttons
    # Get all the filter buttons at once to avoid stale elements
    filter_count = page.all("ul#transaction-search-filters li button").count

    # Click each one with a small delay to let Turbo update
    filter_count.times do
      page.all("ul#transaction-search-filters li button").first.click
      sleep 0.1
    end

    assert_text @transaction.name
  end

  test "can tick several tags from the transaction row and save them at once" do
    transaction = @transaction.entryable
    summary_id = dom_id(transaction, "tag_summary_desktop")
    option_id = "#{dom_id(@transaction, :tag_option)}_#{tags(:two).id}"
    checkbox_id = "#{dom_id(@transaction, :tag_checkbox)}_#{tags(:two).id}"

    within "##{summary_id}" do
      assert_text tags(:one).name
    end

    find("##{summary_id}").click
    find("##{checkbox_id}").click

    # Ticking only changes the form; nothing is saved until "Save".
    assert_equal [ tags(:one).id ], transaction.reload.tag_ids

    find("##{option_id}").ancestor("form").find("[data-tag-dropdown-save]").click

    assert_selector "##{summary_id} [data-tag-fit-target=compact] [data-tag-more]", text: "+1", visible: :all
    assert_equal [ tags(:one).id, tags(:two).id ].sort, transaction.reload.tag_ids.sort
  end

  test "every tag shows when they fit and they collapse to the first one and a count when the column shrinks" do
    transaction = @transaction.entryable
    short_tags = %w[Ab Cd].map { |name| @user.family.tags.create!(name: name, color: Tag::COLORS.first) }
    transaction.update!(tag_ids: short_tags.map(&:id))
    visit transactions_url(per_page: @page_size)

    summary = "##{dom_id(transaction, "tag_summary_desktop")}"
    cell = "document.querySelector('#{summary}').closest('[data-tag-fit-bounds]')"

    page.execute_script("#{cell}.style.width = '400px'")
    assert_selector "#{summary} [data-tag-fit-target=full]", text: "Ab"
    assert_no_selector "#{summary} [data-tag-fit-target=compact]"

    page.execute_script("#{cell}.style.width = '48px'")
    assert_selector "#{summary} [data-tag-fit-target=compact] [data-tag-more]", text: "+1"
    assert_no_selector "#{summary} [data-tag-fit-target=full]"

    page.execute_script("#{cell}.style.width = '400px'")
    assert_selector "#{summary} [data-tag-fit-target=full]", text: "Cd"
  end

  test "a first tag added on desktop also shows on the mobile row" do
    transaction = @uncategorized_transaction.entryable
    assert_empty transaction.tags
    option_id = "#{dom_id(@uncategorized_transaction, :tag_option)}_#{tags(:one).id}"
    checkbox_id = "#{dom_id(@uncategorized_transaction, :tag_checkbox)}_#{tags(:one).id}"

    find("##{dom_id(@uncategorized_transaction)}").hover
    find("##{dom_id(transaction, "tag_summary_desktop")}").click
    find("##{checkbox_id}").click
    find("##{option_id}").ancestor("form").find("[data-tag-dropdown-save]").click
    assert_selector "##{dom_id(transaction, "tag_summary_desktop")}", text: tags(:one).name

    page.current_window.resize_to(390, 900)
    assert_selector "##{dom_id(transaction, "tag_summary_mobile")}", text: tags(:one).name
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  test "can select and deselect entire page of transactions" do
    all_transactions_checkbox.check
    assert_selection_count(number_of_transactions_on_page)
    all_transactions_checkbox.uncheck
    assert_selection_count(0)
  end

  test "can select and deselect groups of transactions" do
    date_transactions_checkbox(1.day.ago.to_date).check
    assert_selection_count(2)

    date_transactions_checkbox(1.day.ago.to_date).uncheck
    assert_selection_count(0)
  end

  test "can select and deselect individual transactions" do
    transaction_checkbox(@transactions.first).check
    assert_selection_count(1)
    transaction_checkbox(@transactions.second).check
    assert_selection_count(2)
    transaction_checkbox(@transactions.second).uncheck
    assert_selection_count(1)
  end

  test "outermost group always overrides inner selections" do
    transaction_checkbox(@transactions.first).check
    assert_selection_count(1)

    all_transactions_checkbox.check
    assert_selection_count(number_of_transactions_on_page)

    transaction_checkbox(@transactions.first).uncheck
    assert_selection_count(number_of_transactions_on_page - 1)

    date_transactions_checkbox(1.day.ago.to_date).uncheck
    assert_selection_count(number_of_transactions_on_page - 3)

    all_transactions_checkbox.uncheck
    assert_selection_count(0)
  end


  test "the calendar changes month without closing and stays inside the window" do
    # The new-transaction page on its own: an account page refreshes itself
    # (Turbo morph) just after it loads, which would close the calendar.
    visit new_transaction_path

    calendar = "[data-controller='date-field'] [role='dialog']"
    find("button[aria-label='Open the calendar']").click
    month = find("#{calendar} span.font-semibold").text

    find("#{calendar} button[aria-label='Next month']").click
    find("#{calendar} button[aria-label='Next month']").click

    assert_selector calendar
    assert_no_selector "#{calendar} span.font-semibold", text: month, exact_text: true

    box = page.evaluate_script("(() => { const r = document.querySelector(\"[data-controller='date-field'] [role='dialog']\").getBoundingClientRect(); return [r.top, r.bottom, window.innerHeight]; })()")
    assert_operator box[0], :>=, 0
    assert_operator box[1], :<=, box[2], "the calendar is not cut off at the bottom"

    find("#{calendar} button[aria-label^='15 ']").click
    assert_no_selector calendar
    target = Date.current.beginning_of_month.next_month(2).change(day: 15)
    assert_equal target.iso8601, find("input[type='date'][name='entry[date]']").value
  end

  test "can create deposit transaction for investment account" do
    investment_account = accounts(:investment)
    investment_account.entries.create!(name: "Investment account", date: Date.current, amount: 1000, currency: "USD", entryable: Transaction.new)
    transfer_date = Date.current
    visit account_url(investment_account, tab: "activity")
    within "[data-testid='activity-menu']" do
      click_on "New"
      click_on "New activity"
    end
    select "Deposit", from: "Type"
    fill_in "Date", with: transfer_date
    fill_in "model[amount]", with: 175.25
    click_button "Add transaction"
    within "#" + dom_id(investment_account, "entries_#{transfer_date}") do
      assert_text "175.25"
    end
  end

  test "transfers should always sum to zero" do
    # Use two accounts that result in funds_movement kind (not investment/crypto which become investment_contribution)
    asset_account = accounts(:other_asset)
    depository_account = accounts(:depository)
    outflow_entry = create_transaction("outflow", Date.current, 500, account: asset_account)
    inflow_entry = create_transaction("inflow", 1.day.ago.to_date, -500, account: depository_account)
    @user.family.auto_match_transfers!
    visit transactions_url

    within "#entry-group-" + Date.current.to_s + "-totals" do
      assert_text "-$100.00" # transaction eleven from setup
    end
  end

  private

    def create_transaction(name, date, amount, category: nil, merchant: nil, tags: [], account: nil)
      account ||= accounts(:depository)

      account.entries.create! \
        name: name,
        date: date,
        amount: amount,
        currency: "USD",
        entryable: Transaction.new(category: category, merchant: merchant, tags: tags)
    end

    def number_of_transactions_on_page
      [ @user.family.entries.count, @page_size ].min
    end

    def all_transactions_checkbox
      find("#selection_entry")
    end

    def date_transactions_checkbox(date)
      find("#selection_entry_#{date}")
    end

    def transaction_checkbox(transaction)
      find("#" + dom_id(transaction, "selection"))
    end

    def assert_selection_count(count)
      if count == 0
        assert_no_selector("#entry-selection-bar")
      else
        within "#entry-selection-bar" do
          assert_text "#{count} transaction#{count == 1 ? "" : "s"} selected"
        end
      end
    end
end
