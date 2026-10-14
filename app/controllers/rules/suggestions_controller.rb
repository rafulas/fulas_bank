# Fulas Bank: categorization rules suggested from the user's history (see
# Rule::Suggester), created with one click or dismissed.
class Rules::SuggestionsController < ApplicationController
  DISMISSED_PREFERENCE = "dismissed_rule_suggestions".freeze

  def show
    @suggestions = suggester.suggestions
    render layout: "settings"
  end

  def create
    chosen = params[:all] == "1" ? suggester.suggestions : [ suggester.find(params[:id].to_s) ].compact
    created = chosen.count do |suggestion|
      suggester.accept!(suggestion)
    rescue ActiveRecord::RecordInvalid
      false
    end

    redirect_to rule_suggestions_path, notice: t(".created", count: created)
  end

  def dismiss
    dismissed = (Current.user.preferences&.dig(DISMISSED_PREFERENCE) || []) | [ params[:id].to_s ]
    Current.user.update_dashboard_preferences(DISMISSED_PREFERENCE => dismissed.last(500))
    redirect_to rule_suggestions_path, notice: t(".dismissed")
  end

  private
    def suggester
      @suggester ||= Rule::Suggester.new(Current.family, entries: Current.accessible_entries,
                                         dismissed: Current.user.preferences&.dig(DISMISSED_PREFERENCE))
    end
end
