import { Controller } from "@hotwired/stimulus";

// Fulas Bank: in the new movement form, as the name is typed, asks the app
// for the category the movements like it have and chooses it. A category
// picked by hand always wins: once the user clicks one, suggestions stop.
export default class extends Controller {
  static targets = ["name", "select", "hint"];
  static values = { url: String };

  connect() {
    this.manual = false;
    this.suggestedId = null;
    this.timer = null;
    this.controllerAbort = null;
  }

  disconnect() {
    clearTimeout(this.timer);
    this.controllerAbort?.abort();
  }

  nameChanged() {
    if (this.manual) return;

    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.fetchSuggestion(), 350);
  }

  manualPick(event) {
    if (event.target.closest("[data-category-select-target='option']")) {
      this.manual = true;
      this.hintTarget.classList.add("hidden");
    }
  }

  async fetchSuggestion() {
    const name = this.nameTarget.value.trim();
    if (name.length < 3) return;

    this.controllerAbort?.abort();
    this.controllerAbort = new AbortController();

    const url = new URL(this.urlValue, window.location.origin);
    url.searchParams.set("name", name);
    url.searchParams.set("nature", this.nature());

    try {
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: this.controllerAbort.signal,
      });
      if (!response.ok) return;

      const suggestion = await response.json();
      this.apply(suggestion.category_id);
    } catch (error) {
      if (error.name !== "AbortError") console.warn(error);
    }
  }

  apply(categoryId) {
    if (this.manual || !categoryId) return;

    const select = this.categorySelect();
    if (!select) return;

    // Only over an empty choice or one this controller made.
    const current = select.hiddenInputTarget.value;
    if (current && current !== this.suggestedId) return;

    const option = select.optionTargets.find(
      (candidate) => candidate.dataset.categoryId === String(categoryId),
    );
    if (!option) return;

    select.selectOption(option);
    this.suggestedId = String(categoryId);
    this.hintTarget.classList.remove("hidden");
  }

  categorySelect() {
    const element = this.selectTarget.querySelector(
      "[data-controller~='category-select']",
    );
    return (
      element &&
      this.application.getControllerForElementAndIdentifier(
        element,
        "category-select",
      )
    );
  }

  nature() {
    const field = this.element
      .closest("form")
      ?.querySelector("input[name='entry[nature]']");
    return field?.value || "outflow";
  }
}
