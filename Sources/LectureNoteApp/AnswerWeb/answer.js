// Draws one answer: Markdown through markdown-it, formulas through KaTeX, then Nomi's own pieces:
// source chips after a sentence, links to files the answer wrote, and demo cards in sandboxed frames.
// Swift calls nomi.render(payload) with the whole answer each time it changes; the page reports its
// height and every click back through the "nomi" message handler.
(function () {
  "use strict";

  const root = document.getElementById("answer");
  const post = (message) => {
    const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nomi;
    if (handler) handler.postMessage(message);
  };

  const md = window.markdownit({ html: false, linkify: true, breaks: false, typographer: false });
  // Only web links stay links; anything else (javascript:, file:, custom schemes) is shown as text.
  const allowLink = md.validateLink;
  md.validateLink = (url) => /^https?:\/\//i.test(url.trim()) && allowLink(url);

  // ---------- Formulas ----------
  // Formulas are cut out before Markdown runs, so underscores and backslashes inside them are not
  // read as emphasis or escapes. The rules match AnswerDocument.swift: \[…\], $$…$$, \(…\) and $…$.
  const OPEN = "", CLOSE = "";

  function protectMath(source, streaming, formulas) {
    let out = "";
    let i = 0;
    let fence = null;   // the fence marker while inside a fenced code block
    let lineStart = true;
    while (i < source.length) {
      if (lineStart) {
        const line = source.slice(i, source.indexOf("\n", i) === -1 ? source.length : source.indexOf("\n", i));
        const marker = line.match(/^\s{0,3}(`{3,}|~{3,})/);
        if (fence) {
          if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length) fence = null;
          out += line; i += line.length; lineStart = false; continue;
        }
        if (marker) { fence = marker[1]; out += line; i += line.length; lineStart = false; continue; }
      }
      const ch = source[i];
      if (ch === "\n") { out += ch; i++; lineStart = true; continue; }
      lineStart = false;
      if (ch === "`") {
        let ticks = 1;
        while (source[i + ticks] === "`") ticks++;
        const run = "`".repeat(ticks);
        const end = source.indexOf(run, i + ticks);
        if (end !== -1) { out += source.slice(i, end + ticks); i = end + ticks; continue; }
        out += source.slice(i, i + ticks); i += ticks; continue;
      }
      let matched = false;
      for (const [open, close, display] of [["\\[", "\\]", true], ["$$", "$$", true], ["\\(", "\\)", false]]) {
        if (!source.startsWith(open, i)) continue;
        const end = source.indexOf(close, i + open.length);
        if (end === -1) {
          if (streaming) return out; // an unfinished formula: hide it until it is complete
          break;
        }
        const latex = source.slice(i + open.length, end).trim();
        if (latex) { formulas.push({ latex, display }); out += OPEN + (formulas.length - 1) + CLOSE; }
        i = end + close.length;
        matched = true;
        break;
      }
      if (matched) continue;
      if (ch === "$" && source[i + 1] !== "$") {
        const next = source[i + 1];
        if (next && next !== " " && next !== "\n") {
          let end = i + 1;
          while (end < source.length && source[end] !== "$" && source[end] !== "\n") end++;
          if (source[end] === "$" && source[end - 1] !== " ") {
            const latex = source.slice(i + 1, end).trim();
            if (latex) { formulas.push({ latex, display: false }); out += OPEN + (formulas.length - 1) + CLOSE; i = end + 1; continue; }
          }
        }
      }
      out += ch; i++;
    }
    return out;
  }

  const formulaToken = new RegExp(OPEN + "(\\d+)" + CLOSE, "g");
  function restoreMath(html, formulas) {
    return html.replace(formulaToken, (_, index) => {
      const formula = formulas[Number(index)];
      if (!formula) return "";
      // Inline fractions are drawn at full size: shrunk to script size, ⅓ and ½ were hard to read.
      const latex = !formula.display && /\\frac/.test(formula.latex) ? "\\displaystyle " + formula.latex : formula.latex;
      try {
        // HTML only: WebKit paints the selection of KaTeX's hidden MathML copy as dark blocks.
        // The LaTeX source rides along for copying (see the copy handler below).
        const html = katex.renderToString(latex, { displayMode: formula.display, throwOnError: false, output: "html" });
        const source = md.utils.escapeHtml(formula.display ? "$$" + formula.latex + "$$" : "$" + formula.latex + "$");
        return html.replace('<span class="katex', '<span data-latex="' + source + '" class="katex');
      } catch (error) {
        return '<span class="math-error">' + md.utils.escapeHtml(formula.latex) + "</span>";
      }
    });
  }

  // ---------- Fences: code, demo cards, and a demo still being written ----------
  let renderState = null;
  const defaultFence = md.renderer.rules.fence;
  md.renderer.rules.fence = function (tokens, index, options, env, self) {
    // The app decides what each fence is (AnswerDocument.fenceRoles), so a card shows exactly
    // where it would anywhere else in Nomi.
    const role = renderState.fenceRoles[renderState.nextFence++] || "code";
    if (role === "empty") return "";
    if (role === "preparing") return '<div class="preparing">' + md.utils.escapeHtml(renderState.preparing) + "</div>";
    if (role === "widget") {
      const widget = renderState.widgets[renderState.nextWidget];
      if (widget) {
        renderState.nextWidget++;
        return cardHTML(widget, renderState.nextWidget - 1);
      }
    }
    return defaultFence(tokens, index, options, env, self);
  };
  md.renderer.rules.table_open = () => '<div class="table"><table>';
  md.renderer.rules.table_close = () => "</table></div>";
  md.renderer.rules.image = function (tokens, index) {
    const token = tokens[index];
    const src = token.attrGet("src") || "";
    const alt = md.utils.escapeHtml(token.content || "");
    if (!/^https:\/\//i.test(src)) return alt;
    return '<img class="remote" src="' + md.utils.escapeHtml(src) + '" alt="' + alt + '" title="' + alt + '">';
  };

  function cardHTML(widget, index) {
    const title = md.utils.escapeHtml(widget.title || renderState.cardTitle);
    return '<div class="card" data-card="' + index + '"><div class="card-title">' + title +
      '</div><div class="card-frame"><iframe sandbox="allow-scripts" data-card="' + index + '"></iframe></div></div>';
  }

  // A small script added to each demo page, so the card can grow to the demo's full height.
  const heightScript = "<script>(function(){function r(){var b=document.body;var h=Math.ceil(Math.max(b?b.scrollHeight:0,document.documentElement.scrollHeight));" +
    "parent.postMessage({nomiCardHeight:h},'*');}if(window.ResizeObserver&&document.body)new ResizeObserver(r).observe(document.body);" +
    "document.addEventListener('input',function(){requestAnimationFrame(r)});document.addEventListener('click',function(){requestAnimationFrame(r)});" +
    "window.addEventListener('load',r);r();})();<\/script>";

  function fillCards(nodes) {
    for (const node of nodes) {
      if (node.nodeType !== 1) continue;
      node.querySelectorAll("iframe[data-card]").forEach((frame) => {
        const widget = renderState.widgets[Number(frame.dataset.card)];
        if (!widget) return;
        const page = /<\/body>/i.test(widget.page) ? widget.page.replace(/<\/body>/i, heightScript + "</body>") : widget.page + heightScript;
        frame.src = "data:text/html;charset=utf-8," + encodeURIComponent(page);
      });
    }
  }

  window.addEventListener("message", (event) => {
    const height = event.data && event.data.nomiCardHeight;
    if (typeof height !== "number" || !isFinite(height) || height <= 0) return;
    root.querySelectorAll("iframe[data-card]").forEach((frame) => {
      if (frame.contentWindow !== event.source) return;
      const full = Math.max(height, 44);
      frame.style.height = full + "px";
      frame.parentElement.style.height = Math.ceil(full * 0.82) + "px";
    });
  });

  // ---------- Sources after a sentence ----------
  // A run such as [3][4] or [3], 【4】 becomes at most two chips, and a source already shown in the
  // same paragraph or list item is left out, as in AnswerInline.citationRun.
  const marker = "(?:\\[(\\d+)\\](?!\\()|【(\\d+)】)";
  const runPattern = new RegExp(marker + "(?:[ ,，、]*" + marker + ")*", "g");
  const markerPattern = new RegExp(marker, "g");
  const blockSelector = "p, li, td, th, h1, h2, h3, h4, blockquote";

  function linkCitations(citations, scope) {
    if (!citations || !Object.keys(citations).length) return;
    const shown = new WeakMap();
    const walker = document.createTreeWalker(scope, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const parent = node.parentElement;
        if (!parent || parent.closest("code, pre, a, .katex, .card")) return NodeFilter.FILTER_REJECT;
        return /[\[【]\d/.test(node.nodeValue) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
      },
    });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    for (const node of nodes) {
      const block = node.parentElement.closest(blockSelector) || root;
      if (!shown.has(block)) shown.set(block, new Set());
      const seen = shown.get(block);
      const text = node.nodeValue;
      const fragment = document.createDocumentFragment();
      let last = 0;
      let changed = false;
      runPattern.lastIndex = 0;
      let run;
      while ((run = runPattern.exec(text))) {
        const numbers = [];
        let one;
        markerPattern.lastIndex = 0;
        while ((one = markerPattern.exec(run[0]))) numbers.push(one[1] || one[2]);
        const resolved = numbers.map((n) => citations[n]).filter(Boolean);
        if (!resolved.length) continue;
        changed = true;
        fragment.append(document.createTextNode(text.slice(last, run.index)));
        let added = 0;
        for (const citation of resolved) {
          if (added >= 2 || seen.has(citation.key)) continue;
          seen.add(citation.key);
          const chip = document.createElement("a");
          chip.className = "cite";
          chip.textContent = citation.label;
          chip.dataset.url = citation.url;
          chip.dataset.kind = citation.kind || "web";
          // A space before each chip, so copied text does not run the source into the sentence.
          fragment.append(document.createTextNode(" "), chip);
          added++;
        }
        last = run.index + run[0].length;
      }
      if (!changed) continue;
      fragment.append(document.createTextNode(text.slice(last)));
      node.replaceWith(fragment);
    }
  }

  // Inline code naming a file the answer saved becomes a link to that file.
  function linkFiles(files, scope) {
    if (!files || scope.nodeType !== 1) return;
    const names = Object.keys(files);
    if (!names.length) return;
    scope.querySelectorAll("code").forEach((code) => {
      if (code.closest("pre")) return;
      const name = code.textContent.trim();
      const key = names.find((candidate) => candidate.toLowerCase() === name.toLowerCase());
      if (!key) return;
      const link = document.createElement("a");
      link.className = "file";
      link.textContent = code.textContent;
      link.dataset.url = files[key];
      code.replaceWith(link);
    });
  }

  // ---------- Rendering ----------
  // While streaming, an unclosed **bold** or `code` would show its raw marker for a moment; close it.
  function closeOpenMarks(source) {
    const lastBlock = source.slice(source.lastIndexOf("\n\n") + 1);
    let text = source;
    if ((lastBlock.match(/\*\*/g) || []).length % 2 === 1) text += "**";
    if ((lastBlock.replace(/```/g, "").match(/`/g) || []).length % 2 === 1) text += "`";
    return text;
  }

  let lastKey = "";
  function render(payload) {
    document.documentElement.dataset.scheme = payload.dark ? "dark" : "light";
    const key = JSON.stringify(payload);
    if (key === lastKey) return report();
    lastKey = key;
    const formulas = [];
    let source = payload.markdown || "";
    source = protectMath(source, payload.streaming, formulas);
    if (payload.streaming) source = closeOpenMarks(source);
    const tokens = md.parse(source, {});
    renderState = {
      widgets: payload.widgets || [],
      nextWidget: 0,
      fenceRoles: payload.fenceRoles || [],
      nextFence: 0,
      preparing: payload.preparing || "",
      cardTitle: payload.cardTitle || "",
    };
    const added = reconcile(restoreMath(md.renderer.render(tokens, md.options, {}), formulas));
    for (const node of added) {
      linkCitations(payload.citations, node);
      linkFiles(payload.files, node);
    }
    fillCards(added);
    showSources(payload.sources, payload.sourcesLabel);
    report();
    reportSoon();
  }

  // One chip per distinct source, above the answer. Hovering and clicking work like the inline ones.
  const sourcesRow = document.getElementById("sources");
  let sourcesKey = "";
  function showSources(sources, label) {
    const key = JSON.stringify(sources || []) + (label || "");
    if (key === sourcesKey) return;
    sourcesKey = key;
    sourcesRow.textContent = "";
    sourcesRow.hidden = !sources || sources.length === 0;
    if (sourcesRow.hidden) return;
    const title = document.createElement("span");
    title.className = "label";
    title.textContent = label || "";
    const chips = document.createElement("div");
    chips.className = "chips";
    for (const source of sources) {
      const chip = document.createElement("a");
      chip.className = "cite";
      chip.dataset.url = source.url;
      chip.dataset.kind = source.kind;
      const text = document.createElement("span");
      text.textContent = source.label;
      chip.append(text);
      chips.append(chip);
    }
    sourcesRow.append(title, chips);
  }

  // Blocks that did not change stay as they are: a demo keeps running, and a selection in the part
  // already written survives while the rest of the answer streams in.
  function reconcile(html) {
    const template = document.createElement("template");
    template.innerHTML = html;
    const fresh = Array.from(template.content.childNodes);
    const old = Array.from(root.childNodes);
    const added = [];
    fresh.forEach((node, index) => {
      const key = node.nodeType === 1 ? node.outerHTML : node.textContent;
      const previous = old[index];
      if (previous && previous.__nomiKey === key) return;
      node.__nomiKey = key;
      if (previous) root.replaceChild(node, previous); else root.appendChild(node);
      added.push(node);
    });
    for (let index = fresh.length; index < old.length; index++) old[index].remove();
    return added;
  }

  // ---------- Height and clicks ----------
  let reported = 0;
  // Where each demo card sits, so a right-click anywhere on it can show the menu for its saved file.
  // The click itself lands inside the card's sandboxed frame, where this page cannot see it.
  let reportedCards = "";
  // Measured from the top of the page to a marker after the answer, so the sources row and every
  // margin count. Measuring the answer block alone left its last line under whatever came next.
  const endMarker = document.getElementById("end");
  function report() {
    const height = Math.ceil(endMarker.getBoundingClientRect().top + window.scrollY) + 2;
    if (height !== reported) {
      reported = height;
      post({ height });
    }
    const cards = Array.from(root.querySelectorAll(".card")).map((card) => {
      const widget = renderState && renderState.widgets[Number(card.dataset.card)];
      const rect = card.getBoundingClientRect();
      return [rect.left, rect.top, rect.width, rect.height, (widget && widget.file) || ""];
    }).filter((card) => card[4]);
    const key = JSON.stringify(cards);
    if (key !== reportedCards) {
      reportedCards = key;
      post({ cards });
    }
  }
  new ResizeObserver(report).observe(root);
  new ResizeObserver(report).observe(document.body);
  window.addEventListener("resize", report);
  // Fonts and chips can settle a moment after drawing and change how lines wrap.
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(report);
  function reportSoon() {
    requestAnimationFrame(() => requestAnimationFrame(report));
    setTimeout(report, 250);
  }

  document.addEventListener("click", (event) => {
    const target = event.target.closest("a, img.remote");
    if (!target) return;
    event.preventDefault();
    if (window.getSelection && String(window.getSelection()).length > 0 && target.tagName !== "A") return;
    const url = target.dataset.url || target.getAttribute("href") || target.getAttribute("src");
    if (url) post({ open: url });
  });

  // Resting on a source for a moment shows its preview card, drawn natively by the app. Once a card
  // is up, moving straight to the next source swaps it at once instead of waiting again.
  let hoverTimer = null;
  let hovered = null;
  let cardShown = false;
  let leftAt = 0;
  function showCard(chip) {
    const rect = chip.getBoundingClientRect();
    cardShown = true;
    post({ hover: chip.dataset.url, label: chip.textContent, rect: [rect.left, rect.top, rect.width, rect.height] });
  }
  document.addEventListener("mouseover", (event) => {
    const chip = event.target.closest("a.cite");
    if (chip === hovered) return;
    clearTimeout(hoverTimer);
    if (hovered) {
      post({ unhover: true });
      leftAt = Date.now();
    }
    hovered = chip;
    if (!chip) return;
    if (cardShown && Date.now() - leftAt < 400) {
      showCard(chip);
      return;
    }
    cardShown = false;
    hoverTimer = setTimeout(() => showCard(chip), 350);
  });
  document.addEventListener("mouseleave", () => {
    clearTimeout(hoverTimer);
    if (hovered) {
      post({ unhover: true });
      leftAt = Date.now();
    }
    hovered = null;
  });
  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;
    clearTimeout(hoverTimer);
    cardShown = false;
    post({ escape: true });
  });

  // WebKit leaves the boxes formulas are drawn in unpainted inside a selection, so a selected formula
  // shows dark gaps. Selected formulas get the selection color themselves.
  document.addEventListener("selectionchange", () => {
    const selection = window.getSelection();
    const range = selection && selection.rangeCount && !selection.isCollapsed ? selection.getRangeAt(0) : null;
    root.querySelectorAll(".katex").forEach((formula) => {
      formula.classList.toggle("selected", !!range && range.intersectsNode(formula));
    });
  });

  // Copying a selection that includes formulas gives their LaTeX source, not KaTeX's drawing pieces.
  document.addEventListener("copy", (event) => {
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return;
    const fragment = selection.getRangeAt(0).cloneContents();
    const formulas = fragment.querySelectorAll("[data-latex]");
    const partial = !formulas.length && selection.anchorNode && selection.anchorNode.parentElement &&
      selection.anchorNode.parentElement.closest("[data-latex]");
    if (!formulas.length && !partial) return;
    if (partial) {
      event.clipboardData.setData("text/plain", partial.dataset.latex);
    } else {
      formulas.forEach((formula) => formula.replaceWith(document.createTextNode(formula.dataset.latex)));
      const box = document.createElement("div");
      box.style.cssText = "position:fixed;left:-9999px;white-space:pre-wrap";
      box.append(fragment);
      document.body.append(box);
      event.clipboardData.setData("text/plain", box.innerText);
      box.remove();
    }
    event.preventDefault();
  });

  window.nomi = { render };
  post({ ready: true });
})();
