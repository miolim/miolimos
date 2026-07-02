// Popup-Logik: aktuellen Tab auslesen, Felder vorausfüllen, beim Save
// POST an /api/v1/inbox_items.

const $ = (id) => document.getElementById(id);
const setStatus = (msg, kind) => {
  const el = $("status");
  el.textContent = msg || "";
  el.className   = kind || "";
};

async function init() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab) {
    $("title").value = tab.title || "";
    $("url").value   = tab.url   || "";
  }
  // Bei Klick außerhalb auf "Einstellungen" → options.html öffnen.
  $("open-options").addEventListener("click", (e) => {
    e.preventDefault();
    chrome.runtime.openOptionsPage();
  });
  $("cancel").addEventListener("click", () => window.close());
  $("save").addEventListener("click", save);
}

async function save() {
  const cfg = await chrome.storage.sync.get(["base_url", "api_token"]);
  if (!cfg.base_url || !cfg.api_token) {
    setStatus("Bitte erst Einstellungen ausfüllen (Base-URL + API-Token).", "error");
    return;
  }
  const body = {
    source_url:  $("url").value,
    title:       $("title").value,
    raw_content: $("note").value || null,
    auto:        $("auto").checked
  };

  $("save").disabled = true;
  setStatus("Sende …");
  try {
    const res = await fetch(`${cfg.base_url.replace(/\/$/, "")}/api/v1/inbox_items`, {
      method:  "POST",
      headers: {
        "Content-Type":  "application/json",
        "Authorization": `Bearer ${cfg.api_token}`,
        "Accept":        "application/json"
      },
      body: JSON.stringify(body)
    });
    if (!res.ok) {
      const txt = await res.text();
      setStatus(`HTTP ${res.status}: ${txt.slice(0, 200)}`, "error");
      $("save").disabled = false;
      return;
    }
    const data = await res.json();
    const status = data?.data?.status || "pending";
    setStatus(`✓ Gespeichert (${status}). Tab schließt sich gleich …`, "ok");
    setTimeout(() => window.close(), 700);
  } catch (e) {
    setStatus(`Fehler: ${e.message}`, "error");
    $("save").disabled = false;
  }
}

document.addEventListener("DOMContentLoaded", init);
