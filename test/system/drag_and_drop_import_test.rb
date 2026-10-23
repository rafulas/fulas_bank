require "application_system_test_case"

class DragAndDropImportTest < ApplicationSystemTestCase
  setup do
    sign_in users(:family_admin)
  end

  test "upload csv via hidden input on transactions index" do
    visit transactions_path

    assert_selector "#transactions[data-controller*='drag-and-drop-import']"

    # We can't easily simulate a true native drag-and-drop in headless chrome via Capybara without complex JS.
    # However, we can verify that the hidden form exists and works when a file is "dropped" (input populated).
    # The Stimulus controller's job is just to transfer the dropped file to the input and submit.

    file_path = file_fixture("imports/transactions.csv")

    # Manually make form and input visible
    execute_script("
      var form = document.querySelector('form[action=\"#{smart_imports_path}\"]');
      form.classList.remove('hidden');
      var input = document.querySelector('input[name=\"file\"]');
      input.classList.remove('hidden');
      input.style.display = 'block';
    ")

    attach_file "file", file_path

    # Submit the form manually since we bypassed the 'drop' event listener which triggers submit
    find("form[action='#{smart_imports_path}']").evaluate_script("this.requestSubmit()")

    # Fulas Bank: the file goes to the smart import, which lands on the
    # configuration step when it knows the account, or asks which one first.
    assert_current_path(%r{/imports/[^/]+/configuration|/importar/[^/]+/edit})
  end

  # Fulas Bank: «Importar cualquier archivo» waited for the hidden file input
  # to blur, which never happens, so choosing a file did nothing. Choosing it
  # must submit the form on its own.
  test "choosing a file in «Importar cualquier archivo» uploads it" do
    visit new_import_path

    attach_file "file", file_fixture("imports/transactions.csv"), make_visible: true

    assert_current_path(%r{/imports/[^/]+/configuration|/importar/[^/]+/edit})
  end
end
