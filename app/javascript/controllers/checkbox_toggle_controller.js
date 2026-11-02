import { Controller } from "@hotwired/stimulus"

// Shows or hides the selection checkboxes of a list on small screens, where
// they are hidden by default (they are always shown from the lg breakpoint).
// Fulas Bank: the button reads «Seleccionar» and, while selecting, «Listo»,
// as in Apple's apps; rows that arrive later (the next page, loaded while
// scrolling) follow the current mode.
export default class extends Controller {
  static targets = ["selectionEntry", "toggleButton", "labelOff", "labelOn"]

  toggle() {
    this.selecting = !this.selecting

    this.selectionEntryTargets.forEach((el) => this.#apply(el))

    if (!this.selecting) {
      const bulkSelectElement =
        this.element.querySelector("[data-controller~='bulk-select']") ||
        this.element.closest("[data-controller~='bulk-select']") ||
        document.querySelector("[data-controller~='bulk-select']")
      if (bulkSelectElement) {
        const bulkSelectController = this.application.getControllerForElementAndIdentifier(
          bulkSelectElement,
          "bulk-select"
        )
        if (bulkSelectController) {
          bulkSelectController.deselectAll()
        }
      }
    }

    if (this.hasToggleButtonTarget) {
      this.toggleButtonTarget.classList.toggle("bg-surface", this.selecting)
      this.toggleButtonTarget.setAttribute("aria-pressed", this.selecting ? "true" : "false")
    }
    this.labelOffTargets.forEach((el) => el.classList.toggle("hidden", this.selecting))
    this.labelOnTargets.forEach((el) => el.classList.toggle("hidden", !this.selecting))
  }

  selectionEntryTargetConnected(el) {
    this.#apply(el)
  }

  #apply(el) {
    el.classList.toggle("hidden", !this.selecting)
  }
}
