require "test_helper"

class Settings::FulasUpdatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @dir = Pathname(Dir.mktmpdir)
    File.write(@dir.join("latido"), Time.current.to_i.to_s)
    update = FulasUpdate.new(dir: @dir)
    FulasUpdate.stubs(:new).returns(update)
  end

  teardown do
    FileUtils.rm_rf(@dir)
  end

  test "an admin asks the server to update" do
    sign_in users(:family_admin)

    with_self_hosting do
      post settings_fulas_update_url(accion: "actualizar")
    end

    assert_redirected_to settings_hosting_url(anchor: "fulas-update")
    assert_equal "actualizar", File.read(@dir.join("peticion"))
  end

  test "a member cannot" do
    sign_in users(:family_member)

    with_self_hosting do
      post settings_fulas_update_url(accion: "actualizar")
    end

    assert_not File.exist?(@dir.join("peticion"))
  end
end
