import { Controller } from "@hotwired/stimulus";

// Fulas Bank: "Añadir a recurrente". Choosing a series sends the form at once;
// "Crear nuevo recurrente" opens the second step (name and frequency).
// The form is sent through its hidden submit button, which in the
// transactions list also adds the selected movements (bulk-select).
export default class extends Controller {
  static targets = ["series", "list", "newStep", "submit"];

  pick(event) {
    const id = event.params.id;
    this.seriesTarget.value = id;

    if (id === "new") {
      this.listTarget.classList.add("hidden");
      this.newStepTarget.classList.remove("hidden");
      this.newStepTarget.querySelector("input[type='text']")?.focus();
    } else {
      this.submitTarget.click();
    }
  }

  back() {
    this.newStepTarget.classList.add("hidden");
    this.listTarget.classList.remove("hidden");
  }

  submitNew(event) {
    event.preventDefault();
    this.seriesTarget.value = "new";
    this.submitTarget.click();
  }
}
