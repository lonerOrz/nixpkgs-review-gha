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

  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

  const query = async (root, selector) => {
    await sleep(0);

    while (true) {
      const element = root.querySelector(selector);
      if (element) return element;
      await sleep(100);
    }
  };

  // ---------- PR page ----------

  const prMatch = /^https:\/\/github.com\/([^/]+\/[^/]+)\/pull\/(\d+)/.exec(
    location.href,
  );

  if (prMatch) {
    const [, repo, prNumber] = prMatch;

    const getPrDetails = () => {
      const labels = [...document.querySelectorAll("div.js-issue-labels a")]
        .map(element => element.innerText.trim());

      const hasLinuxRebuilds = !labels.some(label =>
        /rebuild-linux:\s*0$/i.test(label),
      );
      const hasDarwinRebuilds = !labels.some(label =>
        /rebuild-darwin:\s*0$/i.test(label),
      );
      const hasRebuilds = hasLinuxRebuilds || hasDarwinRebuilds;

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
        "x86_64-darwin": !hasRebuilds || hasDarwinRebuilds
          ? `yes_sandbox_${DARWIN_SANDBOX}`
          : "no",
        "aarch64-darwin": !hasRebuilds || hasDarwinRebuilds
          ? `yes_sandbox_${DARWIN_SANDBOX}`
          : "no",
        state,
      };
    };

    const isClosed = () =>
      ["MERGED", "CLOSED"].includes(getPrDetails().state);

    const injectButton = async () => {
      const actions = await query(
        document,
        "div[data-component=PH_Actions], .gh-header-show .gh-header-actions",
      );

      if (actions.querySelector(".run-build-pr")) return;

      const button = document.createElement("button");
      button.type = "button";
      button.className = "Button Button--secondary Button--small run-build-pr";
      button.innerText = "Run build-pr";

      button.onclick = () => {
        const details = getPrDetails();

        if (["MERGED", "CLOSED"].includes(details.state)) {
          alert(`${repo}#${prNumber} is already ${details.state.toLowerCase()}.`);
          return;
        }

        const { state: _state, ...buildInputs } = details;

        const params = new URLSearchParams({
          repo,
          "pr-number": prNumber,
          ...Object.fromEntries(
            Object.entries(buildInputs).map(([name, value]) => [
              name,
              String(value),
            ]),
          ),
          "pr-comment": "true",
          "telegram-notification": "true",
        });

        const url =
          `https://github.com/${GHA_REPO}` +
          `/actions/workflows/${WORKFLOW}` +
          `#dispatch:${params.toString()}`;

        window.open(url, "_blank");
      };

      actions.prepend(button);

      if (isClosed()) {
        button.setAttribute("aria-disabled", "true");
      }
    };

    new MutationObserver(injectButton).observe(document, {
      childList: true,
      subtree: true,
    });

    injectButton();
    return;
  }

  // ---------- Actions page ----------

  const actionsMatch =
    /^https:\/\/github.com\/([^/]+\/[^/]+)\/actions\/workflows\/build-pr\.yml#dispatch:(.*)$/.exec(
      location.href,
    );

  if (!actionsMatch || actionsMatch[1] !== GHA_REPO) return;

  const inputs = new URLSearchParams(actionsMatch[2]);

  (async () => {
    const dispatchButton = await query(
      document,
      'details > summary.btn, react-app.loaded [data-component="PH_Actions"] button[data-variant="primary"]',
    );

    dispatchButton.click();

    await query(
      document,
      ':is(details .workflow-dispatch, [role="dialog"]) [name="inputs[repo]"]',
    );

    const setInput = (name, value) => {
      const selector =
        `:is(details .workflow-dispatch, [role="dialog"]) [name="inputs[${name}]"]`;

      const input = document.querySelector(
        `${selector}:not([type=hidden])`,
      );

      if (!input) {
        console.warn(`build-pr launcher: input '${name}' not found`);
        return false;
      }

      if (input.type === "checkbox") {
        if (value !== "true" && value !== "false") {
          console.warn(
            `build-pr launcher: input '${name}' expects a boolean, got '${value}'`,
          );
          return false;
        }

        input.checked = value === "true";
      } else {
        input.value = value;
      }

      input.dispatchEvent(new Event("input", { bubbles: true }));
      input.dispatchEvent(new Event("change", { bubbles: true }));

      return true;
    };

    for (const [name, value] of inputs) {
      setInput(name, value);
    }

    document
      .querySelector(
        'details .workflow-dispatch button[type=submit], [role="dialog"] button[type=submit]',
      )
      ?.focus();
  })();
})();
