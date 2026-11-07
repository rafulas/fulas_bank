# frozen_string_literal: true

# Fulas Bank: the "apunte exprés" for iOS Shortcuts and Siri. Takes a
# movement written in plain words ("12 café") and records it; see QuickEntry.
# The response carries a ready-to-speak `message` for the Shortcut.
class Api::V1::QuickEntriesController < Api::V1::BaseController
  before_action :ensure_write_scope

  def create
    I18n.with_locale(user_locale) do
      date = parse_date
      if date == :invalid
        render_validation_error(I18n.t("quick_entries.errors.invalid_date"))
        return
      end

      quick_entry = QuickEntry.new(
        user: current_resource_owner,
        text: params[:text],
        date: date,
        account_id: params[:account_id]
      )

      if quick_entry.save
        entry = quick_entry.entry
        render json: {
          id: entry.transaction.id,
          entry_id: entry.id,
          name: entry.name,
          date: entry.date.iso8601,
          amount: entry.amount_money.abs.format,
          signed_amount: entry.amount.to_s,
          currency: entry.currency,
          nature: quick_entry.income? ? "income" : "expense",
          account: { id: entry.account.id, name: entry.account.name },
          category: entry.transaction.category && { id: entry.transaction.category.id, name: entry.transaction.category.name },
          message: quick_entry.summary
        }, status: :created
      else
        render_validation_error(quick_entry.errors.full_messages.first, quick_entry.errors.full_messages)
      end
    end
  end

  private
    def ensure_write_scope
      authorize_scope!(:write)
    end

    def user_locale
      [ current_resource_owner.locale, current_resource_owner.family.locale ]
        .compact_blank.map(&:to_sym).find { |locale| I18n.available_locales.include?(locale) } || I18n.locale
    end

    def parse_date
      return if params[:date].blank?

      Date.iso8601(params[:date].to_s)
    rescue ArgumentError
      :invalid
    end

    def render_validation_error(message, errors = [ message ])
      render json: { error: "validation_failed", message: message, errors: errors }, status: :unprocessable_entity
    end
end
