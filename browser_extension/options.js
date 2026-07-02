async function load() {
  const cfg = await chrome.storage.sync.get(["base_url", "api_token"]);
  document.getElementById("base_url").value  = cfg.base_url  || "https://os.miolim.de";
  document.getElementById("api_token").value = cfg.api_token || "";
}

async function save() {
  const base_url  = document.getElementById("base_url").value.trim();
  const api_token = document.getElementById("api_token").value.trim();
  await chrome.storage.sync.set({ base_url, api_token });
  const s = document.getElementById("status");
  s.textContent = "✓ Gespeichert";
  setTimeout(() => s.textContent = "", 1500);
}

document.addEventListener("DOMContentLoaded", load);
document.getElementById("save").addEventListener("click", save);
