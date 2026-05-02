// ==UserScript==
// @name        build-pr launcher
// @namespace   build-pr-gha
// @match       https://github.com/*/*/pull/*
// @match       https://github.com/lonerOrz/nixpkgs-review-gha/actions/workflows/build-pr.yml*
// @run-at      document-idle
// ==/UserScript==

(() => {
  "use strict";

  const GHA_REPO = "lonerOrz/nixpkgs-review-gha";
  const WORKFLOW = "build-pr.yml";
  const DARWIN_SANDBOX = "relaxed";

  const sleep = ms => new Promise(r => setTimeout(r, ms));

  const query = async (root, sel) => {
    while (true) {
      const el = root.querySelector(sel);
      if (el) return el;
      await sleep(100);
    }
  };

  /* ---------- PR PAGE ---------- */

  const prMatch = /^https:\/\/github.com\/([^/]+\/[^/]+)\/pull\/(\d+)/.exec(location.href);

  if (prMatch) {
    const [, repo, prNumber] = prMatch;

    const getPrDetails = () => {
      const labels = [...document.querySelectorAll("div.js-issue-labels a")].map(x => x.innerText.trim());

      const hasLinuxRebuilds = !labels.some(l => /rebuild-linux:\s*0$/i.test(l));
      const hasDarwinRebuilds = !labels.some(l => /rebuild-darwin:\s*0$/i.test(l));
      const hasRebuilds = hasLinuxRebuilds || hasDarwinRebuilds;

      return {
        "x86_64-linux": !hasRebuilds || hasLinuxRebuilds,
        "aarch64-linux": !hasRebuilds || hasLinuxRebuilds,
        "x86_64-darwin": !hasRebuilds || hasDarwinRebuilds ? `yes_sandbox_${DARWIN_SANDBOX}` : "no",
        "aarch64-darwin": !hasRebuilds || hasDarwinRebuilds ? `yes_sandbox_${DARWIN_SANDBOX}` : "no",
      };
    };

    const injectButton = async () => {
      const actions = await query(document, "div[data-component=PH_Actions], .gh-header-show .gh-header-actions");
      if (actions.querySelector(".run-build-pr")) return;

      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "Button Button--secondary Button--small run-build-pr";
      btn.innerText = "Run build-pr";

      btn.onclick = () => {
        const params = new URLSearchParams({
          repo,
          "pr-number": prNumber,
          ...getPrDetails(),
        });

        const url =
          `https://github.com/${GHA_REPO}` + `/actions/workflows/${WORKFLOW}` + `#dispatch:${params.toString()}`;

        window.open(url, "_blank");
      };

      actions.prepend(btn);
    };

    new MutationObserver(injectButton).observe(document, {
      childList: true,
      subtree: true,
    });

    injectButton();
  }

  /* ---------- ACTIONS PAGE ---------- */

  const actionsMatch = /^https:\/\/github.com\/([^/]+\/[^/]+)\/actions\/workflows\/build-pr.yml#dispatch:(.*)$/.exec(
    location.href,
  );

  if (!actionsMatch || actionsMatch[1] !== GHA_REPO) return;

  const inputs = new URLSearchParams(actionsMatch[2]);

  (async () => {
    const summary = await query(document, "details > summary.btn");
    summary.click();

    const panel = await query(document, "details .workflow-dispatch");

    const setInput = (name, value) => {
      const el = panel.querySelector(`[name='inputs[${name}]']:not([type=hidden])`);
      if (!el) return;

      if (el.type === "checkbox") {
        el.checked = value === "true" || value === true;
      } else {
        el.value = value;
      }
    };

    for (const [name, value] of inputs) {
      setInput(name, value);
    }

    panel.querySelector("button[type=submit]")?.focus();
  })();
})();
