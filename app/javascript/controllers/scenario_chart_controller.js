import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";
import {
  CHART_TOOLTIP_CONTEXT_CLASSES,
  CHART_TOOLTIP_VALUE_CLASSES,
  createChartTooltip,
} from "utils/chart_tooltip";

// Fulas Bank: the total balance with and without a scenario (Escenarios),
// at the end of each month. The forecast as it is is dashed and grey; the
// scenario solid, so the two read apart without relying on colour.

// Date-only strings parse as UTC midnight in `new Date`; read the parts.
const parseDate = (value) => {
  const [year, month, day] = value.split("-").map(Number);
  return new Date(year, month - 1, day);
};

export default class extends Controller {
  static values = { data: Object };

  connect() {
    this._scheduleDraw = () => {
      if (this._frame) return;
      this._frame = requestAnimationFrame(() => {
        this._frame = null;
        this._draw();
      });
    };
    if (typeof ResizeObserver !== "undefined") {
      this._observer = new ResizeObserver(this._scheduleDraw);
      this._observer.observe(this.element);
    } else {
      this._draw();
    }
  }

  disconnect() {
    if (this._frame) cancelAnimationFrame(this._frame);
    this._frame = null;
    this._observer?.disconnect();
    this._tooltip?.remove();
  }

  _draw() {
    const root = this.element;
    const width = root.clientWidth;
    const height = root.clientHeight;
    if (width <= 0 || height <= 0) return;

    this._tooltip?.remove();
    root.innerHTML = "";
    root.style.position = "relative";

    const data = this.dataValue || {};
    const points = (data.points || []).map((point) => ({
      date: parseDate(point.date),
      base: point.base,
      scenario: point.scenario,
    }));
    if (points.length < 2) return;

    const labels = data.labels || {};
    const money = new Intl.NumberFormat(data.locale || "es", {
      style: "currency",
      currency: data.currency || "EUR",
      maximumFractionDigits: 0,
    });
    const monthFormat = new Intl.DateTimeFormat(data.locale || "es", {
      month: "short",
      year: "numeric",
    });

    const margin = { top: 12, right: 12, bottom: 24, left: 64 };
    const x = d3
      .scaleTime()
      .domain(d3.extent(points, (point) => point.date))
      .range([margin.left, width - margin.right]);
    const low = d3.min(points, (point) => Math.min(point.base, point.scenario));
    const high = d3.max(points, (point) =>
      Math.max(point.base, point.scenario),
    );
    const padding = (high - low) * 0.05 || Math.abs(high) * 0.05 || 1;
    const y = d3
      .scaleLinear()
      .domain([low - padding, high + padding])
      .nice()
      .range([height - margin.bottom, margin.top]);

    const svg = d3
      .select(root)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("role", "img")
      .attr("aria-label", `${labels.base} / ${labels.scenario}`);

    // Tokens as CSS variables go through .style(): an SVG presentation
    // attribute does not resolve them.
    const muted = "var(--color-gray-400)";
    const scenarioColor = "var(--color-success)";
    const gridColor = "var(--color-gray-200)";

    svg
      .append("g")
      .attr("transform", `translate(0,${height - margin.bottom})`)
      .call(
        d3
          .axisBottom(x)
          .ticks(Math.max(2, Math.floor(width / 110)))
          .tickFormat((date) => monthFormat.format(date))
          .tickSizeOuter(0),
      )
      .call((axis) => axis.select(".domain").remove())
      .call((axis) =>
        axis
          .selectAll("text")
          .attr("class", "text-xs fill-current text-secondary"),
      )
      .call((axis) => axis.selectAll("line").remove());

    svg
      .append("g")
      .attr("transform", `translate(${margin.left},0)`)
      .call(
        d3
          .axisLeft(y)
          .ticks(4)
          .tickFormat((value) => money.format(value))
          .tickSize(-(width - margin.left - margin.right)),
      )
      .call((axis) => axis.select(".domain").remove())
      .call((axis) =>
        axis
          .selectAll("text")
          .attr("class", "text-xs fill-current text-secondary"),
      )
      .call((axis) => axis.selectAll("line").style("stroke", gridColor));

    const line = (key) =>
      d3
        .line()
        .x((point) => x(point.date))
        .y((point) => y(point[key]))
        .curve(d3.curveMonotoneX);

    svg
      .append("path")
      .datum(points)
      .attr("fill", "none")
      .attr("stroke-width", 2)
      .attr("stroke-dasharray", "5 4")
      .style("stroke", muted)
      .attr("d", line("base"));

    svg
      .append("path")
      .datum(points)
      .attr("fill", "none")
      .attr("stroke-width", 2)
      .style("stroke", scenarioColor)
      .attr("d", line("scenario"));

    const guide = svg
      .append("line")
      .attr("y1", margin.top)
      .attr("y2", height - margin.bottom)
      .attr("stroke-width", 1)
      .style("stroke", gridColor)
      .style("display", "none");

    const tooltip = createChartTooltip(root);
    this._tooltip = tooltip;
    const bisect = d3.bisector((point) => point.date).center;

    const show = (event) => {
      const [pointerX] = d3.pointer(event);
      const point = points[bisect(points, x.invert(pointerX))];
      if (!point) return;

      const left = x(point.date);
      guide.attr("x1", left).attr("x2", left).style("display", null);

      const difference = point.scenario - point.base;
      const sign = difference > 0 ? "+" : "";
      tooltip.innerHTML = `
        <div class="${CHART_TOOLTIP_CONTEXT_CLASSES}">${monthFormat.format(point.date)}</div>
        <div class="flex justify-between gap-4"><span class="text-secondary">${labels.scenario}</span><span class="${CHART_TOOLTIP_VALUE_CLASSES}">${money.format(point.scenario)}</span></div>
        <div class="flex justify-between gap-4"><span class="text-secondary">${labels.base}</span><span class="${CHART_TOOLTIP_VALUE_CLASSES}">${money.format(point.base)}</span></div>
        <div class="flex justify-between gap-4"><span class="text-secondary">${labels.difference}</span><span class="${CHART_TOOLTIP_VALUE_CLASSES}">${sign}${money.format(difference)}</span></div>`;
      tooltip.style.display = "block";
      const tooltipWidth = tooltip.offsetWidth;
      const placeLeft = left + 12 + tooltipWidth > width;
      tooltip.style.left = `${placeLeft ? left - tooltipWidth - 12 : left + 12}px`;
      tooltip.style.top = `${margin.top}px`;
    };

    const hide = () => {
      guide.style("display", "none");
      tooltip.style.display = "none";
    };

    svg
      .append("rect")
      .attr("x", margin.left)
      .attr("y", margin.top)
      .attr("width", Math.max(0, width - margin.left - margin.right))
      .attr("height", Math.max(0, height - margin.top - margin.bottom))
      .attr("fill", "transparent")
      .on("pointermove", show)
      .on("pointerleave", hide);
  }
}
