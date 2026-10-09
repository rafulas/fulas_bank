class DS::TagSelect < DesignSystemComponent
  attr_reader :form, :tags, :selected_ids, :attribute, :label, :show_label, :disabled,
              :auto_submit, :update_url, :menu_placement, :offset

  MENU_PLACEMENTS = %w[auto down up].freeze

  def initialize(form:, tags:, selected_ids:, attribute: :tag_ids, label: nil, show_label: true,
                 disabled: false, auto_submit: false, update_url: nil, menu_placement: :auto, offset: 6)
    @form = form
    @tags = tags
    @selected_ids = selected_ids.map(&:to_s)
    @attribute = attribute
    @label = label
    @show_label = show_label
    @disabled = disabled
    @auto_submit = auto_submit
    @update_url = update_url
    @menu_placement = normalize_menu_placement(menu_placement)
    @offset = offset
  end

  def field_name
    "#{form.object_name}[#{attribute}][]"
  end

  # Recently used tags first (when the caller passes a Tag relation), then the
  # rest alphabetically. Each tag appears once.
  def recent_tags
    grouped_tags.first
  end

  def other_tags
    grouped_tags.last
  end

  def show_group_headings?
    recent_tags.any? && other_tags.any?
  end

  def menu_id
    @menu_id ||= "tag_select_#{field_name.gsub(/\W+/, "_")}_#{object_id}"
  end

  private
    def grouped_tags
      @grouped_tags ||= if tags.respond_to?(:recent_and_rest)
        tags.recent_and_rest
      else
        [ [], tags.to_a ]
      end
    end


    def normalize_menu_placement(value)
      normalized = value.to_s.downcase
      MENU_PLACEMENTS.include?(normalized) ? normalized : "auto"
    end
end
