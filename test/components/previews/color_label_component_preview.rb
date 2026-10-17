class ColorLabelComponentPreview < ViewComponent::Preview
  # @param size select ["sm", "md", "lg"]
  def category(size: "md")
    render DS::ColorLabel.new(label: "Combustible", detail: "Transporte", color: "#506cd8", icon: "fuel", size: size)
  end

  def uncategorized
    render DS::ColorLabel.new(label: "Uncategorized", color: "#737373", icon: "circle-dashed", dashed: true)
  end

  def tag
    render DS::ColorLabel.new(label: "Viaje Roma", color: "#6471eb", mark: :dot)
  end
end
