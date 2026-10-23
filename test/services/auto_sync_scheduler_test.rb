require "test_helper"
require "ostruct"

class AutoSyncSchedulerTest < ActiveSupport::TestCase
  test "keeps the configured local sync time across daylight saving changes" do
    Setting.stubs(:auto_sync_time).returns("06:30")
    Setting.stubs(:auto_sync_timezone).returns("Europe/Madrid")

    job = OpenStruct.new(valid?: true)

    cron = "30 6 * * * Europe/Madrid"
    Sidekiq::Cron::Job.expects(:create).with(has_entries(name: AutoSyncScheduler::JOB_NAME, cron: cron)).returns(job)

    AutoSyncScheduler.upsert_job

    # 06:30 in Madrid is 05:30 UTC in winter and 04:30 UTC in summer.
    schedule = Fugit.parse_cron(cron)
    assert_equal "Europe/Madrid", schedule.zone
    assert_equal Time.utc(2026, 1, 1, 5, 30), schedule.next_time(Time.utc(2026, 1, 1)).to_t.utc
    assert_equal Time.utc(2026, 7, 1, 4, 30), schedule.next_time(Time.utc(2026, 7, 1)).to_t.utc
  end
end
