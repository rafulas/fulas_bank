import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";
import {
  CHART_TOOLTIP_CONTEXT_CLASSES,
  CHART_TOOLTIP_VALUE_CLASSES,
  createChartTooltip,
} from "utils/chart_tooltip";

// Real fuel consumption of a vehicle over time (one point per full tank).
//
// - Axes with the consumption scale and month/year dates, never repeating a
//   label.
// - A dashed line at the average.
// - Hover (or touch) anywhere on the chart: the nearest refuel is highlighted
//   and a card shows its date, consumption, distance, litres and odometer.
// - Range buttons (last year, last three years, everything).
//
// Every figure arrives already formatted from Ruby
// (VehiclesHelper#vehicle_consumption_chart_data), so the numbers follow the
// user's locale and this script only places them.
export default class extends Controller {
  static targets = ["canvas", "rangeButton"];
  static values = {
    data: Object,
    months: { type: String, default: "12" },
    distanceLabel: String,
    quantityLabel: String,
    odometerLabel: String,
    averageLabel: String,
  };

  connect() {
    this._points = (this.dataValue.points || []).map((point) => ({
      ...point,
      date: this._parseDate(point.date),
    }));

    // A short history looks empty in "last year": start on everything.
    if (this._filtered("12").length < 2) this.monthsValue = "all";

    if (typeof ResizeObserver !== "undefined") {
      this._observer = new ResizeObserver(() => this._draw());
      this._observer.observe(this.canvasTarget);
    }
    this.monthsValueChanged();
  }

  disconnect() {
    this._observer?.disconnect();
  }

  selectRange(event) {
    this.monthsValue = event.params.months.toString();
  }

  monthsValueChanged() {
    if (!this.hasCanvasTarget) return;

    this.rangeButtonTargets.forEach((button) => {
      const active =
        button.dataset.vehicleConsumptionChartMonthsParam === this.monthsValue;
      button.setAttribute("aria-pressed", active ? "true" : "false");
      button.classList.toggle("bg-surface-inset", active);
    });
    this._draw();
  }

  _parseDate(value) {
    const [year, month, day] = value.split("-").map(Number);
    return new Date(year, month - 1, day);
  }

  _filtered(months = this.monthsValue) {
    if (months === "all" || this._points.length === 0) return this._points;

    const last = this._points[this._points.length - 1].date;
    const since = d3.timeMonth.offset(last, -Number(months));
    return this._points.filter((point) => point.date >= since);
  }

  _draw() {
    if (!this._points) return;

    const root = this.canvasTarget;
    root.innerHTML = "";

    const width = root.clientWidth;
    const height = root.clientHeight;
    if (width <= 0 || height <= 0) return;

    const points = this._filtered();
    if (points.length === 0) return;

    const isDark =
      document.documentElement.getAttribute("data-theme") === "dark";
    const lineColor = isDark ? "#ffffff" : "#171717";
    const mutedColor = isDark ? "#a3a3a3" : "#737373";
    const gridColor = isDark ? "rgba(255,255,255,0.10)" : "rgba(0,0,0,0.08)";
    const averageColor = isDark ? "#60a5fa" : "#2563eb";

    const margin = { top: 12, right: 12, bottom: 28, left: 40 };
    const innerWidth = width - margin.left - margin.right;
    const innerHeight = height - margin.top - margin.bottom;

    const [minValue, maxValue] = d3.extent(points, (point) => point.value);
    const padding = Math.max((maxValue - minValue) * 0.15, 0.5);

    const x = d3
      .scaleTime()
      .domain(d3.extent(points, (point) => point.date))
      .range([margin.left, margin.left + innerWidth]);
    // One point alone has no time span: centre it.
    if (points.length === 1)
      x.domain([
        d3.timeDay.offset(points[0].date, -15),
        d3.timeDay.offset(points[0].date, 15),
      ]);

    const y = d3
      .scaleLinear()
      .domain([Math.max(0, minValue - padding), maxValue + padding])
      .nice()
      .range([margin.top + innerHeight, margin.top]);

    const svg = d3
      .select(root)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("aria-hidden", "true");

    // Horizontal grid and consumption scale.
    const yTicks = y.ticks(4);
    svg
      .append("g")
      .selectAll("line")
      .data(yTicks)
      .join("line")
      .attr("x1", margin.left)
      .attr("x2", margin.left + innerWidth)
      .attr("y1", (tick) => y(tick))
      .attr("y2", (tick) => y(tick))
      .attr("stroke", gridColor);

    const numberFormat = new Intl.NumberFormat(
      document.documentElement.lang || undefined,
      {
        maximumFractionDigits: 1,
      },
    );
    svg
      .append("g")
      .selectAll("text")
      .data(yTicks)
      .join("text")
      .attr("x", margin.left - 8)
      .attr("y", (tick) => y(tick))
      .attr("dy", "0.32em")
      .attr("text-anchor", "end")
      .attr("font-size", 11)
      .attr("fill", mutedColor)
      .text((tick) => numberFormat.format(tick));

    // Dates: d3 picks sensible ticks, and labels that would repeat (several
    // ticks in the same month) are dropped.
    const showYear = d3.timeYear.count(...x.domain()) >= 1;
    const dateFormat = new Intl.DateTimeFormat(
      document.documentElement.lang || undefined,
      {
        month: "short",
        ...(showYear ? { year: "2-digit" } : {}),
      },
    );
    const seen = new Set();
    const xTicks = x
      .ticks(Math.max(2, Math.floor(innerWidth / 90)))
      .filter((tick) => {
        const label = dateFormat.format(tick);
        if (seen.has(label)) return false;
        seen.add(label);
        return true;
      });
    svg
      .append("g")
      .selectAll("text")
      .data(xTicks)
      .join("text")
      .attr("x", (tick) => x(tick))
      .attr("y", height - 8)
      .attr("text-anchor", "middle")
      .attr("font-size", 11)
      .attr("fill", mutedColor)
      .text((tick) => dateFormat.format(tick));

    // Average over the whole history, so ranges compare against the same line.
    const average = this.dataValue.average;
    if (average && average >= y.domain()[0] && average <= y.domain()[1]) {
      svg
        .append("line")
        .attr("x1", margin.left)
        .attr("x2", margin.left + innerWidth)
        .attr("y1", y(average))
        .attr("y2", y(average))
        .attr("stroke", averageColor)
        .attr("stroke-width", 1)
        .attr("stroke-dasharray", "4 4");
      svg
        .append("text")
        .attr("x", margin.left + innerWidth)
        .attr("y", y(average) - 6)
        .attr("text-anchor", "end")
        .attr("font-size", 11)
        .attr("fill", averageColor)
        .text(`${this.averageLabelValue} ${this.dataValue.average_label}`);
    }

    const line = d3
      .line()
      .x((point) => x(point.date))
      .y((point) => y(point.value))
      .curve(d3.curveMonotoneX);

    svg
      .append("path")
      .datum(points)
      .attr("fill", "none")
      .attr("stroke", lineColor)
      .attr("stroke-width", 1.5)
      .attr("d", line);

    // Dots only while they stay apart; with years of refuels they would merge.
    const pointRadius = innerWidth / points.length > 8 ? 3 : 0;
    if (pointRadius > 0) {
      svg
        .append("g")
        .selectAll("circle")
        .data(points)
        .join("circle")
        .attr("cx", (point) => x(point.date))
        .attr("cy", (point) => y(point.value))
        .attr("r", pointRadius)
        .attr("fill", lineColor);
    }

    // Hover / touch.
    const focus = svg.append("g").style("display", "none");
    focus
      .append("line")
      .attr("y1", margin.top)
      .attr("y2", margin.top + innerHeight)
      .attr("stroke", mutedColor)
      .attr("stroke-dasharray", "2 3");
    focus
      .append("circle")
      .attr("r", 5)
      .attr("fill", lineColor)
      .attr("stroke", isDark ? "#0a0a0a" : "#ffffff")
      .attr("stroke-width", 2);

    const tooltip = createChartTooltip(root);
    const bisect = d3.bisector((point) => point.date).center;

    const show = (event) => {
      const [pointerX] = d3.pointer(event, svg.node());
      const point = points[bisect(points, x.invert(pointerX))];
      if (!point) return;

      const px = x(point.date);
      const py = y(point.value);
      focus.style("display", null);
      focus.select("line").attr("x1", px).attr("x2", px);
      focus.select("circle").attr("cx", px).attr("cy", py);

      tooltip.innerHTML = `
        <div class="${CHART_TOOLTIP_CONTEXT_CLASSES}">${point.date_label}</div>
        <div class="${CHART_TOOLTIP_VALUE_CLASSES}">${point.value_label}</div>
        <div class="text-xs text-secondary mt-1 space-y-0.5 tabular-nums">
          <div>${this.distanceLabelValue}: ${point.distance_label}</div>
          <div>${this.quantityLabelValue}: ${point.quantity_label}</div>
          <div>${this.odometerLabelValue}: ${point.odometer_label}</div>
        </div>`;
      tooltip.style.display = "block";

      // Keep the card inside the chart: left of the point when near the edge.
      const cardWidth = tooltip.offsetWidth;
      const left = px + 12 + cardWidth > width ? px - 12 - cardWidth : px + 12;
      tooltip.style.left = `${Math.max(0, left)}px`;
      tooltip.style.top = `${Math.max(0, Math.min(py - 20, height - tooltip.offsetHeight))}px`;
    };

    const hide = () => {
      focus.style("display", "none");
      tooltip.style.display = "none";
    };

    svg
      .append("rect")
      .attr("x", margin.left)
      .attr("y", margin.top)
      .attr("width", innerWidth)
      .attr("height", innerHeight)
      .attr("fill", "transparent")
      .style("touch-action", "pan-y")
      .on("pointermove pointerdown", show)
      .on("pointerleave", hide);
  }
}
