// Service-Worker. Aktuell minimal — beim ersten Install Options-Seite
// öffnen, damit User Base-URL + Token einrichtet.
chrome.runtime.onInstalled.addListener((details) => {
  if (details.reason === "install") {
    chrome.runtime.openOptionsPage();
  }
});
