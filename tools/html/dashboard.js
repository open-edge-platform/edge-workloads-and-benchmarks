// SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
// SPDX-License-Identifier: Apache-2.0

/**
 * Edge Workloads and Benchmarks Dashboard JavaScript
 * Handles data loading, chart rendering, table population, and workload switching.
 */

// =========================================================================
// Shared Chart Utilities
// =========================================================================

const COLORS = {
  GREEN: '#22c55e',   // GPU
  BLUE: '#3b82f6',    // GPU/NPU Split
  GOLD: '#a7a406ff',  // GPU/NPU Concurrent
  PURPLE: '#a855f7',  // NPU
  ORANGE: '#f97316',  // CPU
  GRAY: '#666'
};

/** Read a CSS custom property from :root */
function cssVar(name) {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}

/** HTML-escape a string to prevent XSS when interpolating into innerHTML */
function esc(s) {
  if (s == null) return '';
  const d = document.createElement('div');
  d.appendChild(document.createTextNode(String(s)));
  return d.innerHTML;
}

/** Sync COLORS object with current CSS custom properties */
function syncColors() {
  COLORS.GREEN  = cssVar('--chart-green')  || '#22c55e';
  COLORS.BLUE   = cssVar('--chart-blue')   || '#3b82f6';
  COLORS.PURPLE = cssVar('--chart-purple') || '#a855f7';
  COLORS.GOLD   = cssVar('--chart-gold')   || '#a7a406';
  COLORS.ORANGE = cssVar('--chart-orange') || '#f97316';
}

// Format a number to 2 decimal places
function fmtNum(v) {
  const n = parseFloat(v);
  return isNaN(n) ? v : n.toFixed(2);
}

// Build a stat key-value pair for best-config cards
function stat(label, value) {
  return `<div class="best-card-stat"><span class="best-card-stat-label">${esc(label)}</span><span class="best-card-stat-value">${esc(value)}</span></div>`;
}

// Build a best-config winner card
function bestCard(modeClass, badge, title, heroValue, heroUnit, stats) {
  return `<div class="best-card ${esc(modeClass)}">
    <div class="best-card-label">${esc(badge)}</div>
    <div class="best-card-title">${esc(title)}</div>
    <div class="best-card-hero">${esc(heroValue)}<span class="hero-unit">${esc(heroUnit)}</span></div>
    <div class="best-card-stats">${stats.join('')}</div>
  </div>`;
}

function shadeColor(hex, delta) {
  let r = parseInt(hex.slice(1, 3), 16);
  let g = parseInt(hex.slice(3, 5), 16);
  let b = parseInt(hex.slice(5, 7), 16);
  const adjust = (c) => Math.min(255, Math.max(0, Math.round(
    delta > 0 ? c + (255 - c) * delta : c * (1 + delta)
  )));
  r = adjust(r); g = adjust(g); b = adjust(b);
  return '#' + [r, g, b].map(x => x.toString(16).padStart(2, '0')).join('');
}

function batchShade(batch) {
  return batch === '1' ? 0.45 : batch === '8' ? -0.25 : batch === '16' ? -0.5 : 0;
}

function createGroupLabelPlugin() {
  return {
    id: 'groupLabelPlugin',
    beforeDatasetsDraw: (chart, args, opts) => {
      const groups = opts.groups || [];
      if (!groups.length) return;
      const meta = chart.getDatasetMeta(0);
      if (!meta || !meta.data || !meta.data.length) return;
      const ctx = chart.ctx;
      const area = chart.chartArea;
      const bandEven = cssVar('--chart-band-even') || 'rgba(255,255,255,0.04)';
      const bandOdd  = cssVar('--chart-band-odd')  || 'rgba(255,255,255,0.02)';
      ctx.save();
      groups.forEach((group, i) => {
        const slice = meta.data.slice(group.startIndex, group.endIndex + 1);
        if (!slice.length) return;
        const first = slice[0]; const last = slice[slice.length - 1];
        const x1 = first.x - first.width / 2 - 4;
        const x2 = last.x + last.width / 2 + 4;
        ctx.fillStyle = i % 2 === 0 ? bandEven : bandOdd;
        ctx.fillRect(x1, area.top, x2 - x1, area.bottom - area.top);
      });
      ctx.restore();
    },
    afterDatasetsDraw: (chart, args, opts) => {
      const groups = opts.groups || [];
      if (!groups.length) return;
      const meta = chart.getDatasetMeta(0);
      if (!meta || !meta.data || !meta.data.length) return;
      const ctx = chart.ctx;
      const groupText   = cssVar('--chart-group-text')   || '#ddd';
      const groupStroke = cssVar('--chart-group-stroke') || '#555';
      const separator   = cssVar('--chart-separator')    || '#333';
      ctx.save();
      ctx.textAlign = 'center';
      ctx.fillStyle = groupText;
      ctx.font = '600 12px Inter, sans-serif';
      groups.forEach((group, i) => {
        const slice = meta.data.slice(group.startIndex, group.endIndex + 1);
        if (!slice.length) return;
        const first = slice[0]; const last = slice[slice.length - 1];
        const xMid = (first.x + last.x) / 2;
        ctx.fillText(group.name.charAt(0).toUpperCase() + group.name.slice(1).toLowerCase(), xMid, chart.chartArea.top - 14);
        ctx.strokeStyle = groupStroke; ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(first.x - first.width / 2, chart.chartArea.top - 4);
        ctx.lineTo(last.x + last.width / 2, chart.chartArea.top - 4);
        ctx.stroke();
        if (i < groups.length - 1) {
          ctx.strokeStyle = separator;
          ctx.beginPath();
          ctx.moveTo(last.x + last.width / 2 + 6, chart.chartArea.top);
          ctx.lineTo(last.x + last.width / 2 + 6, chart.chartArea.bottom);
          ctx.stroke();
        }
      });
      ctx.restore();
    }
  };
}

function createSubGroupLabelPlugin() {
  return {
    id: 'subGroupLabelPlugin',
    afterDatasetsDraw: (chart, args, opts) => {
      const subGroups = opts.subGroups || [];
      if (!subGroups.length) return;
      const meta = chart.getDatasetMeta(0);
      if (!meta || !meta.data || !meta.data.length) return;
      const ctx = chart.ctx;
      const area = chart.chartArea;
      const textColor = cssVar('--chart-group-text') || '#ddd';
      const separator = cssVar('--chart-separator') || '#333';
      ctx.save();
      ctx.textAlign = 'center';
      ctx.fillStyle = textColor;
      ctx.font = '500 9px Inter, sans-serif';
      const ABBREV = { 'GPU-Only': 'GPU', 'NPU-Only': 'NPU', 'GPU-NPU-Split': 'Split', 'GPU-NPU-Concurrent': 'Conc' };
      subGroups.forEach((sg, i) => {
        const slice = meta.data.slice(sg.startIndex, sg.endIndex + 1);
        if (!slice.length) return;
        const first = slice[0]; const last = slice[slice.length - 1];
        const xMid = (first.x + last.x) / 2;
        const label = ABBREV[sg.name] || sg.name;
        ctx.fillText(label, xMid, area.bottom + 36);
        if (i < subGroups.length - 1) {
          const next = meta.data[sg.endIndex + 1];
          if (next) {
            const nextSg = subGroups[i + 1];
            if (nextSg) {
              const nextFirst = meta.data[nextSg.startIndex];
              if (nextFirst) {
                const xSep = (last.x + last.width / 2 + nextFirst.x - nextFirst.width / 2) / 2;
                ctx.strokeStyle = separator; ctx.lineWidth = 0.5;
                ctx.beginPath();
                ctx.moveTo(xSep, area.bottom + 24);
                ctx.lineTo(xSep, area.bottom + 42);
                ctx.stroke();
              }
            }
          }
        }
      });
      ctx.restore();
    }
  };
}

function createValueLabelPlugin(decimals) {
  decimals = decimals || 0;
  return {
    id: 'valueLabelPlugin',
    afterDatasetsDraw: (chart) => {
      const meta = chart.getDatasetMeta(0);
      if (!meta || !meta.data) return;
      const dataset = chart.data.datasets[0];
      const ctx = chart.ctx;
      const labelColor = cssVar('--chart-label') || '#eee';
      ctx.save();
      ctx.font = '600 11px Inter, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillStyle = labelColor;
      meta.data.forEach((bar, i) => {
        const value = dataset.data[i];
        if (value == null || isNaN(value)) return;
        let y = bar.y - 4;
        if (y < chart.chartArea.top + 10) y = chart.chartArea.top + 10;
        ctx.fillText(value.toFixed(decimals), bar.x, y);
      });
      ctx.restore();
    }
  };
}

/** For stacked bars: show total value above the top segment */
function createStackedValueLabelPlugin() {
  return {
    id: 'stackedValueLabelPlugin',
    afterDatasetsDraw: (chart) => {
      const ctx = chart.ctx;
      const labelColor = cssVar('--chart-label') || '#eee';
      ctx.save();
      ctx.font = '600 11px Inter, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillStyle = labelColor;
      const numBars = chart.data.datasets[0].data.length;
      for (let i = 0; i < numBars; i++) {
        let total = 0;
        let topY = Infinity;
        chart.data.datasets.forEach((ds, dsIdx) => {
          const val = ds.data[i];
          if (val != null && !isNaN(val) && val > 0) {
            total += val;
            const m = chart.getDatasetMeta(dsIdx);
            if (m.data[i]) topY = Math.min(topY, m.data[i].y);
          }
        });
        if (total > 0 && topY !== Infinity) {
          let y = topY - 4;
          if (y < chart.chartArea.top + 10) y = chart.chartArea.top + 10;
          ctx.fillText(Math.round(total).toString(), chart.getDatasetMeta(0).data[i].x, y);
        }
      }
      ctx.restore();
    }
  };
}

function computeGroups(data, keyFn) {
  const groups = [];
  let current = null, start = 0;
  data.forEach((record, i) => {
    const key = keyFn(record);
    if (key !== current) {
      if (current !== null) groups.push({ name: current, startIndex: start, endIndex: i - 1 });
      current = key; start = i;
    }
  });
  if (current !== null) groups.push({ name: current, startIndex: start, endIndex: data.length - 1 });
  return groups;
}

function baseChartOptions(groups) {
  const tick  = cssVar('--chart-tick')  || '#eee';
  const grid  = cssVar('--chart-grid')  || '#222';
  const label = cssVar('--chart-label') || '#eee';
  return {
    plugins: {
      legend: { display: false },
      groupLabelPlugin: { groups }
    },
    layout: { padding: { top: 42 } },
    scales: {
      x: {
        ticks: { color: tick, autoSkip: false, font: { size: 10 }, maxRotation: 0, minRotation: 0 },
        grid: { color: grid }
      },
      y: {
        ticks: { color: tick },
        grid: { color: grid },
        beginAtZero: true,
        grace: '10%',
        title: { display: true, color: label, font: { size: 12, weight: 'bold' } }
      }
    },
    responsive: true,
    maintainAspectRatio: false
  };
}

// =========================================================================
// Shared Color, Model & Legend Utilities
// =========================================================================

/** Map an edge-ai-pipeline record to a bar color */
function edgeDeviceColor(record) {
  const dc = record.device_config || `${record.detect}-${record.classify}`;
  const delta = batchShade(record.batch);
  let base;
  if (dc.includes('CPU')) base = COLORS.ORANGE;
  else if (dc.includes('GPU-Only') || dc === 'GPU-GPU') base = COLORS.GREEN;
  else if (dc.includes('NPU-Only') || dc === 'NPU-NPU') base = COLORS.PURPLE;
  else if ((dc.includes('GPU-NPU') || dc.includes('NPU-GPU')) && dc.includes('Concurrent')) base = COLORS.GOLD;
  else if (dc.includes('GPU-NPU') || dc.includes('NPU-GPU')) base = COLORS.BLUE;
  else base = COLORS.GRAY;
  return shadeColor(base, delta);
}

/** Map a vision benchmark device+batch to a bar color */
function visionDeviceColor(device, batch) {
  const delta = batchShade(batch);
  if (device.includes('Concurrent')) return shadeColor(COLORS.GOLD, delta);
  if (device.startsWith('GPU')) return shadeColor(COLORS.GREEN, delta);
  if (device === 'NPU') return shadeColor(COLORS.PURPLE, delta);
  if (device === 'CPU') return shadeColor(COLORS.ORANGE, delta);
  return shadeColor(COLORS.GRAY, delta);
}

/** Map a media benchmark record to a bar color */
function mediaRecordColor(record) {
  const isH265 = record.codec === 'h265';
  const is4k = record.resolution === '4k';
  const base = isH265 ? COLORS.GREEN : COLORS.BLUE;
  const delta = is4k ? -0.25 : 0.2;
  return shadeColor(base, delta);
}

/** Prettify vision model shortname for display */
function prettyModel(model) {
  return model
    .replace(/_640x640/g, '')
    .replace(/-1\.0-224-tf/g, '')
    .replace(/-tf/g, '');
}

/** Check if a vision record is a detection (YOLO) model */
function isDetectionModel(r) {
  return r.model.toLowerCase().startsWith('yolo');
}

/** Set innerHTML of a legend element by ID */
function setLegend(id, html) {
  const el = document.getElementById(id);
  if (el) el.innerHTML = html;
}

/** Build legend HTML for edge-ai-pipelines */
function buildEdgeLegendHtml(summary, opts) {
  const stackedConcurrent = (opts && opts.stackedConcurrent) || false;
  const deviceConfigs = new Set();
  const batchSizes = new Set();
  summary.forEach(r => {
    deviceConfigs.add(r.device_config || `${r.detect}-${r.classify}`);
    batchSizes.add(r.batch);
  });
  const hasConcurrent = [...deviceConfigs].some(x => (x.includes('GPU-NPU') || x.includes('NPU-GPU')) && x.includes('Concurrent'));
  const allItems = [
    { label: 'GPU-Only', style: `background:${COLORS.GREEN}`,
      cond: () => [...deviceConfigs].some(x => x.includes('GPU-Only') || x === 'GPU-GPU') },
    { label: 'NPU-Only', style: `background:${COLORS.PURPLE}`,
      cond: () => [...deviceConfigs].some(x => x.includes('NPU-Only') || x === 'NPU-NPU') },
    { label: 'GPU/NPU Split', style: `background:${COLORS.BLUE}`,
      cond: () => [...deviceConfigs].some(x => (x.includes('GPU-NPU') || x.includes('NPU-GPU')) && !x.includes('Concurrent')) },
    { label: 'GPU/NPU Concurrent',
      style: stackedConcurrent
        ? `background:linear-gradient(to top, ${COLORS.GREEN} 50%, ${COLORS.PURPLE} 50%);border-radius:3px`
        : `background:${COLORS.GOLD}`,
      cond: () => hasConcurrent },
    { label: 'CPU-Only', style: `background:${COLORS.ORANGE}`,
      cond: () => [...deviceConfigs].some(x => x.includes('CPU')) },
  ];
  const active = allItems.filter(it => it.cond());
  const batchItems = [];
  if (batchSizes.size > 1) {
    if (batchSizes.has('1')) batchItems.push({ label: 'Batch 1 (lighter)', style: 'background:rgba(255,255,255,0.28);border:1px solid #444' });
    if (batchSizes.has('8')) batchItems.push({ label: 'Batch 8 (darker)', style: 'background:rgba(0,0,0,0.4);border:1px solid #444' });
  }
  return active.map(it => `<span class="legend-item"><span class="legend-color" style="${it.style}"></span>${it.label}</span>`).join('')
    + (batchItems.length ? '<span class="legend-item legend-break"></span>' + batchItems.map(it =>
      `<span class="legend-item"><span class="legend-color" style="${it.style}"></span>${it.label}</span>`).join('') : '');
}

/** Build legend HTML for vision benchmarks */
function buildVisionLegendHtml(summary, opts) {
  const showConcurrent = !opts || opts.showConcurrent !== false;
  const stackedConcurrent = (opts && opts.stackedConcurrent) || false;
  const compact = (opts && opts.compact) || false;
  const devices = new Set();
  const batches = new Set();
  summary.forEach(r => { devices.add(r.device); batches.add(r.batch); });
  const hasConcurrent = [...devices].some(d => d.includes('Concurrent'));
  const items = [
    { label: 'GPU', style: `background:${COLORS.GREEN}`, cond: () => devices.has('GPU') },
    { label: 'NPU', style: `background:${COLORS.PURPLE}`, cond: () => devices.has('NPU') },
    { label: 'GPU+NPU Concurrent',
      style: stackedConcurrent
        ? `background:linear-gradient(to top, ${COLORS.GREEN} 50%, ${COLORS.PURPLE} 50%);border-radius:3px`
        : `background:${COLORS.GOLD}`,
      cond: () => showConcurrent && hasConcurrent },
    { label: 'CPU', style: `background:${COLORS.ORANGE}`, cond: () => devices.has('CPU') },
  ];
  const active = items.filter(it => it.cond());
  const bp = compact ? 'BS' : 'Batch ';
  const batchItems = [];
  if (batches.size > 1) {
    if (batches.has('1')) batchItems.push({ label: `${bp}1 (lighter)`, style: 'background:rgba(255,255,255,0.28);border:1px solid #444' });
    if (batches.has('8')) batchItems.push({ label: `${bp}8`, style: 'background:rgba(100,100,100,0.5);border:1px solid #444' });
    if (batches.has('16')) batchItems.push({ label: `${bp}16 (darker)`, style: 'background:rgba(0,0,0,0.4);border:1px solid #444' });
  }
  return active.map(it => `<span class="legend-item"><span class="legend-color" style="${it.style}"></span>${it.label}</span>`).join('')
    + (batchItems.length ? '<span class="legend-item legend-break"></span>' + batchItems.map(it =>
      `<span class="legend-item"><span class="legend-color" style="${it.style}"></span>${it.label}</span>`).join('') : '');
}

/** Build legend HTML for media benchmarks */
function buildMediaLegendHtml(summary) {
  const codecs = new Set();
  const resolutions = new Set();
  summary.forEach(r => { codecs.add(r.codec); resolutions.add(r.resolution); });
  const items = [];
  if (codecs.has('h265')) items.push({ label: 'HEVC', style: `background:${COLORS.GREEN}` });
  if (codecs.has('h264')) items.push({ label: 'AVC', style: `background:${COLORS.BLUE}` });
  const resItems = [];
  if (resolutions.has('1080p')) resItems.push({ label: '1080p @30fps (lighter)', style: 'background:rgba(255,255,255,0.28);border:1px solid #444' });
  if (resolutions.has('4k')) resItems.push({ label: '4K @30fps (darker)', style: 'background:rgba(0,0,0,0.4);border:1px solid #444' });
  return items.map(it => `<span class="legend-item"><span class="legend-color" style="${it.style}"></span>${it.label}</span>`).join('')
    + (resItems.length > 1 ? '<span class="legend-item legend-break"></span>' + resItems.map(it =>
      `<span class="legend-item"><span class="legend-color" style="${it.style}"></span>${it.label}</span>`).join('') : '');
}

/** Map a GenAI benchmark record to a bar color based on device + precision */
function genaiDeviceColor(record) {
  const base = record.device === 'NPU' ? COLORS.PURPLE : COLORS.GREEN;
  const delta = record.precision === 'INT4_SYM_CW' ? 0 : -0.4;
  return shadeColor(base, delta);
}

/** Prettify GenAI model shortname for display */
function prettyGenaiModel(name) {
  return name
    .replace(/-/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase());
}

/** Shorten precision labels for display */
function shortPrecision(p) {
  if (p === 'INT8_ASYM') return 'INT8';
  if (p === 'INT4_SYM_CW') return 'INT4';
  return p;
}

/** Check if a GenAI record is an LLM model */
function isLLMModel(r) {
  return r.type === 'llm';
}

/** Build legend HTML for GenAI benchmarks */
function buildGenaiLegendHtml(summary) {
  const devices = new Set();
  const precisions = new Set();
  summary.forEach(r => { devices.add(r.device); precisions.add(r.precision); });
  const items = [];
  if (devices.has('GPU')) items.push({ label: 'GPU', style: `background:${COLORS.GREEN}` });
  if (devices.has('NPU')) items.push({ label: 'NPU', style: `background:${COLORS.PURPLE}` });
  const precItems = [];
  if (precisions.has('INT8_ASYM')) precItems.push({ label: 'INT8 (darker)', style: 'background:rgba(0,0,0,0.4);border:1px solid #444' });
  if (precisions.has('INT4_SYM_CW')) precItems.push({ label: 'INT4 (lighter)', style: 'background:rgba(255,255,255,0.28);border:1px solid #444' });
  return items.map(it => `<span class="legend-item"><span class="legend-color" style="${it.style}"></span>${it.label}</span>`).join('')
    + (precItems.length > 1 ? '<span class="legend-item legend-break"></span>' + precItems.map(it =>
      `<span class="legend-item"><span class="legend-color" style="${it.style}"></span>${it.label}</span>`).join('') : '');
}

// =========================================================================
// Base Dashboard (shared by Pipeline, Vision, Media, GenAI)
// =========================================================================

class BaseDashboard {
  constructor(summary, rawData, systemInfo) {
    this.summary = summary;
    this.rawData = rawData;
    this.systemInfo = systemInfo;
    this.bestConfigMode = 'performance';
    this.charts = {};
  }

  render() {
    this.updateTitle();
    if (this.setupToggle) this.setupToggle();
    this.renderTable();
    this.renderCharts();
    this.renderSystemInfo();
    this.renderRawData();
  }

  destroy() {
    Object.values(this.charts).forEach(c => c && c.destroy());
  }

  updateTitle() {
    const el = document.getElementById(this.titleId);
    if (el && this.systemInfo && this.systemInfo.system && this.systemInfo.system.name)
      el.textContent = `${this.titlePrefix} — ${this.systemInfo.system.name}`;
  }

  renderSystemInfo() {
    const el = document.getElementById(this.sysInfoId);
    if (el) el.textContent = this.systemInfo ? JSON.stringify(this.systemInfo, null, 2) : 'System information not available.';
  }

  renderRawData() {
    const el = document.getElementById(this.rawDataId);
    if (el && this.rawData.length > 0) el.textContent = JSON.stringify(this.rawData, null, 2);
  }

  updateBestConfigDisplay() {
    this.renderBestConfigSummary(this.getBestConfigurations());
  }
}

// =========================================================================
// Pipeline Dashboard (Edge AI Pipelines)
// =========================================================================

class PipelineDashboard extends BaseDashboard {
  constructor(summary, rawData, systemInfo) {
    super(summary, rawData, systemInfo);
    this.titleId = 'edgeTitle';
    this.titlePrefix = 'Edge AI Pipelines Dashboard';
    this.sysInfoId = 'systemInfoDump';
    this.rawDataId = 'rawDump';
    this.charts = { throughput: null, theoretical: null, efficiency: null, power: null };
    this.render();
  }

  setupToggle() {
    const perfBtn = document.getElementById('togglePerformance');
    const effBtn = document.getElementById('toggleEfficiency');
    if (!perfBtn || !effBtn) return;
    perfBtn.addEventListener('click', () => {
      this.bestConfigMode = 'performance';
      perfBtn.classList.add('active'); effBtn.classList.remove('active');
      this.updateBestConfigDisplay();
    });
    effBtn.addEventListener('click', () => {
      this.bestConfigMode = 'efficiency';
      effBtn.classList.add('active'); perfBtn.classList.remove('active');
      this.updateBestConfigDisplay();
    });
  }

  renderTable() {
    const tbody = document.getElementById('summaryRows');
    if (!tbody) return;
    const bestConfigs = this.getBestConfigurations();
    tbody.innerHTML = this.summary.map(record => {
      const fps = record.avg_throughput
        ? `<span class="status-success">${parseFloat(record.avg_throughput).toFixed(2)}</span>`
        : '<span class="status-error">Failed</span>';
      const streams = record.theoretical_streams
        ? `<span class="status-success">${record.theoretical_streams}${record.primary_theoretical != null && record.secondary_theoretical != null ? ` <small>(${esc(record.detect)}: ${record.primary_theoretical} | ${esc(record.classify)}: ${record.secondary_theoretical})</small>` : ''}</span>`
        : '<span class="status-error">N/A</span>';
      const power = record.avg_power && record.avg_power !== 'NA' ? `${parseFloat(record.avg_power).toFixed(2)}` : 'N/A';
      const eff = record.efficiency && record.efficiency !== 'NA' ? `${parseFloat(record.efficiency).toFixed(2)}` : 'N/A';
      const cn = record.config.charAt(0).toUpperCase() + record.config.slice(1).toLowerCase();
      const isBest = bestConfigs[record.config] === record;
      const configCell = isBest ? `<span class="pill best-config">${esc(cn)}</span>` : `<span class="pill">${esc(cn)}</span>`;
      const dc = record.device_config || `${record.detect}/${record.classify}`;
      return `<tr${isBest ? ' class="best-row"' : ''}>
        <td>${configCell}</td><td>${esc(dc)}</td><td>${esc(record.batch)}</td><td>${record.runs}</td>
        <td>${fps}</td><td>${streams}</td><td>${power}</td><td>${eff}</td></tr>`;
    }).join('');
    this.renderBestConfigSummary(bestConfigs);
  }

  getBestConfigurations(mode) {
    mode = mode || this.bestConfigMode;
    const groups = { light: [], medium: [], heavy: [] };
    this.summary.forEach(r => { if (groups[r.config]) groups[r.config].push(r); });
    const best = {};
    Object.keys(groups).forEach(k => {
      if (groups[k].length > 0)
        best[k] = groups[k].reduce((b, c) => {
          if (mode === 'efficiency') return (c.efficiency || 0) > (b.efficiency || 0) ? c : b;
          return (c.avg_throughput || 0) > (b.avg_throughput || 0) ? c : b;
        });
    });
    return best;
  }

  renderBestConfigSummary(bestConfigs) {
    const container = document.getElementById('bestConfigContent');
    if (!container) return;
    const mode = this.bestConfigMode;
    const items = Object.entries(bestConfigs).map(([ct, r]) => {
      const cn = ct.charAt(0).toUpperCase() + ct.slice(1).toLowerCase();
      const dc = r.device_config || `${r.detect}/${r.classify}`;
      const modeClass = mode === 'efficiency' ? 'efficiency-mode' : '';
      if (mode === 'efficiency') {
        if (!r.efficiency || r.efficiency === 'NA') return '';
        const stats = [];
        stats.push(stat('Device', dc));
        stats.push(stat('Batch', r.batch));
        stats.push(stat('Throughput', `${fmtNum(r.avg_throughput)} FPS`));
        stats.push(stat('Power', `${fmtNum(r.avg_power)} W`));
        return bestCard(modeClass, 'Best Efficiency', cn, fmtNum(r.efficiency), 'FPS/W', stats);
      }
      if (!r.avg_throughput) return '';
      const stats = [];
      stats.push(stat('Device', dc));
      stats.push(stat('Batch', r.batch));
      if (r.theoretical_streams) stats.push(stat('Streams', r.theoretical_streams));
      if (r.avg_power && r.avg_power !== 'NA') stats.push(stat('Power', `${fmtNum(r.avg_power)} W`));
      return bestCard(modeClass, 'Best Performance', cn, fmtNum(r.avg_throughput), 'FPS', stats);
    }).filter(Boolean);
    if (items.length > 0) {
      container.innerHTML = `<div class="best-config-grid">${items.join('')}</div>`;
      document.getElementById('bestConfigSummary').style.display = 'block';
    }
  }

  renderCharts() {
    const valid = this.summary.filter(r => r.avg_throughput != null && r.theoretical_streams != null);
    this.validData = valid;
    if (!valid.length) return;

    const labels = valid.map(r => `B${r.batch}`);
    const groups = computeGroups(valid, r => r.config);
    const subGroups = computeGroups(valid, r => r.device_config || `${r.detect}-${r.classify}`);
    const bgColors = valid.map(r => edgeDeviceColor(r));
    const opts = baseChartOptions(groups);
    opts.layout.padding.bottom = 30;
    opts.plugins.subGroupLabelPlugin = { subGroups };

    const tooltipCb = {
      title: (items) => {
        const r = this.validData[items[0].dataIndex];
        const dc = r.device_config || `${r.detect}/${r.classify}`;
        return `${r.config.charAt(0).toUpperCase() + r.config.slice(1)} | ${dc} Batch ${r.batch}`;
      }
    };

    Object.values(this.charts).forEach(c => c && c.destroy());

    const makeChart = (id, data, yLabel) => {
      const ctx = document.getElementById(id);
      if (!ctx) return null;
      const o = JSON.parse(JSON.stringify(opts));
      o.scales.y.title.text = yLabel;
      o.plugins.tooltip = { callbacks: tooltipCb };
      return new Chart(ctx, {
        type: 'bar',
        data: { labels, datasets: [{ data, backgroundColor: bgColors, borderWidth: 0 }] },
        options: o,
        plugins: [createGroupLabelPlugin(), createSubGroupLabelPlugin(), createValueLabelPlugin()]
      });
    };

    // Throughput chart with stacked bars for concurrent
    const isConcurrent = (r) => r.device_config && r.device_config.includes('Concurrent');
    const primaryData = [];
    const secondaryData = [];
    const primaryColors = [];
    const secondaryColors = [];

    valid.forEach(r => {
      if (isConcurrent(r) && r.primary_fps != null && r.secondary_fps != null) {
        primaryData.push(r.primary_fps);
        secondaryData.push(r.secondary_fps);
        primaryColors.push(shadeColor(COLORS.GREEN, batchShade(r.batch)));
        secondaryColors.push(shadeColor(COLORS.PURPLE, batchShade(r.batch)));
      } else {
        primaryData.push(r.avg_throughput);
        secondaryData.push(0);
        primaryColors.push(edgeDeviceColor(r));
        secondaryColors.push('transparent');
      }
    });

    const hasStacked = secondaryData.some(v => v > 0);
    const thrOpts = JSON.parse(JSON.stringify(opts));
    thrOpts.scales.y.title.text = 'Frames per Second (FPS)';
    if (hasStacked) {
      thrOpts.scales.x.stacked = true;
      thrOpts.scales.y.stacked = true;
    }
    thrOpts.plugins.tooltip = {
      callbacks: {
        title: (items) => {
          const r = this.validData[items[0].dataIndex];
          const dc = r.device_config || `${r.detect}/${r.classify}`;
          return `${r.config.charAt(0).toUpperCase() + r.config.slice(1)} | ${dc} Batch ${r.batch}`;
        },
        label: (item) => {
          const r = this.validData[item.dataIndex];
          if (isConcurrent(r) && r.primary_fps != null && r.secondary_fps != null) {
            const total = parseFloat(r.avg_throughput).toFixed(1);
            const pri = parseFloat(r.primary_fps).toFixed(1);
            const sec = parseFloat(r.secondary_fps).toFixed(1);
            return `Total: ${total} FPS (${r.detect}: ${pri}, ${r.classify}: ${sec})`;
          }
          return `${parseFloat(r.avg_throughput).toFixed(1)} FPS`;
        }
      }
    };
    const thrCtx = document.getElementById('thrChart');
    if (thrCtx) {
      const datasets = [{ data: primaryData, backgroundColor: primaryColors, borderWidth: 0, stack: 'stack0' }];
      if (hasStacked) datasets.push({ data: secondaryData, backgroundColor: secondaryColors, borderWidth: 0, stack: 'stack0' });
      this.charts.throughput = new Chart(thrCtx, {
        type: 'bar',
        data: { labels, datasets },
        options: thrOpts,
        plugins: [createGroupLabelPlugin(), createSubGroupLabelPlugin(), hasStacked ? createStackedValueLabelPlugin() : createValueLabelPlugin()]
      });
    }

    // Theoretical streams chart with stacking for concurrent pipelines
    const theoPri = [], theoSec = [], theoPriColors = [], theoSecColors = [];
    valid.forEach(r => {
      if (isConcurrent(r) && r.primary_theoretical != null && r.secondary_theoretical != null) {
        theoPri.push(r.primary_theoretical);
        theoSec.push(r.secondary_theoretical);
        theoPriColors.push(shadeColor(COLORS.GREEN, batchShade(r.batch)));
        theoSecColors.push(shadeColor(COLORS.PURPLE, batchShade(r.batch)));
      } else {
        theoPri.push(r.theoretical_streams);
        theoSec.push(0);
        theoPriColors.push(edgeDeviceColor(r));
        theoSecColors.push('transparent');
      }
    });
    const hasStackedTheo = theoSec.some(v => v > 0);
    const theoOpts = JSON.parse(JSON.stringify(opts));
    theoOpts.scales.y.title.text = 'Number of Streams';
    if (hasStackedTheo) { theoOpts.scales.x.stacked = true; theoOpts.scales.y.stacked = true; }
    theoOpts.plugins.tooltip = {
      callbacks: {
        title: (items) => {
          const r = this.validData[items[0].dataIndex];
          const dc = r.device_config || `${r.detect}/${r.classify}`;
          return `${r.config.charAt(0).toUpperCase() + r.config.slice(1)} | ${dc} Batch ${r.batch}`;
        },
        label: (item) => {
          const r = this.validData[item.dataIndex];
          if (isConcurrent(r) && r.primary_theoretical != null && r.secondary_theoretical != null)
            return `Total: ${r.theoretical_streams} (${r.detect}: ${r.primary_theoretical}, ${r.classify}: ${r.secondary_theoretical})`;
          return `${r.theoretical_streams} streams`;
        }
      }
    };
    const theoCtx = document.getElementById('theoChart');
    if (theoCtx) {
      const datasets = [{ data: theoPri, backgroundColor: theoPriColors, borderWidth: 0, stack: 'stack0' }];
      if (hasStackedTheo) datasets.push({ data: theoSec, backgroundColor: theoSecColors, borderWidth: 0, stack: 'stack0' });
      this.charts.theoretical = new Chart(theoCtx, {
        type: 'bar', data: { labels, datasets }, options: theoOpts,
        plugins: [createGroupLabelPlugin(), createSubGroupLabelPlugin(), hasStackedTheo ? createStackedValueLabelPlugin() : createValueLabelPlugin()]
      });
    }

    const effData = valid.map(r => r.efficiency && r.efficiency !== 'NA' ? parseFloat(r.efficiency) : null);
    if (effData.some(v => v != null))
      this.charts.efficiency = makeChart('effChart', effData, 'FPS per Watt');

    const pwrData = valid.map(r => r.avg_power && r.avg_power !== 'NA' ? parseFloat(r.avg_power) : null);
    if (pwrData.some(v => v != null))
      this.charts.power = makeChart('powerChart', pwrData, 'Package Power (W)');

    this.renderLegends();
  }

  renderLegends() {
    setLegend('legendThroughput', buildEdgeLegendHtml(this.summary, { stackedConcurrent: true }));
    setLegend('legendEfficiency', buildEdgeLegendHtml(this.summary, {}));
    setLegend('legendTheoretical', buildEdgeLegendHtml(this.summary, { stackedConcurrent: true }));
    setLegend('legendPower', buildEdgeLegendHtml(this.summary, {}));
  }
}


// =========================================================================
// Vision Dashboard (Vision Benchmarks)
// =========================================================================

class VisionDashboard extends BaseDashboard {
  constructor(summary, rawData, systemInfo) {
    super(summary, rawData, systemInfo);
    this.titleId = 'visionTitle';
    this.titlePrefix = 'Vision Benchmarks Dashboard';
    this.sysInfoId = 'vSystemInfoDump';
    this.rawDataId = 'vRawDump';
    this.charts = { throughputDet: null, throughputCls: null, latencyDet: null, latencyCls: null, efficiencyDet: null, efficiencyCls: null, powerDet: null, powerCls: null };
    this.render();
  }

  setupToggle() {
    const perfBtn = document.getElementById('vTogglePerformance');
    const perfSingleBtn = document.getElementById('vTogglePerfSingle');
    const latBtn = document.getElementById('vToggleLatency');
    const effBtn = document.getElementById('vToggleEfficiency');
    if (!perfBtn || !perfSingleBtn || !latBtn || !effBtn) return;
    const allBtns = [perfBtn, perfSingleBtn, latBtn, effBtn];
    const activate = (btn, mode) => {
      this.bestConfigMode = mode;
      allBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      this.updateBestConfigDisplay();
    };
    perfBtn.addEventListener('click', () => activate(perfBtn, 'performance'));
    perfSingleBtn.addEventListener('click', () => activate(perfSingleBtn, 'performance-single'));
    latBtn.addEventListener('click', () => activate(latBtn, 'latency'));
    effBtn.addEventListener('click', () => activate(effBtn, 'efficiency'));
  }

  renderTable() {
    const tbody = document.getElementById('vSummaryRows');
    if (!tbody) return;
    const bestConfigs = this.getBestConfigurations();
    const bestSet = new Set(Object.values(bestConfigs));

    tbody.innerHTML = this.summary.map(r => {
      const thr = r.avg_throughput != null
        ? `<span class="status-success">${parseFloat(r.avg_throughput).toFixed(2)}</span>`
        : '<span class="status-error">N/A</span>';
      const lat = r.median_latency != null
        ? `${parseFloat(r.median_latency).toFixed(2)}`
        : 'N/A';
      const pwr = r.avg_power != null ? `${parseFloat(r.avg_power).toFixed(2)}` : 'N/A';
      const eff = r.efficiency != null ? `${parseFloat(r.efficiency).toFixed(2)}` : 'N/A';
      const isBest = bestSet.has(r);
      const modelCell = isBest
        ? `<span class="pill best-config">${esc(prettyModel(r.model))}</span>`
        : `<span class="pill">${esc(prettyModel(r.model))}</span>`;
      const modeLabel = r.mode === 'tput' ? 'Throughput' : r.mode === 'latency' ? 'Latency' : r.mode;
      return `<tr${isBest ? ' class="best-row"' : ''}>
        <td>${modelCell}</td><td>${esc(r.device)}</td><td>${esc(modeLabel)}</td><td>${esc(r.batch)}</td>
        <td>${thr}</td><td>${lat}</td><td>${pwr}</td><td>${eff}</td></tr>`;
    }).join('');
    this.renderBestConfigSummary(bestConfigs);
  }

  getBestConfigurations(mode) {
    mode = mode || this.bestConfigMode;
    const isSingle = mode === 'performance-single';
    const groups = {};
    this.summary.forEach(r => {
      if (isSingle && r.concurrent && r.concurrent !== 'None') return;
      if (!groups[r.model]) groups[r.model] = [];
      groups[r.model].push(r);
    });
    const best = {};
    Object.keys(groups).forEach(model => {
      if (groups[model].length > 0)
        best[model] = groups[model].reduce((b, c) => {
          if (mode === 'efficiency') return (c.efficiency || 0) > (b.efficiency || 0) ? c : b;
          if (mode === 'latency') {
            const cLat = c.median_latency; const bLat = b.median_latency;
            if (cLat == null) return b;
            if (bLat == null) return c;
            return cLat < bLat ? c : b;
          }
          return (c.avg_throughput || 0) > (b.avg_throughput || 0) ? c : b;
        });
    });
    return best;
  }

  renderBestConfigSummary(bestConfigs) {
    const container = document.getElementById('vBestConfigContent');
    if (!container) return;
    const mode = this.bestConfigMode;
    const items = Object.entries(bestConfigs).map(([model, r]) => {
      const mn = prettyModel(model);
      if (mode === 'efficiency') {
        if (!r.efficiency) return '';
        const modeClass = 'efficiency-mode';
        const stats = [];
        stats.push(stat('Device', r.device));
        stats.push(stat('Batch', r.batch));
        stats.push(stat('Mode', r.mode));
        stats.push(stat('Throughput', `${fmtNum(r.avg_throughput)} FPS`));
        stats.push(stat('Power', `${fmtNum(r.avg_power)} W`));
        return bestCard(modeClass, 'Best Efficiency', mn, fmtNum(r.efficiency), 'FPS/W', stats);
      }
      if (mode === 'latency') {
        if (r.median_latency == null) return '';
        const modeClass = 'latency-mode';
        const stats = [];
        stats.push(stat('Device', r.device));
        stats.push(stat('Batch', r.batch));
        stats.push(stat('Mode', r.mode));
        if (r.avg_throughput != null) stats.push(stat('Throughput', `${fmtNum(r.avg_throughput)} FPS`));
        if (r.avg_power && r.avg_power !== 'NA') stats.push(stat('Power', `${fmtNum(r.avg_power)} W`));
        return bestCard(modeClass, 'Best Latency', mn, fmtNum(r.median_latency), 'ms', stats);
      }
      if (!r.avg_throughput) return '';
      const modeClass = mode === 'performance-single' ? 'perf-single-mode' : '';
      const label = mode === 'performance-single' ? 'Best (Single Device)' : 'Best Performance';
      const stats = [];
      stats.push(stat('Device', r.device));
      stats.push(stat('Batch', r.batch));
      stats.push(stat('Mode', r.mode));
      if (r.median_latency != null) stats.push(stat('Latency', `${fmtNum(r.median_latency)} ms`));
      if (r.avg_power && r.avg_power !== 'NA') stats.push(stat('Power', `${fmtNum(r.avg_power)} W`));
      return bestCard(modeClass, label, mn, fmtNum(r.avg_throughput), 'FPS', stats);
    }).filter(Boolean);
    if (items.length > 0) {
      container.innerHTML = `<div class="best-config-grid">${items.join('')}</div>`;
      document.getElementById('vBestConfigSummary').style.display = 'block';
    }
  }

  renderCharts() {
    Object.values(this.charts).forEach(c => c && c.destroy());

    // ---- Throughput charts: split into Detection and Classification ----
    const tputData = this.summary.filter(r => r.mode === 'tput' && r.avg_throughput != null);
    const tputDet = tputData.filter(r => isDetectionModel(r));
    const tputCls = tputData.filter(r => !isDetectionModel(r));

    const buildThroughputChart = (subset, canvasId, chartKey, subsetRef) => {
      if (!subset.length) return;
      this[subsetRef] = subset;
      const labels = subset.map(r => `B${r.batch}`);
      const groups = computeGroups(subset, r => r.model);
      groups.forEach(g => { g.name = prettyModel(g.name); });

      const primaryData = [];
      const secondaryData = [];
      const primaryColors = [];
      const secondaryColors = [];

      subset.forEach(r => {
        const isConcurrent = r.concurrent && r.concurrent !== 'None';
        if (isConcurrent && r.primary_fps != null && r.secondary_fps != null) {
          primaryData.push(r.primary_fps);
          secondaryData.push(r.secondary_fps);
          primaryColors.push(shadeColor(COLORS.GREEN, batchShade(r.batch)));
          secondaryColors.push(shadeColor(COLORS.PURPLE, batchShade(r.batch)));
        } else {
          primaryData.push(r.avg_throughput);
          secondaryData.push(0);
          primaryColors.push(visionDeviceColor(r.device, r.batch));
          secondaryColors.push('transparent');
        }
      });

      const hasStacked = secondaryData.some(v => v > 0);
      const opts = baseChartOptions(groups);
      opts.scales.y.title.text = 'Frames per Second (FPS)';
      if (hasStacked) {
        opts.scales.x.stacked = true;
        opts.scales.y.stacked = true;
      }
      opts.plugins.tooltip = {
        callbacks: {
          title: (items) => {
            const r = this[subsetRef][items[0].dataIndex];
            return `${prettyModel(r.model)} | ${r.device} BS${r.batch}`;
          },
          label: (item) => {
            const r = this[subsetRef][item.dataIndex];
            const isConcurrent = r.concurrent && r.concurrent !== 'None';
            if (isConcurrent && r.primary_fps != null && r.secondary_fps != null) {
              const total = parseFloat(r.avg_throughput).toFixed(1);
              const pri = parseFloat(r.primary_fps).toFixed(1);
              const sec = parseFloat(r.secondary_fps).toFixed(1);
              const priDev = r.device.split('-')[0];
              const secDev = r.concurrent;
              return `Total: ${total} FPS (${priDev}: ${pri}, ${secDev}: ${sec})`;
            }
            return `${parseFloat(r.avg_throughput).toFixed(1)} FPS`;
          }
        }
      };

      const ctx = document.getElementById(canvasId);
      if (ctx) {
        const datasets = [{
          label: 'Primary Device',
          data: primaryData,
          backgroundColor: primaryColors,
          borderWidth: 0,
          stack: 'stack0'
        }];
        if (hasStacked) {
          datasets.push({
            label: 'Secondary Device',
            data: secondaryData,
            backgroundColor: secondaryColors,
            borderWidth: 0,
            stack: 'stack0'
          });
        }
        this.charts[chartKey] = new Chart(ctx, {
          type: 'bar',
          data: { labels, datasets },
          options: opts,
          plugins: [createGroupLabelPlugin(), hasStacked ? createStackedValueLabelPlugin() : createValueLabelPlugin()]
        });
      }
    };

    buildThroughputChart(tputDet, 'vThrChartDet', 'throughputDet', 'tputDetData');
    buildThroughputChart(tputCls, 'vThrChartCls', 'throughputCls', 'tputClsData');

    // ---- Latency charts: latency mode only, non-concurrent, split Det/Cls ----
    const latAll = this.summary.filter(r =>
      r.mode === 'latency' && r.median_latency != null && (r.concurrent === 'None' || !r.concurrent)
    );
    const latDet = latAll.filter(r => isDetectionModel(r));
    const latCls = latAll.filter(r => !isDetectionModel(r));

    const buildLatencyChart = (subset, canvasId, chartKey, dataRef) => {
      if (!subset.length) return;
      this[dataRef] = subset;
      const labels = subset.map(r => `B${r.batch}`);
      const groups = computeGroups(subset, r => r.model);
      groups.forEach(g => { g.name = prettyModel(g.name); });
      const bgColors = subset.map(r => visionDeviceColor(r.device, '8'));
      const opts = baseChartOptions(groups);
      opts.scales.y.title.text = 'Median Latency (ms)';
      opts.plugins.tooltip = {
        callbacks: {
          title: (items) => {
            const r = this[dataRef][items[0].dataIndex];
            return `${prettyModel(r.model)} | ${r.device} BS${r.batch}`;
          },
          label: (item) => `${parseFloat(this[dataRef][item.dataIndex].median_latency).toFixed(2)} ms`
        }
      };
      const ctx = document.getElementById(canvasId);
      if (ctx) {
        this.charts[chartKey] = new Chart(ctx, {
          type: 'bar',
          data: { labels, datasets: [{ data: subset.map(r => r.median_latency), backgroundColor: bgColors, borderWidth: 0 }] },
          options: opts,
          plugins: [createGroupLabelPlugin(), createValueLabelPlugin(2)]
        });
      }
    };
    buildLatencyChart(latDet, 'vLatChartDet', 'latencyDet', 'latDetData');
    buildLatencyChart(latCls, 'vLatChartCls', 'latencyCls', 'latClsData');

    // ---- Efficiency charts: tput mode only, split Det/Cls ----
    const effAll = this.summary.filter(r => r.mode === 'tput' && r.efficiency != null);
    const effDet = effAll.filter(r => isDetectionModel(r));
    const effCls = effAll.filter(r => !isDetectionModel(r));

    const buildSimpleChart = (subset, canvasId, chartKey, dataRef, yLabel, field, unit, decimals) => {
      if (!subset.length) return;
      this[dataRef] = subset;
      const labels = subset.map(r => `B${r.batch}`);
      const groups = computeGroups(subset, r => r.model);
      groups.forEach(g => { g.name = prettyModel(g.name); });
      const bgColors = subset.map(r => visionDeviceColor(r.device, r.batch));
      const opts = baseChartOptions(groups);
      opts.scales.y.title.text = yLabel;
      opts.plugins.tooltip = {
        callbacks: {
          title: (items) => {
            const r = this[dataRef][items[0].dataIndex];
            return `${prettyModel(r.model)} | ${r.device} BS${r.batch}`;
          },
          label: (item) => `${parseFloat(this[dataRef][item.dataIndex][field]).toFixed(2)} ${unit}`
        }
      };
      const ctx = document.getElementById(canvasId);
      if (ctx) {
        this.charts[chartKey] = new Chart(ctx, {
          type: 'bar',
          data: { labels, datasets: [{ data: subset.map(r => r[field]), backgroundColor: bgColors, borderWidth: 0 }] },
          options: opts,
          plugins: [createGroupLabelPlugin(), createValueLabelPlugin(decimals)]
        });
      }
    };
    buildSimpleChart(effDet, 'vEffChartDet', 'efficiencyDet', 'effDetData', 'FPS per Watt', 'efficiency', 'FPS/W');
    buildSimpleChart(effCls, 'vEffChartCls', 'efficiencyCls', 'effClsData', 'FPS per Watt', 'efficiency', 'FPS/W');

    // ---- Power charts: tput mode only, split Det/Cls ----
    const pwrAll = this.summary.filter(r => r.avg_power != null && r.mode === 'tput');
    const pwrDet = pwrAll.filter(r => isDetectionModel(r));
    const pwrCls = pwrAll.filter(r => !isDetectionModel(r));
    buildSimpleChart(pwrDet, 'vPowerChartDet', 'powerDet', 'pwrDetData', 'Package Power (W)', 'avg_power', 'W');
    buildSimpleChart(pwrCls, 'vPowerChartCls', 'powerCls', 'pwrClsData', 'Package Power (W)', 'avg_power', 'W');

    this.renderLegends();
  }

  renderLegends() {
    setLegend('vLegendThroughputDet', buildVisionLegendHtml(this.summary, { stackedConcurrent: true }));
    setLegend('vLegendThroughputCls', buildVisionLegendHtml(this.summary, { stackedConcurrent: true }));
    setLegend('vLegendLatencyDet', buildVisionLegendHtml(this.summary, { showConcurrent: false }));
    setLegend('vLegendLatencyCls', buildVisionLegendHtml(this.summary, { showConcurrent: false }));
    setLegend('vLegendEfficiencyDet', buildVisionLegendHtml(this.summary, {}));
    setLegend('vLegendEfficiencyCls', buildVisionLegendHtml(this.summary, {}));
    setLegend('vLegendPowerDet', buildVisionLegendHtml(this.summary, {}));
    setLegend('vLegendPowerCls', buildVisionLegendHtml(this.summary, {}));
  }
}


// =========================================================================
// Media Dashboard (Media Benchmarks)
// =========================================================================

class MediaDashboard extends BaseDashboard {
  constructor(summary, rawData, systemInfo) {
    super(summary, rawData, systemInfo);
    this.titleId = 'mediaTitle';
    this.titlePrefix = 'Media Benchmarks Dashboard';
    this.sysInfoId = 'mSystemInfoDump';
    this.rawDataId = 'mRawDump';
    this.charts = { throughput: null, theoretical: null, efficiency: null, power: null };
    this.render();
  }

  /** Label for chart x-axis: "bears" or "apple" */
  shortLabel(record) {
    return record.media;
  }

  renderTable() {
    const tbody = document.getElementById('mSummaryRows');
    if (!tbody) return;
    tbody.innerHTML = this.summary.map(r => {
      const thr = r.avg_throughput != null
        ? `<span class="status-success">${parseFloat(r.avg_throughput).toFixed(2)}</span>`
        : '<span class="status-error">N/A</span>';
      const streams = r.theoretical_streams != null
        ? `<span class="status-success">${r.theoretical_streams}</span>`
        : '<span class="status-error">N/A</span>';
      const pwr = r.avg_power != null ? `${parseFloat(r.avg_power).toFixed(2)}` : 'N/A';
      const eff = r.efficiency != null ? `${parseFloat(r.efficiency).toFixed(2)}` : 'N/A';
      return `<tr>
        <td>${esc(r.media)}</td><td>${esc(r.codec.toUpperCase())}</td><td>${esc(r.resolution)}</td>
        <td>${esc(r.streams)}</td><td>${esc(r.runs)}</td>
        <td>${thr}</td><td>${streams}</td><td>${pwr}</td><td>${eff}</td></tr>`;
    }).join('');
  }

  renderCharts() {
    const valid = this.summary.filter(r => r.avg_throughput != null);
    this.validData = valid;
    if (!valid.length) return;

    const labels = valid.map(r => this.shortLabel(r));
    // Group by "codec + resolution" e.g. "H265 1080p @30fps", "H264 4K @30fps"
    const resLabel = (r) => r.resolution === '4k' ? '4K @30fps' : `${r.resolution} @30fps`;
    const groups = computeGroups(valid, r => `${r.codec.toUpperCase()} ${resLabel(r)}`);
    const bgColors = valid.map(r => mediaRecordColor(r));
    const opts = baseChartOptions(groups);

    const tooltipCb = {
      title: (items) => {
        const r = this.validData[items[0].dataIndex];
        return `${r.media} | ${r.codec.toUpperCase()} ${r.resolution} x${r.streams} streams`;
      }
    };

    Object.values(this.charts).forEach(c => c && c.destroy());

    const makeChart = (id, data, yLabel) => {
      const ctx = document.getElementById(id);
      if (!ctx) return null;
      const o = JSON.parse(JSON.stringify(opts));
      o.scales.y.title.text = yLabel;
      o.plugins.tooltip = { callbacks: tooltipCb };
      return new Chart(ctx, {
        type: 'bar',
        data: { labels, datasets: [{ data, backgroundColor: bgColors, borderWidth: 0 }] },
        options: o,
        plugins: [createGroupLabelPlugin(), createValueLabelPlugin()]
      });
    };

    this.charts.throughput = makeChart('mThrChart', valid.map(r => r.avg_throughput), 'Frames per Second (FPS)');

    const theoData = valid.map(r => r.theoretical_streams);
    if (theoData.some(v => v != null))
      this.charts.theoretical = makeChart('mTheoChart', theoData, 'Number of Streams');

    const effData = valid.map(r => r.efficiency != null ? parseFloat(r.efficiency) : null);
    if (effData.some(v => v != null))
      this.charts.efficiency = makeChart('mEffChart', effData, 'FPS per Watt');

    const pwrData = valid.map(r => r.avg_power != null ? parseFloat(r.avg_power) : null);
    if (pwrData.some(v => v != null))
      this.charts.power = makeChart('mPowerChart', pwrData, 'Package Power (W)');

    this.renderLegends();
  }

  renderLegends() {
    const html = buildMediaLegendHtml(this.summary);
    ['mLegendThroughput', 'mLegendTheoretical', 'mLegendEfficiency', 'mLegendPower'].forEach(id => setLegend(id, html));
  }
}


// =========================================================================
// GenAI Dashboard (GenAI Benchmarks)
// =========================================================================

class GenaiDashboard extends BaseDashboard {
  constructor(summary, rawData, systemInfo) {
    super(summary, rawData, systemInfo);
    this.titleId = 'genaiTitle';
    this.titlePrefix = 'GenAI Benchmarks Dashboard';
    this.sysInfoId = 'gSystemInfoDump';
    this.rawDataId = 'gRawDump';
    this.charts = {
      throughputLLM: null,
      latencyLLM: null,
      efficiencyLLM: null,
      powerLLM: null,
      throughputVLM: null,
      latencyVLM: null,
      efficiencyVLM: null,
      powerVLM: null
    };
    this.render();
  }

  setupToggle() {
    const perfBtn = document.getElementById('gTogglePerformance');
    const latBtn = document.getElementById('gToggleLatency');
    const effBtn = document.getElementById('gToggleEfficiency');
    if (!perfBtn || !latBtn || !effBtn) return;
    const allBtns = [perfBtn, latBtn, effBtn];
    const activate = (btn, mode) => {
      this.bestConfigMode = mode;
      allBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      this.updateBestConfigDisplay();
    };
    perfBtn.addEventListener('click', () => activate(perfBtn, 'performance'));
    latBtn.addEventListener('click', () => activate(latBtn, 'latency'));
    effBtn.addEventListener('click', () => activate(effBtn, 'efficiency'));
  }

  renderTable() {
    const tbody = document.getElementById('gSummaryRows');
    if (!tbody) return;
    const bestConfigs = this.getBestConfigurations();
    const bestSet = new Set(Object.values(bestConfigs));
    tbody.innerHTML = this.summary.map(r => {
      const thr = r.second_token_throughput != null
        ? `<span class="status-success">${parseFloat(r.second_token_throughput).toFixed(2)}</span>`
        : '<span class="status-error">N/A</span>';
      const lat = r.first_token_latency != null
        ? `${parseFloat(r.first_token_latency).toFixed(2)}`
        : 'N/A';
      const pwr = r.avg_power != null ? `${parseFloat(r.avg_power).toFixed(2)}` : 'N/A';
      const eff = r.efficiency != null ? `${parseFloat(r.efficiency).toFixed(2)}` : 'N/A';
      const isBest = bestSet.has(r);
      const modelCell = isBest
        ? `<span class="pill best-config">${esc(prettyGenaiModel(r.model))}</span>`
        : `<span class="pill">${esc(prettyGenaiModel(r.model))}</span>`;
      const typeLabel = (r.type || 'llm').toUpperCase();
      return `<tr${isBest ? ' class="best-row"' : ''}>
        <td>${modelCell}</td><td>${esc(r.device)}</td><td>${esc(shortPrecision(r.precision))}</td><td>${esc(typeLabel)}</td>
        <td>${lat}</td><td>${thr}</td><td>${pwr}</td><td>${eff}</td></tr>`;
    }).join('');
    this.renderBestConfigSummary(bestConfigs);
  }

  getBestConfigurations(mode) {
    mode = mode || this.bestConfigMode;
    const groups = {};
    this.summary.forEach(r => {
      if (!groups[r.model]) groups[r.model] = [];
      groups[r.model].push(r);
    });
    const best = {};
    Object.keys(groups).forEach(model => {
      if (groups[model].length > 0)
        best[model] = groups[model].reduce((b, c) => {
          if (mode === 'efficiency') return (c.efficiency || 0) > (b.efficiency || 0) ? c : b;
          if (mode === 'latency') {
            const cLat = c.first_token_latency; const bLat = b.first_token_latency;
            if (cLat == null) return b;
            if (bLat == null) return c;
            return cLat < bLat ? c : b;
          }
          return (c.second_token_throughput || 0) > (b.second_token_throughput || 0) ? c : b;
        });
    });
    return best;
  }

  renderBestConfigSummary(bestConfigs) {
    const container = document.getElementById('gBestConfigContent');
    if (!container) return;
    const mode = this.bestConfigMode;
    const makeCard = (model, r) => {
      const mn = prettyGenaiModel(model);
      if (mode === 'efficiency') {
        if (!r.efficiency) return '';
        return bestCard('efficiency-mode', 'Best Efficiency', mn, fmtNum(r.efficiency), 'tpt/W', [
          stat('Device', r.device), stat('Precision', shortPrecision(r.precision)),
          stat('Throughput', `${fmtNum(r.second_token_throughput)} tok/s`),
          stat('Power', `${fmtNum(r.avg_power)} W`)
        ]);
      }
      if (mode === 'latency') {
        if (r.first_token_latency == null) return '';
        return bestCard('latency-mode', 'Best Latency', mn, fmtNum(r.first_token_latency), 'ms', [
          stat('Device', r.device), stat('Precision', shortPrecision(r.precision)),
          stat('Throughput', `${fmtNum(r.second_token_throughput)} tok/s`),
          stat('Power', r.avg_power != null ? `${fmtNum(r.avg_power)} W` : 'N/A')
        ]);
      }
      if (!r.second_token_throughput) return '';
      return bestCard('', 'Best Performance', mn, fmtNum(r.second_token_throughput), 'tok/s', [
        stat('Device', r.device), stat('Precision', shortPrecision(r.precision)),
        stat('Latency', r.first_token_latency != null ? `${fmtNum(r.first_token_latency)} ms` : 'N/A'),
        stat('Power', r.avg_power != null ? `${fmtNum(r.avg_power)} W` : 'N/A')
      ]);
    };
    const llmCards = Object.entries(bestConfigs)
      .filter(([m, r]) => isLLMModel(r)).map(([m, r]) => makeCard(m, r)).filter(Boolean);
    const mmCards = Object.entries(bestConfigs)
      .filter(([m, r]) => !isLLMModel(r)).map(([m, r]) => makeCard(m, r)).filter(Boolean);
    let html = '';
    if (llmCards.length) html += `<h4 style="margin:0 0 0.5rem 0;color:var(--text-secondary)">LLM</h4><div class="best-config-grid">${llmCards.join('')}</div>`;
    if (mmCards.length) html += `<h4 style="margin:1rem 0 0.5rem 0;color:var(--text-secondary)">VLM</h4><div class="best-config-grid">${mmCards.join('')}</div>`;
    if (html) {
      container.innerHTML = html;
      document.getElementById('gBestConfigSummary').style.display = 'block';
    }
  }

  renderCharts() {
    Object.values(this.charts).forEach(c => c && c.destroy());

    const llm = this.summary.filter(r => isLLMModel(r));
    const vlm = this.summary.filter(r => !isLLMModel(r));

    const buildChart = (subset, canvasId, chartKey, dataRef, yLabel, field, unit, decimals) => {
      if (!subset.length) return;
      this[dataRef] = subset;
      const labels = subset.map(r => shortPrecision(r.precision));
      const groups = computeGroups(subset, r => r.model);
      groups.forEach(g => { g.name = prettyGenaiModel(g.name); });
      const bgColors = subset.map(r => genaiDeviceColor(r));
      const opts = baseChartOptions(groups);
      opts.scales.y.title.text = yLabel;
      opts.plugins.tooltip = {
        callbacks: {
          title: (items) => {
            const r = this[dataRef][items[0].dataIndex];
            return `${prettyGenaiModel(r.model)} | ${r.device} ${shortPrecision(r.precision)}`;
          },
          label: (item) => `${parseFloat(this[dataRef][item.dataIndex][field]).toFixed(2)} ${unit}`
        }
      };
      const ctx = document.getElementById(canvasId);
      if (ctx) {
        this.charts[chartKey] = new Chart(ctx, {
          type: 'bar',
          data: { labels, datasets: [{ data: subset.map(r => r[field]), backgroundColor: bgColors, borderWidth: 0 }] },
          options: opts,
          plugins: [createGroupLabelPlugin(), createValueLabelPlugin(decimals || 2)]
        });
      }
    };

    // LLM Row 1: Latency + Throughput
    const latLLM = llm.filter(r => r.first_token_latency != null);
    const thrLLM = llm.filter(r => r.second_token_throughput != null);
    buildChart(latLLM, 'gLatChartLLM', 'latencyLLM', 'latLLMData', '1st Token Latency (ms)', 'first_token_latency', 'ms');
    buildChart(thrLLM, 'gThrChartLLM', 'throughputLLM', 'thrLLMData', 'Tokens per Second', 'second_token_throughput', 'tok/s');

    // LLM Row 2: Efficiency + Power
    const effLLM = llm.filter(r => r.efficiency != null);
    const pwrLLM = llm.filter(r => r.avg_power != null);
    buildChart(effLLM, 'gEffChartLLM', 'efficiencyLLM', 'effLLMData', 'Tokens per Watt (tpt/W)', 'efficiency', 'tpt/W');
    buildChart(pwrLLM, 'gPowerChartLLM', 'powerLLM', 'pwrLLMData', 'Package Power (W)', 'avg_power', 'W');

    // VLM Row 1: Latency + Throughput
    const latVLM = vlm.filter(r => r.first_token_latency != null);
    const thrVLM = vlm.filter(r => r.second_token_throughput != null);
    buildChart(latVLM, 'gLatChartVLM', 'latencyVLM', 'latVLMData', '1st Token Latency (ms)', 'first_token_latency', 'ms');
    buildChart(thrVLM, 'gThrChartVLM', 'throughputVLM', 'thrVLMData', 'Tokens per Second', 'second_token_throughput', 'tok/s');

    // VLM Row 2: Efficiency + Power
    const effVLM = vlm.filter(r => r.efficiency != null);
    const pwrVLM = vlm.filter(r => r.avg_power != null);
    buildChart(effVLM, 'gEffChartVLM', 'efficiencyVLM', 'effVLMData', 'Tokens per Watt (tpt/W)', 'efficiency', 'tpt/W');
    buildChart(pwrVLM, 'gPowerChartVLM', 'powerVLM', 'pwrVLMData', 'Package Power (W)', 'avg_power', 'W');

    this.renderLegends();
  }

  renderLegends() {
    const llmHtml = buildGenaiLegendHtml(this.summary.filter(r => isLLMModel(r)));
    ['gLegendThroughputLLM', 'gLegendLatencyLLM',
     'gLegendEfficiencyLLM', 'gLegendPowerLLM'
    ].forEach(id => setLegend(id, llmHtml));
    const vlmHtml = buildGenaiLegendHtml(this.summary.filter(r => !isLLMModel(r)));
    ['gLegendThroughputVLM', 'gLegendLatencyVLM',
     'gLegendEfficiencyVLM', 'gLegendPowerVLM'
    ].forEach(id => setLegend(id, vlmHtml));
  }
}


// =========================================================================
// Summary Dashboard
// =========================================================================

class SummaryDashboard {
  constructor(data, systemInfo) {
    this.data = data;
    this.systemInfo = systemInfo;
    this.charts = [];
    this.render();
  }

  destroy() {
    this.charts.forEach(c => c && c.destroy());
    this.charts = [];
  }

  render() {
    this.updateTitle();
    this.renderSystemConfig();
    if (this.data.edge_ai_pipelines && this.data.edge_ai_pipelines.summary.length)
      this.renderEdge();
    if (this.data.vision_benchmarks && this.data.vision_benchmarks.summary.length)
      this.renderVision();
    if (this.data.genai_benchmarks && this.data.genai_benchmarks.summary.length)
      this.renderGenai();
    if (this.data.media_benchmarks && this.data.media_benchmarks.summary.length)
      this.renderMedia();
  }

  updateTitle() {
    const el = document.getElementById('summaryTitle');
    if (el && this.systemInfo && this.systemInfo.system && this.systemInfo.system.name)
      el.textContent = `Performance Summary — ${this.systemInfo.system.name}`;
  }

  renderSystemConfig() {
    const si = this.systemInfo;
    if (!si) return;
    const card = document.getElementById('sSystemConfig');
    if (!card) return;
    card.style.display = 'block';
    const set = (id, val) => { const el = document.getElementById(id); if (el && val) el.textContent = val; };
    if (si.system) {
      set('cfgProcessor', si.system.name);
      set('cfgOS', si.system.os);
      set('cfgKernel', si.system.kernel);
    }
    if (si.memory) {
      set('cfgMemCapacity', si.memory.capacity);
      set('cfgMemType', si.memory.type);
      set('cfgMemSpeed', si.memory.speed);
    }
    if (si.compute) {
      set('cfgGPU', si.compute.gpu_driver);
      set('cfgNPU', si.compute.npu_driver);
      set('cfgVAAPI', si.compute.vaapi_version);
    }
    if (si.software) {
      set('cfgDLS', si.software.dlstreamer_version);
      set('cfgOV', si.software.openvino_native_version || si.software.openvino_container_version);
      set('cfgDocker', si.software.docker_version);
    }
  }

  // --- Edge AI Pipelines ---
  renderEdge() {
    document.getElementById('sSectionEdge').style.display = 'block';
    const summary = this.data.edge_ai_pipelines.summary;
    const valid = summary.filter(r => r.avg_throughput != null);
    if (!valid.length) return;

    const labels = valid.map(r => `B${r.batch}`);
    const groups = computeGroups(valid, r => r.config);
    const subGroups = computeGroups(valid, r => r.device_config || `${r.detect}-${r.classify}`);
    const bgColors = valid.map(r => edgeDeviceColor(r));

    // Stacked bars for concurrent throughput
    const isConcurrent = (r) => r.device_config && r.device_config.includes('Concurrent');
    const primaryData = [], secondaryData = [], primaryColors = [], secondaryColors = [];
    valid.forEach(r => {
      if (isConcurrent(r) && r.primary_fps != null && r.secondary_fps != null) {
        primaryData.push(r.primary_fps);
        secondaryData.push(r.secondary_fps);
        primaryColors.push(shadeColor(COLORS.GREEN, batchShade(r.batch)));
        secondaryColors.push(shadeColor(COLORS.PURPLE, batchShade(r.batch)));
      } else {
        primaryData.push(r.avg_throughput);
        secondaryData.push(0);
        primaryColors.push(edgeDeviceColor(r));
        secondaryColors.push('transparent');
      }
    });
    const hasStacked = secondaryData.some(v => v > 0);
    const thrOpts = baseChartOptions(groups);
    thrOpts.scales.y.title.text = 'FPS';
    thrOpts.layout.padding.bottom = 30;
    thrOpts.plugins.subGroupLabelPlugin = { subGroups };
    if (hasStacked) { thrOpts.scales.x.stacked = true; thrOpts.scales.y.stacked = true; }
    const thrCtx = document.getElementById('sEdgeThrChart');
    if (thrCtx) {
      const datasets = [{ data: primaryData, backgroundColor: primaryColors, borderWidth: 0, stack: 'stack0' }];
      if (hasStacked) datasets.push({ data: secondaryData, backgroundColor: secondaryColors, borderWidth: 0, stack: 'stack0' });
      this.charts.push(new Chart(thrCtx, {
        type: 'bar', data: { labels, datasets }, options: thrOpts,
        plugins: [createGroupLabelPlugin(), createSubGroupLabelPlugin(), hasStacked ? createStackedValueLabelPlugin() : createValueLabelPlugin()]
      }));
    }

    // Theoretical streams chart with stacking for concurrent pipelines
    const theoPri = [], theoSec = [], theoPriColors = [], theoSecColors = [];
    valid.forEach(r => {
      if (isConcurrent(r) && r.primary_theoretical != null && r.secondary_theoretical != null) {
        theoPri.push(r.primary_theoretical);
        theoSec.push(r.secondary_theoretical);
        theoPriColors.push(shadeColor(COLORS.GREEN, batchShade(r.batch)));
        theoSecColors.push(shadeColor(COLORS.PURPLE, batchShade(r.batch)));
      } else {
        theoPri.push(r.theoretical_streams);
        theoSec.push(0);
        theoPriColors.push(edgeDeviceColor(r));
        theoSecColors.push('transparent');
      }
    });
    const hasStackedTheo = theoSec.some(v => v > 0);
    if (theoPri.some(v => v != null)) {
      const theoOpts = baseChartOptions(groups);
      theoOpts.scales.y.title.text = 'Number of Streams';
      theoOpts.layout.padding.bottom = 30;
      theoOpts.plugins.subGroupLabelPlugin = { subGroups };
      if (hasStackedTheo) { theoOpts.scales.x.stacked = true; theoOpts.scales.y.stacked = true; }
      const theoCtx = document.getElementById('sEdgeTheoChart');
      if (theoCtx) {
        const datasets = [{ data: theoPri, backgroundColor: theoPriColors, borderWidth: 0, stack: 'stack0' }];
        if (hasStackedTheo) datasets.push({ data: theoSec, backgroundColor: theoSecColors, borderWidth: 0, stack: 'stack0' });
        this.charts.push(new Chart(theoCtx, {
          type: 'bar', data: { labels, datasets }, options: theoOpts,
          plugins: [createGroupLabelPlugin(), createSubGroupLabelPlugin(), hasStackedTheo ? createStackedValueLabelPlugin() : createValueLabelPlugin()]
        }));
      }
    }

    const effData = valid.map(r => r.efficiency && r.efficiency !== 'NA' ? parseFloat(r.efficiency) : null);
    if (effData.some(v => v != null))
      this.buildChart('sEdgeEffChart', labels, effData, bgColors, groups, 'FPS/W', subGroups);

    const pwrData = valid.map(r => r.avg_power && r.avg_power !== 'NA' ? parseFloat(r.avg_power) : null);
    if (pwrData.some(v => v != null))
      this.buildChart('sEdgePowerChart', labels, pwrData, bgColors, groups, 'Package Power (W)', subGroups);

    this.renderEdgeLegends(summary);
  }

  renderEdgeLegends(summary) {
    setLegend('sEdgeLegendThr', buildEdgeLegendHtml(summary, { stackedConcurrent: true }));
    setLegend('sEdgeLegendTheo', buildEdgeLegendHtml(summary, { stackedConcurrent: true }));
    setLegend('sEdgeLegendEff', buildEdgeLegendHtml(summary, {}));
    setLegend('sEdgeLegendPower', buildEdgeLegendHtml(summary, {}));
  }

  // --- Vision Benchmarks ---
  renderVision() {
    document.getElementById('sSectionVision').style.display = 'block';
    const summary = this.data.vision_benchmarks.summary;
    const tputData = summary.filter(r => r.mode === 'tput' && r.avg_throughput != null);
    if (!tputData.length) return;

    // Detection throughput
    const det = tputData.filter(r => isDetectionModel(r));
    if (det.length) {
      const labels = det.map(r => `B${r.batch}`);
      const groups = computeGroups(det, r => r.model);
      groups.forEach(g => { g.name = prettyModel(g.name); });
      this.buildVisionThrChart('sVisionThrDetChart', det, labels, groups, visionDeviceColor);
    }

    // Classification throughput
    const cls = tputData.filter(r => !isDetectionModel(r));
    if (cls.length) {
      const labels = cls.map(r => `B${r.batch}`);
      const groups = computeGroups(cls, r => r.model);
      groups.forEach(g => { g.name = prettyModel(g.name); });
      this.buildVisionThrChart('sVisionThrClsChart', cls, labels, groups, visionDeviceColor);
    }

    // Detection Efficiency
    const effDet = tputData.filter(r => isDetectionModel(r) && r.efficiency != null);
    if (effDet.length) {
      const labels = effDet.map(r => `B${r.batch}`);
      const groups = computeGroups(effDet, r => r.model);
      groups.forEach(g => { g.name = prettyModel(g.name); });
      const bgColors = effDet.map(r => visionDeviceColor(r.device, r.batch));
      this.buildChart('sVisionEffDetChart', labels, effDet.map(r => r.efficiency), bgColors, groups, 'FPS/W');
    }

    // Classification Efficiency
    const effCls = tputData.filter(r => !isDetectionModel(r) && r.efficiency != null);
    if (effCls.length) {
      const labels = effCls.map(r => `B${r.batch}`);
      const groups = computeGroups(effCls, r => r.model);
      groups.forEach(g => { g.name = prettyModel(g.name); });
      const bgColors = effCls.map(r => visionDeviceColor(r.device, r.batch));
      this.buildChart('sVisionEffClsChart', labels, effCls.map(r => r.efficiency), bgColors, groups, 'FPS/W');
    }

    // Detection Power
    const pwrDet = tputData.filter(r => isDetectionModel(r) && r.avg_power != null);
    if (pwrDet.length) {
      const labels = pwrDet.map(r => `B${r.batch}`);
      const groups = computeGroups(pwrDet, r => r.model);
      groups.forEach(g => { g.name = prettyModel(g.name); });
      const bgColors = pwrDet.map(r => visionDeviceColor(r.device, r.batch));
      this.buildChart('sVisionPowerDetChart', labels, pwrDet.map(r => r.avg_power), bgColors, groups, 'Package Power (W)');
    }

    // Classification Power
    const pwrCls = tputData.filter(r => !isDetectionModel(r) && r.avg_power != null);
    if (pwrCls.length) {
      const labels = pwrCls.map(r => `B${r.batch}`);
      const groups = computeGroups(pwrCls, r => r.model);
      groups.forEach(g => { g.name = prettyModel(g.name); });
      const bgColors = pwrCls.map(r => visionDeviceColor(r.device, r.batch));
      this.buildChart('sVisionPowerClsChart', labels, pwrCls.map(r => r.avg_power), bgColors, groups, 'Package Power (W)');
    }

    this.renderVisionLegends(summary);
  }

  buildVisionThrChart(canvasId, subset, labels, groups, deviceColor) {
    const primaryData = [], secondaryData = [], primaryColors = [], secondaryColors = [];
    subset.forEach(r => {
      const isConcurrent = r.concurrent && r.concurrent !== 'None';
      if (isConcurrent && r.primary_fps != null && r.secondary_fps != null) {
        primaryData.push(r.primary_fps); secondaryData.push(r.secondary_fps);
        primaryColors.push(shadeColor(COLORS.GREEN, batchShade(r.batch)));
        secondaryColors.push(shadeColor(COLORS.PURPLE, batchShade(r.batch)));
      } else {
        primaryData.push(r.avg_throughput); secondaryData.push(0);
        primaryColors.push(deviceColor(r.device, r.batch));
        secondaryColors.push('transparent');
      }
    });
    const hasStacked = secondaryData.some(v => v > 0);
    const opts = baseChartOptions(groups);
    opts.scales.y.title.text = 'FPS';
    if (hasStacked) { opts.scales.x.stacked = true; opts.scales.y.stacked = true; }
    const ctx = document.getElementById(canvasId);
    if (!ctx) return;
    const datasets = [{ data: primaryData, backgroundColor: primaryColors, borderWidth: 0, stack: 'stack0' }];
    if (hasStacked) datasets.push({ data: secondaryData, backgroundColor: secondaryColors, borderWidth: 0, stack: 'stack0' });
    this.charts.push(new Chart(ctx, {
      type: 'bar', data: { labels, datasets }, options: opts,
      plugins: [createGroupLabelPlugin(), hasStacked ? createStackedValueLabelPlugin() : createValueLabelPlugin()]
    }));
  }

  renderVisionLegends(summary) {
    const thrHtml = buildVisionLegendHtml(summary, { compact: true, stackedConcurrent: true });
    const otherHtml = buildVisionLegendHtml(summary, { compact: true });
    ['sVisionLegendThrDet', 'sVisionLegendThrCls'].forEach(id => setLegend(id, thrHtml));
    ['sVisionLegendEffDet', 'sVisionLegendEffCls', 'sVisionLegendPowerDet', 'sVisionLegendPowerCls'].forEach(id => setLegend(id, otherHtml));
  }

  // --- Media Benchmarks ---
  renderMedia() {
    document.getElementById('sSectionMedia').style.display = 'block';
    const summary = this.data.media_benchmarks.summary;
    const valid = summary.filter(r => r.avg_throughput != null);
    if (!valid.length) return;

    const resLabel = (r) => r.resolution === '4k' ? '4K @30fps' : `${r.resolution} @30fps`;
    const labels = valid.map(r => r.media);
    const groups = computeGroups(valid, r => `${r.codec.toUpperCase()} ${resLabel(r)}`);
    const bgColors = valid.map(r => mediaRecordColor(r));

    this.buildChart('sMediaThrChart', labels, valid.map(r => r.avg_throughput), bgColors, groups, 'FPS');

    const theoData = valid.map(r => r.theoretical_streams);
    if (theoData.some(v => v != null))
      this.buildChart('sMediaTheoChart', labels, theoData, bgColors, groups, 'Number of Streams');

    const effData = valid.map(r => r.efficiency != null ? parseFloat(r.efficiency) : null);
    if (effData.some(v => v != null))
      this.buildChart('sMediaEffChart', labels, effData, bgColors, groups, 'FPS/W');

    const pwrData = valid.map(r => r.avg_power != null ? parseFloat(r.avg_power) : null);
    if (pwrData.some(v => v != null))
      this.buildChart('sMediaPowerChart', labels, pwrData, bgColors, groups, 'Package Power (W)');

    this.renderMediaLegends(summary);
  }

  renderMediaLegends(summary) {
    const html = buildMediaLegendHtml(summary);
    ['sMediaLegendThr', 'sMediaLegendTheo', 'sMediaLegendEff', 'sMediaLegendPower'].forEach(id => setLegend(id, html));
  }

  // --- GenAI Benchmarks ---
  renderGenai() {
    document.getElementById('sSectionGenai').style.display = 'block';
    const summary = this.data.genai_benchmarks.summary;
    const llm = summary.filter(r => isLLMModel(r));
    const vlm = summary.filter(r => !isLLMModel(r));

    const buildGenaiChart = (subset, canvasId, yLabel, field) => {
      if (!subset.length) return;
      const labels = subset.map(r => shortPrecision(r.precision));
      const groups = computeGroups(subset, r => r.model);
      groups.forEach(g => { g.name = prettyGenaiModel(g.name); });
      const bgColors = subset.map(r => genaiDeviceColor(r));
      this.buildChart(canvasId, labels, subset.map(r => r[field]), bgColors, groups, yLabel);
    };

    // Row 1: LLM latency + throughput
    const latLLM = llm.filter(r => r.first_token_latency != null);
    buildGenaiChart(latLLM, 'sGenaiLatLLMChart', 'ms', 'first_token_latency');
    const thrLLM = llm.filter(r => r.second_token_throughput != null);
    buildGenaiChart(thrLLM, 'sGenaiThrLLMChart', 'tok/s', 'second_token_throughput');

    // Row 2: LLM efficiency + power
    const effLLM = llm.filter(r => r.efficiency != null);
    buildGenaiChart(effLLM, 'sGenaiEffLLMChart', 'tpt/W', 'efficiency');
    const pwrLLM = llm.filter(r => r.avg_power != null);
    buildGenaiChart(pwrLLM, 'sGenaiPwrLLMChart', 'W', 'avg_power');

    // Row 3: VLM latency + throughput
    const latVLM = vlm.filter(r => r.first_token_latency != null);
    buildGenaiChart(latVLM, 'sGenaiLatVLMChart', 'ms', 'first_token_latency');
    const thrVLM = vlm.filter(r => r.second_token_throughput != null);
    buildGenaiChart(thrVLM, 'sGenaiThrVLMChart', 'tok/s', 'second_token_throughput');

    // Row 4: VLM efficiency + power
    const effVLM = vlm.filter(r => r.efficiency != null);
    buildGenaiChart(effVLM, 'sGenaiEffVLMChart', 'tpt/W', 'efficiency');
    const pwrVLM = vlm.filter(r => r.avg_power != null);
    buildGenaiChart(pwrVLM, 'sGenaiPwrVLMChart', 'W', 'avg_power');

    this.renderGenaiLegends(summary);
  }

  renderGenaiLegends(summary) {
    const llmHtml = buildGenaiLegendHtml(summary.filter(r => isLLMModel(r)));
    ['sGenaiLegendLatLLM', 'sGenaiLegendThrLLM', 'sGenaiLegendEffLLM', 'sGenaiLegendPwrLLM'
    ].forEach(id => setLegend(id, llmHtml));
    const vlmHtml = buildGenaiLegendHtml(summary.filter(r => !isLLMModel(r)));
    ['sGenaiLegendLatVLM', 'sGenaiLegendThrVLM', 'sGenaiLegendEffVLM', 'sGenaiLegendPwrVLM'
    ].forEach(id => setLegend(id, vlmHtml));
  }

  // --- Shared chart builder ---
  buildChart(canvasId, labels, data, bgColors, groups, yLabel, subGroups) {
    const ctx = document.getElementById(canvasId);
    if (!ctx) return;
    const opts = baseChartOptions(groups);
    opts.scales.y.title.text = yLabel;
    const plugins = [createGroupLabelPlugin(), createValueLabelPlugin()];
    if (subGroups) {
      opts.layout.padding.bottom = 30;
      opts.plugins.subGroupLabelPlugin = { subGroups };
      plugins.splice(1, 0, createSubGroupLabelPlugin());
    }
    this.charts.push(new Chart(ctx, {
      type: 'bar',
      data: { labels, datasets: [{ data, backgroundColor: bgColors, borderWidth: 0 }] },
      options: opts,
      plugins
    }));
  }
}


// =========================================================================
// Workload Manager (sidebar + data loading)
// =========================================================================

class WorkloadManager {
  constructor() {
    this.edgeDashboard = null;
    this.visionDashboard = null;
    this.mediaDashboard = null;
    this.genaiDashboard = null;
    this.summaryDashboard = null;
    this.systemInfo = null;
    this.data = null;
    this.init();
  }

  async init() {
    try {
      await this.loadData();
      await this.loadSystemInfo();
      this.updateSidebarState();
      this.setupSidebar();
      this.instantiateDashboards();
      this.showDefaultWorkload();
      initChartExportButtons();
    } catch (error) {
      this.showError('Failed to initialize dashboard: ' + error.message);
    }
  }

  async loadData() {
    try {
      const response = await fetch('data.json');
      if (!response.ok) throw new Error('not found');
      this.data = await response.json();
    } catch (_) {
      this.data = {
        edge_ai_pipelines: { summary: [], raw: [] },
        vision_benchmarks: { summary: [], raw: [] },
        media_benchmarks: { summary: [], raw: [] },
        genai_benchmarks: { summary: [], raw: [] }
      };
    }

    // Handle legacy data.json format
    if (this.data.summary && !this.data.edge_ai_pipelines) {
      this.data = {
        edge_ai_pipelines: { summary: this.data.summary, raw: this.data.raw || [] },
        vision_benchmarks: { summary: [], raw: [] }
      };
    }
  }

  async loadSystemInfo() {
    try {
      const response = await fetch('system_info.json');
      if (response.ok) this.systemInfo = await response.json();
    } catch (_) { /* optional */ }
  }

  get hasEdge() {
    return this.data && this.data.edge_ai_pipelines && this.data.edge_ai_pipelines.summary.length > 0;
  }

  get hasVision() {
    return this.data && this.data.vision_benchmarks && this.data.vision_benchmarks.summary.length > 0;
  }

  get hasMedia() {
    return this.data && this.data.media_benchmarks && this.data.media_benchmarks.summary.length > 0;
  }

  get hasGenai() {
    return this.data && this.data.genai_benchmarks && this.data.genai_benchmarks.summary.length > 0;
  }

  updateSidebarState() {
    const navSummary = document.getElementById('navSummary');
    const navEdge = document.getElementById('navEdge');
    const navVision = document.getElementById('navVision');
    const navMedia = document.getElementById('navMedia');
    if (navSummary && !this.hasEdge && !this.hasVision && !this.hasMedia && !this.hasGenai && !this.systemInfo) {
      navSummary.classList.add('disabled');
      navSummary.title = 'No benchmark results or system info found';
    }
    if (navEdge && !this.hasEdge) {
      navEdge.classList.add('disabled');
      navEdge.title = 'No edge-ai-pipelines results found';
    }
    if (navVision && !this.hasVision) {
      navVision.classList.add('disabled');
      navVision.title = 'No vision-benchmarks results found';
    }
    if (navMedia && !this.hasMedia) {
      navMedia.classList.add('disabled');
      navMedia.title = 'No media-benchmarks results found';
    }
    const navGenai = document.getElementById('navGenai');
    if (navGenai && !this.hasGenai) {
      navGenai.classList.add('disabled');
      navGenai.title = 'No genai-benchmarks results found';
    }
    // System name in sidebar
    const sysEl = document.getElementById('sidebarSystemName');
    if (sysEl && this.systemInfo && this.systemInfo.system)
      sysEl.textContent = this.systemInfo.system.name || '';
  }

  setupSidebar() {
    const navItems = document.querySelectorAll('.sidebar-item');
    navItems.forEach(btn => {
      btn.addEventListener('click', () => {
        if (btn.classList.contains('disabled')) return;
        navItems.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        const workload = btn.dataset.workload;
        document.querySelectorAll('.workload-section').forEach(s => s.classList.remove('active'));
        const sectionMap = {
          'summary': 'summarySection',
          'edge-ai-pipelines': 'edgePipelinesSection',
          'vision-benchmarks': 'visionBenchmarksSection',
          'media-benchmarks': 'mediaBenchmarksSection',
          'genai-benchmarks': 'genaiBenchmarksSection'
        };
        const sectionId = sectionMap[workload];
        if (sectionId) document.getElementById(sectionId).classList.add('active');
      });
    });

    // Collapse toggle
    const toggle = document.getElementById('sidebarToggle');
    const sidebar = document.getElementById('sidebar');
    if (toggle && sidebar) {
      toggle.addEventListener('click', () => sidebar.classList.toggle('collapsed'));
    }
  }

  instantiateDashboards() {
    if (this.hasEdge) {
      const d = this.data.edge_ai_pipelines;
      this.edgeDashboard = new PipelineDashboard(d.summary, d.raw, this.systemInfo);
    }
    if (this.hasVision) {
      const d = this.data.vision_benchmarks;
      this.visionDashboard = new VisionDashboard(d.summary, d.raw, this.systemInfo);
    }
    if (this.hasMedia) {
      const d = this.data.media_benchmarks;
      this.mediaDashboard = new MediaDashboard(d.summary, d.raw, this.systemInfo);
    }
    if (this.hasGenai) {
      const d = this.data.genai_benchmarks;
      this.genaiDashboard = new GenaiDashboard(d.summary, d.raw, this.systemInfo);
    }
    if (this.hasEdge || this.hasVision || this.hasMedia || this.hasGenai || this.systemInfo) {
      this.summaryDashboard = new SummaryDashboard(this.data, this.systemInfo);
    }
  }

  showDefaultWorkload() {
    const navSummary = document.getElementById('navSummary');
    if (navSummary && !navSummary.classList.contains('disabled')) {
      navSummary.click();
    } else if (this.hasEdge) {
      document.getElementById('navEdge').click();
    } else if (this.hasVision) {
      document.getElementById('navVision').click();
    } else if (this.hasMedia) {
      document.getElementById('navMedia').click();
    } else if (this.hasGenai) {
      document.getElementById('navGenai').click();
    }
  }

  showError(message) {
    const main = document.querySelector('.main-content');
    if (!main) return;
    const div = document.createElement('div');
    div.className = 'error-message';
    const strong = document.createElement('strong');
    strong.textContent = 'Error: ';
    div.appendChild(strong);
    div.appendChild(document.createTextNode(message));
    main.insertBefore(div, main.firstChild);
  }
}

// Attach chart-export buttons to all chart items
function initChartExportButtons() {
  const svgIcon = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M8 12l-4-4h2.5V2h3v6H12L8 12z"/><path d="M14 14H2v-2h12v2z"/></svg>';

  const slugify = (s) => s.trim().replace(/[^a-zA-Z0-9]+/g, '-').replace(/-+$/, '').toLowerCase();

  const getWorkloadName = (item) => {
    // Summary view: look for nearest .summary-workload-group > h2
    const summaryGroup = item.closest('.summary-workload-group');
    if (summaryGroup) {
      const h = summaryGroup.querySelector('.summary-section-header');
      if (h) return slugify(h.textContent);
    }
    // Individual workload sections: find section h1
    const section = item.closest('.workload-section');
    if (section) {
      const h = section.querySelector('h1');
      if (h) return slugify(h.textContent.replace(/dashboard.*/i, '').replace(/—.*/i, ''));
    }
    return 'chart';
  };

  const exportChart = (item, canvas) => {
    const titleEl = item.querySelector('.chart-title');
    const legendEl = item.querySelector('.legend');
    const footerEl = item.querySelector('.chart-footer');
    const chartTitle = titleEl ? titleEl.textContent.trim() : '';
    const footerText = footerEl ? footerEl.textContent.trim() : '';

    // Gather legend items
    const legendItems = [];
    if (legendEl) {
      legendEl.querySelectorAll('.legend-item').forEach(li => {
        const swatch = li.querySelector('.legend-color');
        const color = swatch ? getComputedStyle(swatch).backgroundColor : '#888';
        legendItems.push({ color, text: li.textContent.trim() });
      });
    }

    const pad = 24;
    const titleH = chartTitle ? 28 : 0;
    const legendH = legendItems.length ? 22 : 0;
    const footerH = footerText ? 18 : 0;
    const gap = 12;
    const chartW = canvas.width;
    const chartH = canvas.height;
    const totalW = chartW + pad * 2;
    const totalH = pad + titleH + (titleH ? gap : 0) + legendH + (legendH ? gap : 0) + chartH + (footerText ? gap : 0) + footerH + pad;

    const offscreen = document.createElement('canvas');
    offscreen.width = totalW;
    offscreen.height = totalH;
    const ctx = offscreen.getContext('2d');

    // Background
    const isLight = document.documentElement.getAttribute('data-theme') === 'light';
    ctx.fillStyle = isLight ? '#ffffff' : '#1a1d23';
    ctx.fillRect(0, 0, totalW, totalH);

    let y = pad;

    // Title
    if (chartTitle) {
      ctx.fillStyle = isLight ? '#1b1b1b' : '#ffffff';
      ctx.font = 'bold 16px Inter, system-ui, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(chartTitle, totalW / 2, y + 16);
      y += titleH + gap;
    }

    // Legend
    if (legendItems.length) {
      ctx.font = '11px Inter, system-ui, sans-serif';
      ctx.textAlign = 'left';
      const swatchSize = 10;
      const itemGap = 16;
      // Measure total width to center
      let totalLegendW = 0;
      legendItems.forEach(li => { totalLegendW += swatchSize + 4 + ctx.measureText(li.text).width + itemGap; });
      totalLegendW -= itemGap;
      let lx = Math.max(pad, (totalW - totalLegendW) / 2);
      legendItems.forEach(li => {
        ctx.fillStyle = li.color;
        ctx.fillRect(lx, y + 4, swatchSize, swatchSize);
        ctx.fillStyle = isLight ? '#6e7781' : '#cccccc';
        ctx.fillText(li.text, lx + swatchSize + 4, y + 13);
        lx += swatchSize + 4 + ctx.measureText(li.text).width + itemGap;
      });
      y += legendH + gap;
    }

    // Chart image
    ctx.drawImage(canvas, pad, y);
    y += chartH;

    // Footer
    if (footerText) {
      y += gap;
      ctx.fillStyle = isLight ? '#6e7781' : '#888888';
      ctx.font = 'italic 10px Inter, system-ui, sans-serif';
      ctx.textAlign = 'right';
      ctx.fillText(footerText, totalW - pad, y + 10);
    }

    // Build filename: {workload-name}_{chart-name}_{timestamp}.png
    const workload = getWorkloadName(item);
    const chart = titleEl ? slugify(titleEl.textContent) : 'chart';
    const ts = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 15);
    const filename = `${workload}_${chart}_${ts}.png`;

    const a = document.createElement('a');
    a.href = offscreen.toDataURL('image/png');
    a.download = filename;
    a.click();
  };

  // Remove any existing export buttons before re-adding
  document.querySelectorAll('.chart-export-btn').forEach(b => b.remove());

  document.querySelectorAll('.chart-item').forEach(item => {
    const canvas = item.querySelector('canvas');
    if (!canvas) return;
    const btn = document.createElement('button');
    btn.className = 'chart-export-btn';
    btn.title = 'Download chart as PNG';
    btn.innerHTML = svgIcon;
    btn.addEventListener('click', () => exportChart(item, canvas));
    item.appendChild(btn);
  });
}

// Initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
  // Apply saved theme before anything renders
  const saved = localStorage.getItem('dashboard-theme');
  if (saved === 'light') document.documentElement.setAttribute('data-theme', 'light');
  syncColors();

  const manager = new WorkloadManager();

  // Theme toggle
  const themeBtn = document.getElementById('themeToggle');
  if (themeBtn) {
    const sunIcon  = document.getElementById('themeIconSun');
    const moonIcon = document.getElementById('themeIconMoon');
    const label    = document.getElementById('themeLabel');

    function updateIcons() {
      const isLight = document.documentElement.getAttribute('data-theme') === 'light';
      if (sunIcon)  sunIcon.style.display  = isLight ? 'none' : 'block';
      if (moonIcon) moonIcon.style.display = isLight ? 'block' : 'none';
      if (label) label.textContent = isLight ? 'Dark mode' : 'Light mode';
    }

    updateIcons();

    themeBtn.addEventListener('click', () => {
      const isCurrentlyLight = document.documentElement.getAttribute('data-theme') === 'light';
      if (isCurrentlyLight) {
        document.documentElement.removeAttribute('data-theme');
        localStorage.setItem('dashboard-theme', 'dark');
      } else {
        document.documentElement.setAttribute('data-theme', 'light');
        localStorage.setItem('dashboard-theme', 'light');
      }
      updateIcons();
      syncColors();

      // Destroy existing Chart.js instances and rebuild
      Object.values(Chart.instances).forEach(c => c.destroy());
      manager.instantiateDashboards();
      initChartExportButtons();
    });
  }
});
