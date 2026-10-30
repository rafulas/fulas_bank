import { Controller } from "@hotwired/stimulus";

// Fulas Bank: the tags of the bulk edit drawer as one list of chips. Each
// tap moves a chip on: untouched → add (+) → remove (−) → untouched. The
// chip's hidden field goes in bulk_update[add_tag_ids][] or
// [remove_tag_ids][] accordingly, or carries no name and is not sent.
export default class extends Controller {
  static targets = ["chip", "search", "summary"];
  static values = { addLabel: String, removeLabel: String };

  static STATES = ["", "add", "remove"];

  connect() {
    for (const chip of this.chipTargets) this.#paint(chip);
    this.#summarize();
  }

  cycle(event) {
    const chip = event.currentTarget;
    const states = this.constructor.STATES;
    const next =
      states[(states.indexOf(chip.dataset.state || "") + 1) % states.length];
    chip.dataset.state = next;
    this.#paint(chip);
    this.#summarize();
  }

  filter() {
    const query = this.searchTarget.value.trim().toLowerCase();
    for (const chip of this.chipTargets) {
      const matches = chip.dataset.name.toLowerCase().includes(query);
      chip.hidden = !matches && !chip.dataset.state;
    }
  }

  #paint(chip) {
    const state = chip.dataset.state || "";
    const input = chip.querySelector("input");
    input.name = state ? `bulk_update[${state}_tag_ids][]` : "";
    input.disabled = !state;
    chip.setAttribute("aria-pressed", state ? "true" : "false");
    chip.querySelector("[data-mark]").textContent =
      state === "add" ? "+" : state === "remove" ? "−" : "";
    chip.classList.toggle("bg-success/10", state === "add");
    chip.classList.toggle("text-success", state === "add");
    chip.classList.toggle("border-success", state === "add");
    chip.classList.toggle("bg-destructive/10", state === "remove");
    chip.classList.toggle("text-destructive", state === "remove");
    chip.classList.toggle("border-destructive", state === "remove");
    chip.classList.toggle("line-through", state === "remove");
    chip.classList.toggle("border-secondary", !state);
    chip.classList.toggle("text-primary", !state);
  }

  #summarize() {
    if (!this.hasSummaryTarget) return;
    const count = (state) =>
      this.chipTargets.filter((chip) => chip.dataset.state === state).length;
    const parts = [];
    if (count("add")) parts.push(`${this.addLabelValue}: ${count("add")}`);
    if (count("remove"))
      parts.push(`${this.removeLabelValue}: ${count("remove")}`);
    this.summaryTarget.textContent = parts.join(" · ");
  }
}
