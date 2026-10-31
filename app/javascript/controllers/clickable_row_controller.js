import { Controller } from "@hotwired/stimulus";

// Delegates a click anywhere on a list row (avatar, whitespace, cells with
// no control of their own) to the row's primary link, so the whole row
// looks and behaves as clickable rather than only the exact link text.
// Clicks on real interactive descendants (checkbox, category menu, account
// link, kebab menu, etc.) are left alone so they keep handling themselves.
//
// Fulas Bank: opening the row takes its blue "not seen yet" dot off at once
// (`seen`, on the link's click). The server marks the movement seen when it
// opens, but the list behind the drawer, and the page Turbo keeps for going
// back, would otherwise still show the dot.
export default class extends Controller {
  static targets = ["link", "unseen"];

  seen() {
    for (const dot of this.unseenTargets) dot.remove();
  }

  open(event) {
    if (event.target.closest("a, button, input, select, textarea, label")) return;
    // Popover/menu/dropdown panels (category dropdown, account/kebab menu,
    // investment activity quick-edit) render as `position: fixed`/`absolute`
    // but stay DOM descendants of the row, so a click anywhere on their
    // background (padding, headings, plain text) would otherwise fall
    // through to the row's own link.
    if (
      event.target.closest(
        '[data-ds--popover-target="content"], [data-ds--menu-target="content"], [data-activity-label-quick-edit-target="dropdown"]',
      )
    ) {
      return;
    }
    if (window.getSelection().toString().length > 0) return;

    // Browsers only honor Ctrl/Cmd/Shift (open in new tab/window) on
    // trusted, native link activation — a synthetic/dispatched click event
    // is always untrusted, so its modifier-key flags are ignored. Open the
    // link explicitly instead of delegating to `linkTarget.click()`.
    if (event.ctrlKey || event.metaKey || event.shiftKey) {
      window.open(this.linkTarget.href, "_blank", "noopener");
      return;
    }

    this.linkTarget.click();
  }
}
