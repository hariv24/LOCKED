// Locked: YouTube cleanup content script (runs at document_start on *.youtube.com).
//
// During an active session (and unless YouTube as a whole is allowlisted) it hides
// recommendations, comments, end-screen cards, the home feed, Shorts, the left guide and the
// autoplay toggle, and switches autoplay off. Disallowed videos are blocked by the background
// worker; this only removes distractions around the allowed ones.
(() => {
  'use strict';

  const STYLE_ID = 'locked-youtube-clean';
  const CSS = `
/* Recommendations / sidebar */
#related, #secondary, #secondary-inner, ytd-watch-next-secondary-results-renderer,
ytm-item-section-renderer[section-identifier="related-items"],
/* Comments and live chat */
#comments, ytd-comments, ytm-comment-section-renderer, ytm-comments-entry-point-header-renderer,
ytd-live-chat-frame, #chat,
/* End screen, up-next, pause overlay */
.ytp-ce-element, .ytp-ce-covering-overlay, .ytp-endscreen-content, .html5-endscreen,
.videowall-endscreen, .ytp-videowall-still, .ytp-autonav-endscreen, .ytp-upnext,
.ytp-autonav-endscreen-countdown-overlay, .ytp-suggestion-set, .ytp-pause-overlay,
.ytp-pause-overlay-container, .ytp-endscreen-previous, .ytp-endscreen-next, .ytp-next-button,
/* Autoplay toggles */
.ytp-autonav-toggle-button-container, .ytp-autonav-toggle,
button[data-tooltip-target-id="ytp-autonav-toggle-button"], ytm-autonav-toggle-button-container,
.ytm-autonav-toggle-button-container,
/* Home feed */
ytd-browse[page-subtype="home"], ytd-browse[page-subtype="home"] ytd-rich-grid-renderer,
ytm-browse ytm-rich-grid-renderer, #feed, ytd-two-column-browse-results-renderer[page-subtype="home"],
/* Shorts shelves and entry points */
ytd-reel-shelf-renderer, ytd-rich-shelf-renderer[is-shorts], ytd-rich-section-renderer:has(ytd-rich-shelf-renderer[is-shorts]),
ytm-reel-shelf-renderer, ytm-shorts-lockup-view-model, ytd-guide-entry-renderer:has(a[title="Shorts"]),
ytd-mini-guide-entry-renderer[aria-label="Shorts"], grid-shelf-view-model,
/* Left navigation guide */
#guide, tp-yt-app-drawer#guide, ytd-guide-renderer, ytd-mini-guide-renderer, #guide-button,
#guide-content, ytm-pivot-bar-renderer,
/* Merch, chips and other feed bait on watch pages */
ytd-merch-shelf-renderer, ytd-feed-filter-chip-bar-renderer, #chips-wrapper {
  display: none !important;
}
ytd-app[guide-persistent-and-visible] ytd-page-manager,
ytd-app ytd-page-manager { margin-left: 0 !important; }
ytd-watch-flexy[flexy] #primary.ytd-watch-flexy { max-width: none !important; }
`;

  let clean = true; // optimistic until the background answers, to avoid a flash of recommendations
  let timers = [];

  function setStyle(on) {
    const existing = document.getElementById(STYLE_ID);
    if (on && !existing) {
      const style = document.createElement('style');
      style.id = STYLE_ID;
      style.textContent = CSS;
      (document.head || document.documentElement).appendChild(style);
    } else if (!on && existing) {
      existing.remove();
    }
  }

  function setClean(value) {
    clean = !!value;
    setStyle(clean);
    if (clean) scheduleAutoplayOff();
  }

  // Autoplay: click the player's toggle if it's on (the toggle is hidden but still clickable).
  function disableAutoplay() {
    if (!clean) return;
    const desktop = document.querySelector('.ytp-autonav-toggle-button[aria-checked="true"]');
    if (desktop) {
      const button = desktop.closest('button') || desktop;
      button.click();
    }
    const mobile = document.querySelector('.ytm-autonav-toggle-button-container[aria-pressed="true"]');
    if (mobile) mobile.click();
  }

  function cancelUpNext() {
    if (!clean) return;
    const cancel = document.querySelector('.ytp-autonav-endscreen-upnext-cancel-button');
    if (cancel) cancel.click();
  }

  function scheduleAutoplayOff() {
    for (const t of timers) clearTimeout(t);
    timers = [250, 1000, 2500, 5000].map((ms) => setTimeout(disableAutoplay, ms));
  }

  function refresh() {
    try {
      chrome.runtime.sendMessage({ type: 'getYouTubeMode', url: location.href }, (resp) => {
        if (chrome.runtime.lastError || !resp) {
          setClean(false);
          return;
        }
        setClean(resp.clean);
      });
    } catch {
      // Extension context invalidated (extension reloaded/removed): leave YouTube untouched.
      setClean(false);
    }
  }

  setStyle(true);
  refresh();

  // YouTube is a single-page app: re-check after every in-app navigation.
  document.addEventListener('yt-navigate-finish', refresh);
  document.addEventListener('yt-page-data-updated', disableAutoplay);
  document.addEventListener('yt-player-updated', disableAutoplay);
  // Media events don't bubble, but they can be caught in the capture phase.
  document.addEventListener('play', disableAutoplay, true);
  document.addEventListener('ended', () => {
    cancelUpNext();
    setTimeout(cancelUpNext, 300);
  }, true);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') refresh();
  });

  chrome.runtime.onMessage.addListener((msg) => {
    if (msg && msg.type === 'youtubeMode') setClean(msg.clean);
  });
})();
