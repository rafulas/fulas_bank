import { Controller } from "@hotwired/stimulus";

// The "variable / fixed / bill / subscription" form in a movement's detail:
// only a fixed one ends (a loan), never, on a date or after the number of
// payments still to come.
export default class extends Controller {
  static targets = ["type", "end", "endsBy", "date", "periods"];

  connect() {
    this.refresh();
  }

  refresh() {
    const fixed = this.typeTarget.value === "fixed";
    const endsBy = this.endsByTarget.value;

    this.endTarget.hidden = !fixed;
    this.dateTarget.hidden = endsBy !== "date";
    this.periodsTarget.hidden = endsBy !== "periods";
  }
}
