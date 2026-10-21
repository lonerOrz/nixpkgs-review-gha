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
    // Yield once before the first lookup so callers can rely on await semantics.
    await sleep(0);
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

      // Optional: a merged/closed PR cannot be built, so the button is disabled.
      const state = (
        document.querySelector(
          "div[data-component=TitleArea] div[data-component=PH_LeadingVisual] span, span.State",
        )?.innerText ?? ""
      )
        .trim()
        .toUpperCase();

      return {
        "x86_64-linux": !hasRebuilds || hasLinuxRebuilds,
        "aarch64-linux": !hasRebuilds || hasLinuxRebuilds,
        "x86_64-darwin": !hasRebuilds || hasDarwinRebuilds ? `yes_sandbox_${DARWIN_SANDBOX}` : "no",
        "aarch64-darwin": !hasRebuilds || hasDarwinRebuilds ? `yes_sandbox_${DARWIN_SANDBOX}` : "no",
        state,
      };
    };

    // True when the PR is already merged/closed -- building it is pointless and
    // the dispatch would run against a ref that may no longer resolve.
    const isClosed = () => ["MERGED", "CLOSED"].includes(getPrDetails().state);

    const injectButton = async () => {
      const actions = await query(document, "div[data-component=PH_Actions], .gh-header-show .gh-header-actions");
      if (actions.querySelector(".run-build-pr")) return;

      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "Button Button--secondary Button--small run-build-pr";
      btn.innerText = "Run build-pr";

      btn.onclick = () => {
        if (isClosed()) {
          alert(`${repo}#${prNumber} is already ${getPrDetails().state.toLowerCase()}.`);
          return;
        }

        // `packages` is a required input of build-pr.yml and it cannot be
        // guessed: a PR routinely touches several packages (or none that the
        // title names), so the user always fills it in explicitly.
        const packages = (prompt(`Packages to build for ${repo}#${prNumber} (comma separated)`) ?? "").trim();
        if (packages === "") return;

        // `state` is only used for UI gating, it is not a workflow input.
        const { state: _state, ...buildInputs } = getPrDetails();

        const params = new URLSearchParams({
          repo,
          "pr-number": prNumber,
          packages,
          ...buildInputs,
        });

        const url =
          `https://github.com/${GHA_REPO}` + `/actions/workflows/${WORKFLOW}` + `#dispatch:${params.toString()}`;

        window.open(url, "_blank");
      };

      actions.prepend(btn);

      // Mirror the state onto the button, like shortcut.user.js does for review.
      if (isClosed()) btn.setAttribute("aria-disabled", "true");
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
    (
      await query(
        document,
        'details > summary.btn, react-app.loaded [data-component="PH_Actions"] button[data-variant="primary"]',
      )
    ).click();
    await query(document, ':is(details .workflow-dispatch, [role="dialog"]) [name="inputs[repo]"]');

    const setInput = (name, value) => {
      const selector = `:is(details .workflow-dispatch, [role="dialog"]) [name='inputs[${name}]']`;
      const input = document.querySelector(`${selector}:not([type=hidden])`);
      if (!input) {
        console.warn(`build-pr launcher: input '${name}' not found, skipped`);
        return false;
      }

      if (input.type === "checkbox") {
        if (value !== "true" && value !== "false" && value !== true && value !== false) {
          alert(`workflow_dispatch input '${name}' expects a boolean but is set to '${value}'`);
          return false;
        }
        input.checked = value === "true" || value === true;
      } else {
        input.value = value;
      }
      return true;
    };

    // Required inputs of build-pr.yml. If any is missing from the form we abort
    // instead of letting the user submit a dispatch that will be rejected.
    const required = ["repo", "pr-number", "packages"];
    const missing = [];

    for (const [name, value] of inputs) {
      if (!setInput(name, value) && required.includes(name)) missing.push(name);
    }

    for (const name of required) {
      if (![...inputs.keys()].includes(name)) missing.push(name);
    }

    if (missing.length > 0) {
      alert(`build-pr launcher: missing required input(s): ${[...new Set(missing)].join(", ")}`);
      return;
    }

    document
      .querySelector('details .workflow-dispatch button[type=submit], [role="dialog"] button[type=submit]')
      ?.focus();
  })();
})();
