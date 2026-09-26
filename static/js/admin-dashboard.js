(function () {
  "use strict";

  function formatNumber(value, decimals) {
    return Number(value).toFixed(decimals);
  }

  function renderStats(stats) {
    var grid = document.getElementById("admin-stat-grid");
    if (!grid) return;
    grid.querySelectorAll("[data-stat]").forEach(function (el) {
      var key = el.getAttribute("data-stat");
      if (key === "total_users" || key === "total_pages") {
        el.textContent = stats[key];
      } else {
        el.textContent = formatNumber(stats[key], 2);
      }
    });
  }

  // Interpolates a pixel x-position for a fractional value (e.g. an average
  // of 1.62) on a category scale, whose getPixelForValue only understands
  // integer category indices -- linearly blend between the two neighboring
  // category ticks instead of switching the whole chart to a linear scale
  // (which would lose Chart.js's category-scale bar sizing/spacing).
  function pixelForFractionalCategory(xScale, value, maxIndex) {
    var lower = Math.max(0, Math.min(maxIndex, Math.floor(value)));
    var upper = Math.max(0, Math.min(maxIndex, Math.ceil(value)));
    var lowerPx = xScale.getPixelForValue(lower);
    if (lower === upper) return lowerPx;
    var upperPx = xScale.getPixelForValue(upper);
    return lowerPx + (upperPx - lowerPx) * (value - lower);
  }

  // Draws the average/P99 reference lines + direct labels on top of the
  // bars -- Chart.js core has no "annotation" concept, but its plugin API
  // is just an object with draw hooks, so this is the whole "plugin".
  var referenceLinesPlugin = {
    id: "referenceLines",
    afterDatasetsDraw: function (chart, args, opts) {
      var lines = opts.lines || [];
      if (!lines.length) return;
      var ctx = chart.ctx;
      var xScale = chart.scales.x;
      var area = chart.chartArea;

      lines.forEach(function (line) {
        var x = pixelForFractionalCategory(xScale, line.value, opts.maxIndex);
        if (x < area.left || x > area.right) return;

        ctx.save();
        ctx.strokeStyle = line.color;
        ctx.lineWidth = 2;
        ctx.setLineDash([5, 4]);
        ctx.beginPath();
        ctx.moveTo(x, area.top);
        ctx.lineTo(x, area.bottom);
        ctx.stroke();

        ctx.setLineDash([]);
        ctx.fillStyle = line.color;
        ctx.font = "600 11px Inter, sans-serif";
        var label = line.label + " " + line.value.toFixed(2);
        var textWidth = ctx.measureText(label).width;
        var textX = x;
        if (x + textWidth / 2 > area.right) {
          ctx.textAlign = "right";
          textX = area.right;
        } else if (x - textWidth / 2 < area.left) {
          ctx.textAlign = "left";
          textX = area.left;
        } else {
          ctx.textAlign = "center";
        }
        ctx.fillText(label, textX, area.top - 8);
        ctx.restore();
      });
    },
  };

  function renderChart(canvas, wrap, stats) {
    var histogram = stats.histogram || [];
    var average = stats.average_pages_per_user || 0;
    var p99 = stats.p99_pages_per_user || 0;

    if (!histogram.length) {
      var empty = document.createElement("p");
      empty.className = "admin-chart-empty";
      empty.textContent = "No users yet — the chart will populate once accounts exist.";
      wrap.appendChild(empty);
      canvas.remove();
      return;
    }

    var byCount = {};
    var maxCount = 0;
    histogram.forEach(function (d) {
      byCount[d.count] = d.users;
      if (d.count > maxCount) maxCount = d.count;
    });
    var labels = [];
    var data = [];
    for (var i = 0; i <= maxCount; i++) {
      labels.push(i);
      data.push(byCount[i] || 0);
    }

    var brandPrimary = "#d29ad4";
    var brandPrimaryDark = "#efc7f0";
    var mutedInk = "#c3a8c9";
    var onSurface = "#1c0e1f";
    var outline = "#4a2f52";
    var p99Color = "#f5a63d";

    var lines = [{ value: average, color: mutedInk, label: "Average" }];
    if (Math.abs(p99 - average) > 0.01) {
      lines.push({ value: p99, color: p99Color, label: "P99" });
    }

    new Chart(canvas, {
      type: "bar",
      data: {
        labels: labels,
        datasets: [
          {
            label: "Users",
            data: data,
            backgroundColor: brandPrimary,
            hoverBackgroundColor: brandPrimaryDark,
            borderRadius: 4,
            maxBarThickness: 28,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        layout: { padding: { top: 24 } },
        scales: {
          x: {
            ticks: { color: mutedInk, font: { family: "Inter" } },
            grid: { display: false },
            border: { color: outline },
            title: {
              display: true,
              text: "Pages created",
              color: mutedInk,
              font: { size: 11, weight: "600", family: "Inter" },
            },
          },
          y: {
            beginAtZero: true,
            ticks: { precision: 0, color: mutedInk, font: { family: "Inter" } },
            grid: { color: outline },
            border: { display: false },
          },
        },
        datasets: {
          bar: { barPercentage: 0.7, categoryPercentage: 0.8 },
        },
        plugins: {
          legend: { display: false },
          tooltip: {
            backgroundColor: onSurface,
            padding: 10,
            cornerRadius: 10,
            titleFont: { family: "Inter" },
            bodyFont: { family: "Inter" },
            callbacks: {
              title: function () {
                return "";
              },
              label: function (ctx) {
                var users = ctx.parsed.y;
                var pages = ctx.dataIndex;
                return users + " user" + (users === 1 ? "" : "s") + " with " + pages + " page" + (pages === 1 ? "" : "s");
              },
            },
          },
          referenceLines: { lines: lines, maxIndex: maxCount },
        },
      },
      plugins: [referenceLinesPlugin],
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    var section = document.getElementById("admin-dashboard");
    var canvas = document.getElementById("admin-dashboard-chart");
    if (!section || !canvas) return;

    var url = section.getAttribute("data-stats-url");
    if (!url || typeof Chart === "undefined") return;

    var wrap = canvas.parentElement;

    fetch(url, { headers: { "X-Requested-With": "XMLHttpRequest" } })
      .then(function (response) { return response.json(); })
      .then(function (stats) {
        renderStats(stats);
        renderChart(canvas, wrap, stats);
      })
      .catch(function () {
        wrap.textContent = "Couldn't load analytics data.";
      });
  });
})();
