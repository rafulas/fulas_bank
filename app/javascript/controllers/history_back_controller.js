import { Controller } from "@hotwired/stimulus";
import { Turbo } from "@hotwired/turbo-rails";

// Fulas Bank: the «Volver» button in the top bar. The Mac app has no
// browser back button, so this steps back through the pages visited in
// this window. Turbo numbers each visit in history.state; at the first one
// (a page opened fresh) there is nothing to go back to, so it goes up to
// the breadcrumb trail's previous page instead.
//
// Connects to data-controller="history-back"
export default class extends Controller {
  static values = { fallback: String };

  go(event) {
    event.preventDefault();

    const index = window.history.state?.turbo?.restorationIndex;
    if (typeof index === "number" && index > 0) {
      window.history.back();
    } else {
      Turbo.visit(this.fallbackValue || "/");
    }
  }
}
