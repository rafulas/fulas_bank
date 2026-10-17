import { Controller } from "@hotwired/stimulus";

// Fulas Bank: category pickers show only the main categories; a category
// with subcategories opens them when it is tapped ("Transporte" →
// "Combustible"). While the user types a search, every group opens so the
// matching subcategories can be found, and the group headers step aside
// unless they are themselves a choice (the filter's checkboxes).
//
// Markup (see categories/_tree_group):
//   [data-category-tree-target=group][data-expanded]
//     [data-category-tree-target=header]  (button, data-action=category-tree#toggle)
//     [data-category-tree-target=children][hidden]
export default class extends Controller {
  static targets = ["group", "header", "children"];

  toggle(event) {
    event.preventDefault();
    event.stopPropagation();

    const group = event.currentTarget.closest(
      "[data-category-tree-target~='group']",
    );
    if (!group) return;

    this.#setExpanded(group, group.dataset.expanded !== "true");
  }

  // input->category-tree#search on the picker's search box.
  search(event) {
    const searching = event.target.value.trim().length > 0;

    this.groupTargets.forEach((group) => {
      const header = this.#headerOf(group);
      const children = this.#childrenOf(group);

      if (children)
        children.hidden = searching ? false : group.dataset.expanded !== "true";
      // A header that is only a toggle hides while searching; one that is
      // also a filterable choice is shown or hidden by the list filter.
      if (header && !header.classList.contains("filterable-item")) {
        header.hidden = searching;
      }
    });
  }

  #setExpanded(group, expanded) {
    group.dataset.expanded = expanded ? "true" : "false";

    const header = this.#headerOf(group);
    const toggle = header?.matches("[aria-expanded]")
      ? header
      : header?.querySelector("[aria-expanded]");
    if (toggle)
      toggle.setAttribute("aria-expanded", expanded ? "true" : "false");

    const children = this.#childrenOf(group);
    if (children) children.hidden = !expanded;
  }

  #headerOf(group) {
    return this.headerTargets.find(
      (header) =>
        header.closest("[data-category-tree-target~='group']") === group,
    );
  }

  #childrenOf(group) {
    return this.childrenTargets.find(
      (children) =>
        children.closest("[data-category-tree-target~='group']") === group,
    );
  }
}
