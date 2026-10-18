# A label for a user-defined entity whose hue is data (a category, a tag):
# a small colored mark followed by plain text, instead of a tinted pill.
#
# - `mark: :square` (default) — a rounded square filled with the color and a
#   white Lucide `icon:` on it (a category).
# - `mark: :dot` — a small colored dot (a tag).
# - `mark: :none` — the text alone, when the mark is already shown nearby
#   (the transaction row has the category's square at its left).
# - `dashed: true` — an empty square with a dashed border, for "nothing
#   chosen yet" (an uncategorized movement): it calls for attention.
#
# `tinted: true` puts the label in a soft pill of its own color, with the
# text in that color (darker in light mode, lighter in dark mode, for
# contrast); the detail stays outside it, in grey. The transaction rows use
# it so the category stands out.
#
# `detail:` adds a secondary text after the label (the parent of a
# subcategory: "Combustible · Transporte"). `truncate: true` lets the label
# ellipsize inside a `min-w-0` parent. The square's fill is darkened a little
# so the white icon keeps its contrast on light category colors (white in
# both themes, as DS::FilledIcon's :solid variant).
class DS::ColorLabel < DesignSystemComponent
  MARKS = %i[square dot none].freeze
  SIZES = {
    sm: { square: "w-5 h-5 rounded-md", icon: "xs", text: "text-xs", dot: "size-1.5" },
    md: { square: "w-6 h-6 rounded-md", icon: "sm", text: "text-sm", dot: "size-2" },
    lg: { square: "w-8 h-8 rounded-lg", icon: "md", text: "text-sm", dot: "size-2" }
  }.freeze
  DEFAULT_COLOR = "#737373".freeze
  HEX_COLOR = /\A#[0-9a-fA-F]{6}\z/

  attr_reader :label, :color, :icon, :mark, :detail, :size, :dashed, :truncate, :title, :label_testid, :show_label, :tinted

  def initialize(label:, color: nil, icon: nil, mark: :square, detail: nil, size: :md, dashed: false, truncate: true,
                 title: nil, label_testid: nil, show_label: true, tinted: false)
    @label = label
    @color = color.to_s.match?(HEX_COLOR) ? color : DEFAULT_COLOR
    @icon = icon.presence
    @mark = MARKS.include?(mark.to_sym) ? mark.to_sym : :square
    @detail = detail.presence
    @size = SIZES.key?(size.to_sym) ? size.to_sym : :md
    @dashed = dashed
    @truncate = truncate
    @title = title
    @label_testid = label_testid
    @show_label = show_label
    @tinted = tinted
  end

  def container_classes
    class_names("inline-flex items-center gap-2 max-w-full text-primary font-normal", SIZES[size][:text], truncate ? "min-w-0" : "shrink-0")
  end

  def square_classes
    class_names("inline-flex shrink-0 items-center justify-center", SIZES[size][:square],
                dashed ? "border border-dashed border-secondary text-secondary" : nil)
  end

  def square_style
    return nil if dashed

    "background-color: color-mix(in oklab, #{color} 88%, black); color: var(--color-white);"
  end

  def tint_classes
    class_names("rounded-full px-2 py-0.5 font-medium", truncate ? "min-w-0 truncate" : "shrink-0")
  end

  def tint_style
    "background-color: color-mix(in oklab, #{color} 14%, transparent); " \
      "color: light-dark(color-mix(in oklab, #{color} 72%, black), color-mix(in oklab, #{color} 65%, white));"
  end

  def dot_classes
    class_names("inline-block shrink-0 rounded-full", SIZES[size][:dot])
  end

  def icon_size
    SIZES[size][:icon]
  end

  def full_title
    title || [ label, detail ].compact.join(" · ")
  end
end
