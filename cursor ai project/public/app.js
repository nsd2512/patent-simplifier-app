const $ = (id) => document.getElementById(id);

let lastDraftHtml = "";
let lastMermaidSource = "";

function splitLinesForUi(value) {
  return (value || "").toString();
}

function setStatus(msg) {
  const el = $("status");
  if (!el) return;
  el.textContent = msg || "";
}

function renderList(ulEl, items) {
  if (!ulEl) return;
  ulEl.innerHTML = "";
  (items || []).forEach((x) => {
    const li = document.createElement("li");
    li.textContent = x;
    ulEl.appendChild(li);
  });
}

function getPayloadFromForm() {
  return {
    applicationType: $("applicationType").value,
    title: $("title").value,
    summary: $("summary").value,
    howItWorks: $("howItWorks").value,
    keyComponents: $("keyComponents").value,
    processSteps: $("processSteps").value,
    useCases: $("useCases").value,
    externalSources: $("externalSources").value
  };
}

async function generateDraft() {
  setStatus("Generating...");
  const btn = $("generateBtn");
  if (btn) btn.disabled = true;

  try {
    const payload = getPayloadFromForm();
    const res = await fetch("/api/generate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });

    const data = await res.json();
    if (!res.ok) {
      throw new Error(data?.error || `Request failed with ${res.status}`);
    }

    const assessment = data.assessment || {};
    const draft = data.draft || {};
    const search = data.search || {};

    $("results").style.display = "block";

    $("scoreBadge").textContent = `Score: ${assessment.score ?? "-"}`;
    $("gradeText").textContent = `Grade: ${assessment.grade ?? "-"}`;

    renderList($("feedbackList"), assessment.feedback);
    renderList($("checklist"), assessment.checklist);

    lastDraftHtml = draft.draftHtml || "";
    const frame = $("draftFrame");
    if (frame) frame.srcdoc = lastDraftHtml;

    lastMermaidSource = draft.mermaid || "";
    $("mermaidSource").textContent = lastMermaidSource;

    const risk = search.noveltyRisk;
    $("riskBadge").textContent = `Novelty risk: ${risk === null || risk === undefined ? "-" : risk}`;

    const configured = search.configured;
    const searchCfg = $("searchConfigured");
    if (searchCfg) {
      if (configured) searchCfg.textContent = "Search: enabled";
      else searchCfg.textContent = search.message || "Search: not configured";
    }

    const sr = $("searchResults");
    if (sr) {
      sr.innerHTML = "";
      const results = search.results || [];
      if (!results.length) {
        sr.innerHTML = "<div class='muted'>No search results yet (or search is not configured).</div>";
      } else {
        results.forEach((r) => {
          const card = document.createElement("div");
          card.className = "resultCard";
          const a = document.createElement("a");
          a.href = r.link;
          a.target = "_blank";
          a.rel = "noreferrer";
          a.textContent = r.title || r.link;

          const q = document.createElement("div");
          q.className = "muted";
          q.textContent = `Query: ${r.query}`;

          const snip = document.createElement("div");
          snip.textContent = r.snippet || "";

          card.appendChild(a);
          card.appendChild(q);
          card.appendChild(snip);
          sr.appendChild(card);
        });
      }
    }

    setStatus("Done.");
  } catch (err) {
    console.error(err);
    setStatus(`Error: ${err.message || String(err)}`);
  } finally {
    if (btn) btn.disabled = false;
  }
}

async function tryRenderMermaid() {
  const src = (lastMermaidSource || "").toString().trim();
  const output = $("mermaidOutput");
  if (!output) return;
  output.innerHTML = "";

  if (!window.mermaid) {
    output.innerHTML = "<div class='muted'>Mermaid library not loaded. View the Mermaid source instead.</div>";
    return;
  }
  if (!src) {
    output.innerHTML = "<div class='muted'>No Mermaid source to render.</div>";
    return;
  }

  try {
    const id = "mermaidGraph";
    window.mermaid.initialize({ startOnLoad: false });
    const render = window.mermaid.render(id, src);

    if (render && typeof render.then === "function") {
      const resolved = await render;
      if (resolved && resolved.svg) output.innerHTML = resolved.svg;
      else output.textContent = src;
      return;
    }

    // Some mermaid versions may return the object directly.
    if (render && render.svg) output.innerHTML = render.svg;
    else output.textContent = src;
  } catch (e) {
    console.error(e);
    output.innerHTML = `<div class='muted'>Failed to render Mermaid. Mermaid source is shown above.</div>`;
  }
}

function printDraft() {
  if (!lastDraftHtml) return;
  const win = window.open("", "_blank", "noopener,noreferrer");
  if (!win) return;
  win.document.open();
  win.document.write(lastDraftHtml);
  win.document.close();
  win.focus();
  win.print();
}

function downloadHtml() {
  if (!lastDraftHtml) return;
  const blob = new Blob([lastDraftHtml], { type: "text/html;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "patent-draft.html";
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

document.addEventListener("DOMContentLoaded", () => {
  const genBtn = $("generateBtn");
  if (genBtn) genBtn.addEventListener("click", generateDraft);

  const renderBtn = $("renderMermaidBtn");
  if (renderBtn) renderBtn.addEventListener("click", () => tryRenderMermaid());

  const printBtn = $("printDraftBtn");
  if (printBtn) printBtn.addEventListener("click", printDraft);

  const dlBtn = $("downloadHtmlBtn");
  if (dlBtn) dlBtn.addEventListener("click", downloadHtml);
});

