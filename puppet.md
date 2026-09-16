# Architecture Proposal: The "Puppet Pattern" for Secure One-Way Iframe Control

## Executive Summary
When embedding third-party or dynamic user content via `srcdoc` or `<iframe>` elements, web application security enforces a strict binary model:
1. **Symmetric Direct Access:** Granting `allow-same-origin` allows the parent page to directly manipulate the child DOM, but simultaneously grants the child frame unrestricted access to the parent’s DOM, cookies, and local storage.
2. **Total Isolation:** Applying strict `sandbox` policies prevents the child from reaching the parent, but completely blocks the parent from directly interacting with or reading the child DOM (including taking screenshots).

This proposal outlines the **Puppet Pattern**, an architectural design that achieves **asymmetric, one-way control**. It allows a host application to programmatically drive and capture a sandboxed iframe without exposing host context to potential cross-site scripting (XSS) or privilege escalation vectors inside the child.

---

## Problem Statement
Under the browser Same-Origin Policy (SOP), cross-frame DOM inspection is strictly symmetric:
* `Host -> Child` access requires same-origin context.
* `Child -> Host` access is granted automatically once same-origin context exists (`window.parent.document`).

In environments where iframe content is dynamic or user-generated, granting `allow-same-origin` exposes the parent application to session hijacking and DOM tampering. Conversely, locking the iframe down breaks host-side client automation (e.g., clicking internal elements, capturing UI screenshots).

---

## Proposed Architecture: The Puppet Pattern

The Puppet Pattern resolves this dilemma by decoupling **orchestration** (parent) from **execution** (child):

1. **Strict Origin Isolation:** The iframe is configured with `sandbox="allow-scripts"` (intentionally omitting `allow-same-origin`). The browser isolates the child frame into a unique opaque origin.
2. **Injected Bridge Script ("Puppet"):** A minimal, trusted event listener is injected into the iframe's `srcdoc` source before rendering.
3. **Asynchronous IPC Channel:** All host-to-child requests and child-to-host responses travel exclusively through `window.postMessage()`.

```
┌────────────────────────────────────────────────────────┐
│                      Parent Host                       │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Orchestrator / Controller                        │  │
│  └──────────────────┬───────────────────────────────┘  │
└─────────────────────┼──────────────────────────────┘
                      │ postMessage({ command: 'click' })
                      ▼
┌────────────────────────────────────────────────────────┐
│              Sandboxed Child Frame (Opaque)             │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Injected Puppet Driver                           │  │
│  │  - Listens for explicit command protocol        │  │
│  │  - Executes DOM actions inside child context     │  │
│  │  - Captures DOM via internal html2canvas         │  │
│  └──────────────────┬───────────────────────────────┘  │
└─────────────────────┼──────────────────────────────┘
                      │ postMessage({ type: 'result' })
                      ▼
```

---

## Implementation Specification

### 1. Injected Child Puppet Script
The puppet listener runs inside the child context, receiving commands and returning structured output.

```html
<iframe id="childIframe" sandbox="allow-scripts" srcdoc="
  <!DOCTYPE html>
  <html>
    <head>
      <script src='https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js'></script>
      <script>
        window.addEventListener('message', async (event) => {
          const { command, selector, reqId } = event.data || {};

          if (command === 'click') {
            const el = document.querySelector(selector);
            if (el) el.click();
          }

          if (command === 'screenshot') {
            if (typeof html2canvas !== 'undefined') {
              const canvas = await html2canvas(document.body);
              const dataUrl = canvas.toDataURL('image/png');
              window.parent.postMessage({ reqId, type: 'screenshot_reply', data: dataUrl }, '*');
            }
          }
        });
      </script>
    </head>
    <body>
      <!-- Dynamic / Embedded Content -->
    </body>
  </html>
"></iframe>
```

### 2. Parent Host Controller
The parent orchestrator invokes actions asynchronously using explicit protocol messages.

```javascript
class IframePuppeteer {
  constructor(iframeElement) {
    this.iframe = iframeElement;
  }

  sendCommand(command, payload = {}) {
    const reqId = crypto.randomUUID();
    this.iframe.contentWindow.postMessage({ command, ...payload, reqId }, '*');
  }

  click(selector) {
    this.sendCommand('click', { selector });
  }

  captureScreenshot() {
    return new Promise((resolve) => {
      const handler = (event) => {
        if (event.data?.type === 'screenshot_reply') {
          window.removeEventListener('message', handler);
          resolve(event.data.data);
        }
      };
      window.addEventListener('message', handler);
      this.sendCommand('screenshot');
    });
  }
}
```

---

## Security & Threat Model Analysis

| Vulnerability / Threat Vector | SOP Standard Response | Puppet Pattern Mitigation |
| :--- | :--- | :--- |
| **Child script calls `window.parent.document`** | Allowed under `allow-same-origin` | **Blocked.** Throws `DOMException` due to opaque origin mismatch. |
| **Child attempts cookie / storage theft** | Full access under same origin | **Blocked.** Opaque origin has zero access to parent cookies or `localStorage`. |
| **Parent DOM hijacking via XSS in iframe** | Critical Risk | **Mitigated.** Child can only emit data through explicit `postMessage` payloads. |
| **Malicious command injection** | High Risk | **Mitigated.** Child accepts parameter data only; arbitrary string evaluation (`eval()`) is excluded. |

---

## Key Advantages & Trade-Offs

### Advantages
* **Enforced One-Way Security:** Completely blocks privilege escalation from child to parent.
* **Client-Side Rendering:** Enables DOM screenshot capabilities within sandboxed frames without relying on expensive server-side headless browsers (e.g., Puppeteer, Playwright).
* **Decoupled API:** Wraps frame interaction into clean JS primitives (`click()`, `captureScreenshot()`).

### Trade-Offs & Considerations
* **Requires Script Injection:** The parent application must control the `srcdoc` generation or have permission to insert the bridge script.
* **Asynchronous Overhead:** Direct DOM operations switch from synchronous method calls to asynchronous RPC-style message passing.

---

## Recommendation
For production applications requiring safe driver automation over semi-trusted or isolated dynamic content, adopt the **Puppet Pattern** as the baseline security standard.
