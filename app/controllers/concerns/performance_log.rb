# Fulas Bank: with FULAS_PERF_LOG set, one line in the log per page with
# where its time went: the database (how many queries and how long) and the
# slowest pieces of the page. Off by default; it is for finding out why a
# page is slow on the server:
#
#   FULAS_PERF_LOG=1 docker compose up -d web
#   docker compose logs -f web | grep --line-buffered "\[perf\]"
#
# It writes as a warning, so it shows with the usual log level. The times of
# the pieces include the pieces inside them. Code can also name a step of
# its own work with a "part.fulas" notification (see Forecast#measure),
# listed apart under "pasos". Components (DS::Pill...) are listed with the
# partials, by class name, when the app booted with FULAS_PERF_LOG set.
module PerformanceLog
  extend ActiveSupport::Concern

  SLOWEST_PIECES = 6

  included do
    around_action :log_performance, if: -> { ENV["FULAS_PERF_LOG"].present? }
  end

  private
    def log_performance
      thread = Thread.current
      queries = 0
      query_ms = 0.0
      pieces = Hash.new(0.0)
      steps = Hash.new(0.0)

      # Notifications reach every thread's subscribers: count only this
      # request's, which run in its own thread.
      subscribers = [
        ActiveSupport::Notifications.subscribe("sql.active_record") do |event|
          next unless Thread.current == thread
          next if event.payload[:name] == "SCHEMA" || event.payload[:cached]

          queries += 1
          query_ms += event.duration
        end,
        ActiveSupport::Notifications.subscribe(/\Arender_(partial|collection)\.action_view\z/) do |event|
          next unless Thread.current == thread

          pieces[performance_piece_name(event.payload[:identifier])] += event.duration
        end,
        ActiveSupport::Notifications.subscribe("render.view_component") do |event|
          next unless Thread.current == thread

          pieces[event.payload[:name].to_s] += event.duration
        end,
        ActiveSupport::Notifications.subscribe("part.fulas") do |event|
          next unless Thread.current == thread

          steps[event.payload[:part].to_s] += event.duration
        end
      ]

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      subscribers&.each { |subscriber| ActiveSupport::Notifications.unsubscribe(subscriber) }

      if started
        total = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
        slowest = pieces.sort_by { |_, ms| -ms }.first(SLOWEST_PIECES).map { |name, ms| "#{name} #{ms.round}ms" }
        line = "[perf] #{request.method} #{request.fullpath.truncate(80)} #{total.round}ms" \
               " · SQL #{queries} consultas #{query_ms.round}ms · más lento: #{slowest.join(", ")}"
        line += " · pasos: #{steps.map { |name, ms| "#{name} #{ms.round}ms" }.join(", ")}" if steps.any?
        Rails.logger.warn(line)
      end
    end

    # Names a step of an action's own work for the [perf] line ("pasos").
    # Without FULAS_PERF_LOG nobody listens, and it only runs the block.
    def performance_step(name, &block)
      ActiveSupport::Notifications.instrument("part.fulas", part: name, &block)
    end

    # "app/views/transactions/_transaction.html.erb" from the full path.
    def performance_piece_name(identifier)
      identifier.to_s.sub(%r{\A.*?/app/views/}, "").sub(/\.html\.erb\z/, "")
    end
end
