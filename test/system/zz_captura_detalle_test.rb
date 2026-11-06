require "application_system_test_case"
require "base64"

# Temporary: a screenshot of a movement's detail at iPad size, to look at the
# layout. It fails on purpose so CI keeps the screenshot. Never merged.
class ZzCapturaDetalleTest < ApplicationSystemTestCase
  include ActionView::RecordIdentifier

  setup do
    sign_in users(:family_admin)
  end

  test "captura del detalle" do
    entry = entries(:transaction)
    dir = Rails.root.join("tmp/screenshots")
    FileUtils.mkdir_p(dir)

    [ [ "ipad", 834, 1112 ], [ "ordenador", 1440, 1000 ] ].each do |name, width, height|
      page.current_window.resize_to(width, height)
      visit transactions_url
      find("a[data-drawer-title='#{entry.name}']", match: :first).click
      assert_selector "dialog[open] ##{dom_id(entry, :header)}"
      sleep 1
      page.save_screenshot(dir.join("captura_#{name}_arriba.png"))
      page.execute_script("document.querySelector('dialog[open] .overflow-auto')?.scrollTo(0, 100000)")
      sleep 0.5
      page.save_screenshot(dir.join("captura_#{name}_abajo.png"))
      find("dialog[open] summary", text: /M[aá]s opciones|More options/i).click
      sleep 0.5
      page.execute_script("document.querySelector('dialog[open] .overflow-auto')?.scrollTo(0, 100000)")
      sleep 0.3
      page.save_screenshot(dir.join("captura_#{name}_mas_opciones.png"))
    end

    # The artifact storage is not reachable from where they are looked at:
    # the screenshots go out in the log, in base64 lines.
    Dir[dir.join("captura_*.png")].sort.each do |file|
      Base64.strict_encode64(File.binread(file)).scan(/.{1,8000}/).each_with_index do |chunk, index|
        puts "CAPTURA|#{File.basename(file)}|#{index}|#{chunk}"
      end
    end

    flunk "Solo para la captura"
  end
end
