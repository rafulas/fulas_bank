require "test_helper"

class FulasUpdateTest < ActiveSupport::TestCase
  setup do
    @dir = Pathname(Dir.mktmpdir)
    @update = FulasUpdate.new(dir: @dir)
  end

  teardown do
    FileUtils.rm_rf(@dir)
  end

  test "it is offered only while the server's listener answers" do
    assert_not @update.available?

    File.write(@dir.join("latido"), 2.minutes.ago.to_i.to_s)
    assert @update.available?

    File.write(@dir.join("latido"), 10.minutes.ago.to_i.to_s)
    assert_not @update.available?
  end

  test "a request is left for the server, once" do
    File.write(@dir.join("latido"), Time.current.to_i.to_s)

    assert @update.request!("actualizar")
    assert_equal "actualizar", File.read(@dir.join("peticion"))
    assert @update.busy?
    assert_not @update.request!("volver"), "one at a time"
    assert_not FulasUpdate.new(dir: @dir).request!("otra cosa")
  end

  test "nothing is requested when the server does not answer" do
    assert_not @update.request!("actualizar")
    assert_not File.exist?(@dir.join("peticion"))
  end

  test "reads how the server says it went" do
    File.write(@dir.join("estado"), "en_curso actualizar #{1.minute.ago.to_i}\n")
    assert @update.status.running?
    assert @update.busy?

    File.write(@dir.join("estado"), "en_curso actualizar #{2.hours.ago.to_i}\n")
    assert_not @update.status.running?, "an update silent for so long was cut short"

    File.write(@dir.join("estado"), "ok actualizar #{1.minute.ago.to_i} abcdef1234\n")
    status = @update.status
    assert status.done?
    assert_equal "abcdef1234", status.version
  end

  test "lists the pull requests merged since the running version" do
    @update.stubs(:current_version).returns("aaa111")
    @update.stubs(:get).with("/actions/workflows/fulas-imagen.yml/runs?branch=main&status=success&per_page=1")
           .returns("workflow_runs" => [ { "head_sha" => "bbb222" } ])
    @update.stubs(:get).with("/compare/aaa111...bbb222").returns(
      "status" => "ahead",
      "commits" => [
        { "commit" => { "message" => "Merge pull request #170 from rafulas/calendario-anio\n\nCalendario: saltar a otro mes o año" } },
        { "commit" => { "message" => "Fix a test" } }
      ]
    )

    with_cache do
      assert @update.update_available?
      assert_equal [ [ 170, "Calendario: saltar a otro mes o año" ] ], @update.changes.map { |change| [ change.number, change.title ] }
    end
  end

  private
    def with_cache
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = original
    end
end
