// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails";
import "controllers";
import HwComboboxController from "controllers/hw_combobox_controller";

// Fix hotwire_combobox race condition: when typing quickly, a slow response for
// an early query (e.g. "A") can overwrite the correct results for the final query
// (e.g. "AAPL"). We abort the previous in-flight request whenever a new one fires,
// so stale Turbo Stream responses never reach the DOM.
const originalFilterAsync = HwComboboxController.prototype._filterAsync;
HwComboboxController.prototype._filterAsync = async function(inputType) {
  if (this._searchAbortController) {
    this._searchAbortController.abort();
  }
  this._searchAbortController = new AbortController();

  const query = {
    q: this._fullQuery,
    input_type: inputType,
    for_id: this.element.dataset.asyncId,
    callback_id: this._enqueueCallback()
  };

  const url = new URL(this.asyncSrcValue, window.location.origin);
  Object.entries(query).forEach(([k, v]) => {
    if (v != null) url.searchParams.set(k, v);
  });

  try {
    const response = await fetch(url.toString(), {
      headers: {
        "Accept": "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
        "X-Requested-With": "XMLHttpRequest",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
      signal: this._searchAbortController.signal,
      credentials: "same-origin"
    });

    if (response.ok) {
      await Turbo.renderStreamMessage(await response.text());
    }
  } catch (e) {
    if (e.name !== "AbortError") throw e;
  }
};

// Fulas Bank: the blue bar at the top while a movement's detail (the drawer),
// a dialog or the Forecast table is loading, as when changing page. Turbo
// only shows it for pages and forms, so a tap on a movement showed nothing
// until its detail arrived. Same delay as for pages: quick loads show none.
const PROGRESS_FRAMES = new Set(["drawer", "modal", "forecast_ledger"]);
let framesLoading = 0;

const progressFrame = (event) =>
  event.target?.tagName === "TURBO-FRAME" &&
  PROGRESS_FRAMES.has(event.target.id);

const frameLoadFinished = (event) => {
  if (!progressFrame(event) || framesLoading === 0) return;

  framesLoading -= 1;
  if (framesLoading === 0) Turbo.session.adapter?.formSubmissionFinished?.();
};

document.addEventListener("turbo:before-fetch-request", (event) => {
  if (!progressFrame(event)) return;

  framesLoading += 1;
  if (framesLoading === 1) Turbo.session.adapter?.formSubmissionStarted?.();
});
document.addEventListener("turbo:before-fetch-response", frameLoadFinished);
document.addEventListener("turbo:fetch-request-error", frameLoadFinished);

Turbo.StreamActions.redirect = function () {
  // Use "replace" to avoid adding form submission to browser history
  Turbo.visit(this.target, { action: "replace" });
};

// Register service worker for PWA offline support
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/service-worker')
      .then(registration => {
        console.log('Service Worker registered with scope:', registration.scope);
      })
      .catch(error => {
        console.log('Service Worker registration failed:', error);
      });
  });
}
