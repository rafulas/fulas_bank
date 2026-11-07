# Fulas Bank: the weekly and monthly recaps (see Recap), like Bilance's
# "Resumen de octubre". The written report loads apart (#report) because it
# may wait on the LLM.
class RecapsController < ApplicationController
  WEEKS_LISTED = 8
  MONTHS_LISTED = 6

  before_action :set_recap, only: %i[show report]

  def index
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("recaps.index.title"), nil ] ]
    @weeks = listed(Recap.for(Current.family, user: Current.user, kind: "week", date: Date.current), WEEKS_LISTED)
    @months = listed(Recap.for(Current.family, user: Current.user, kind: "month", date: Date.current), MONTHS_LISTED)
  end

  def show
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("recaps.index.title"), recaps_path ], [ @recap.title, nil ] ]
  end

  def report
    @report = Recap::Report.new(@recap).result
    render partial: "recaps/report", locals: { recap: @recap, report: @report }
  end

  private
    def set_recap
      @recap = Recap.from_param(Current.family, params[:id], user: Current.user)
      raise ActiveRecord::RecordNotFound unless @recap&.started?
    end

    # The running period first, then the ones before it.
    def listed(recap, count)
      Array.new(count) { |index| index.zero? ? recap : (recap = recap.previous) }
    end
end
