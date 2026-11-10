# Fulas Bank: updating the app from the app itself (Ajustes › Autoalojamiento),
# from any device, as the Mac's «Actualizar ahora» does.
#
# The app cannot restart itself, so it only leaves a request in its storage
# folder (a Docker volume). On the server, servidor/peticiones.sh looks every
# minute (cron): it takes the request and runs servidor/actualizar.sh, the
# same script the Mac runs (backup first, then the new version), and writes
# back how it went. Each minute it also leaves a heartbeat, so the app only
# offers the button where something will answer it.
#
#   storage/fulas/peticion  "actualizar" or "volver", written here
#   storage/fulas/estado    "<state> <action> <epoch> [<version>]", written by the server
#   storage/fulas/latido    the epoch of the server's last look
class FulasUpdate
  DIR = Rails.root.join("storage", "fulas")
  ACTIONS = %w[actualizar volver].freeze
  ALIVE_FOR = 5.minutes
  # An update that has not said how it ended after this was cut short.
  RUNNING_FOR = 30.minutes
  REPO = "rafulas/fulas_bank"
  API = "https://api.github.com/repos/#{REPO}".freeze

  Status = Data.define(:state, :action, :at, :version) do
    def running? = state == "en_curso" && at > RUNNING_FOR.ago
    def done? = state == "ok"
    def failed? = state == "error"
  end

  Change = Data.define(:number, :title)

  def initialize(dir: DIR)
    @dir = Pathname(dir)
  end

  # The server's listener looked recently: a request will be answered.
  def available?(now: Time.current)
    seen = read("latido").to_i
    seen.positive? && Time.zone.at(seen) > now - ALIVE_FOR
  end

  def pending
    action = read("peticion").to_s.strip
    action if ACTIONS.include?(action)
  end

  # @return [Status, nil]
  def status
    state, action, epoch, version = read("estado").to_s.split
    return if state.blank?

    action = "actualizar" unless ACTIONS.include?(action)
    Status.new(state: state, action: action, at: Time.zone.at(epoch.to_i), version: version)
  end

  def busy?
    pending.present? || status&.running?
  end

  def current_version
    ENV["BUILD_COMMIT_SHA"].presence
  end

  # The newest version GitHub has finished building (the image the server
  # would download), as the Mac's aviso.sh reads it.
  def latest_version
    Rails.cache.fetch("fulas_update/latest", expires_in: 10.minutes, skip_nil: true) do
      runs = get("/actions/workflows/fulas-imagen.yml/runs?branch=main&status=success&per_page=1")
      runs&.dig("workflow_runs", 0, "head_sha")
    end
  end

  def update_available?
    latest = latest_version
    latest.present? && current_version.present? && latest != current_version && changes.any?
  end

  # The pull requests merged since the running version, newest last. Empty
  # when the running version is not older (or GitHub cannot be reached).
  # @return [Array<Change>]
  def changes
    return [] if current_version.blank? || latest_version.blank? || current_version == latest_version

    @changes ||= Rails.cache.fetch("fulas_update/changes/#{current_version}/#{latest_version}", expires_in: 1.hour, skip_nil: true) do
      compare = get("/compare/#{current_version}...#{latest_version}")
      next nil unless compare
      next [] unless compare["status"] == "ahead" || compare["status"] == "diverged"

      merges = Array(compare["commits"]).filter_map do |commit|
        message = commit.dig("commit", "message").to_s
        number = message[/\AMerge pull request #(\d+)/, 1]
        Change.new(number: number.to_i, title: message.lines[2].to_s.strip.presence || "—") if number
      end
      merges.presence || [ Change.new(number: nil, title: I18n.t("settings.hostings.fulas_update.improvements")) ]
    end || []
  end

  # Leaves the request for the server. @return [Boolean]
  def request!(action)
    return false unless ACTIONS.include?(action) && available? && !busy?

    FileUtils.mkdir_p(@dir)
    tmp = @dir.join("peticion.#{SecureRandom.hex(4)}")
    File.write(tmp, action)
    File.rename(tmp, @dir.join("peticion"))
    true
  end

  private
    def read(name)
      File.read(@dir.join(name))
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end

    def get(path)
      response = Faraday.new(url: "#{API}/", request: { timeout: 5, open_timeout: 3 }).get(path.delete_prefix("/")) do |request|
        request.headers["Accept"] = "application/vnd.github+json"
        request.headers["User-Agent"] = "FulasBank"
      end
      response.success? ? JSON.parse(response.body) : nil
    rescue Faraday::Error, JSON::ParserError
      nil
    end
end
