import { Controller } from "@hotwired/stimulus";

// The "fixed / recurring / variable" form in a movement's detail: the end of a
// recurring movement only matters for "recurring", and it is given either as
// a date or as the number of payments still to come.
export default class extends Controller {
  static targets = ["type", "end", "endsBy", "date", "periods"];

  connect() {
    this.refresh();
  }

  refresh() {
    const recurring = this.typeTarget.value === "recurring";
    const byDate = this.endsByTarget.value === "date";

    this.endTarget.hidden = !recurring;
    this.dateTarget.hidden = !byDate;
    this.periodsTarget.hidden = byDate;
  }
}
