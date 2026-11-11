import { Controller } from "@hotwired/stimulus";

// Fulas Bank: add and remove a loan's partial early repayments. The rows are
// plain inputs named as an array, so the form works without JavaScript too;
// a hidden sentinel keeps the key when the last row is removed.
export default class extends Controller {
  static targets = ["rows", "template", "empty"];

  connect() {
    this.#sync();
  }

  add(event) {
    event.preventDefault();
    const row = this.templateTarget.content.firstElementChild.cloneNode(true);
    this.rowsTarget.appendChild(row);
    row.querySelector("input[type='date']")?.focus();
    this.#sync();
  }

  remove(event) {
    event.preventDefault();
    event.target.closest("[data-prepayment-row]")?.remove();
    this.#sync();
  }

  #sync() {
    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = this.rowsTarget.children.length > 0;
    }
  }
}
