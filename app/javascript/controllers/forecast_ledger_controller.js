import { Controller } from "@hotwired/stimulus";

// Fulas Bank: the Forecast table, after a folded month is opened or folded.
// The table comes back from the server and its scroll area starts at the
// top again, so this brings the month just tapped back under the header.
export default class extends Controller {
  static values = { focus: String };

  connect() {
    if (!this.focusValue) return;

    const marker = this.element.querySelector(
      `[data-forecast-month="${this.focusValue}"]`,
    );
    const row = marker?.closest("tr");
    const scroller = this.element.querySelector(".table-scroll");
    if (!row || !scroller) return;

    const header = scroller.querySelector("thead");
    const offset =
      row.getBoundingClientRect().top - scroller.getBoundingClientRect().top;
    scroller.scrollTop += offset - (header?.offsetHeight || 0);
  }
}
