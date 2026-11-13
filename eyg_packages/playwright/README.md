# Playwright for Overlay artifacts

Check and drive artifacts shown in Overlay with the
[Playwright](https://playwright.dev/docs/api/class-locator) API.
Every action performs the `Puppet` effect, a script in the sandboxed preview
acts on the document and replies with data, see
[the guide](../../guides/overlay_artifacts.md#artifact-control).

EYG has no methods, so each function takes the locator as its first argument.
Locators are plain records, narrowing one never runs anything.

| Playwright | EYG |
| --- | --- |
| `page.locator('li')` | `locator(page("board"), "li")` |
| `page.getByRole('button', {name: 'Next'})` | `get_by_role(page("board"), "button", "Next")` |
| `locator.first()`, `.last()`, `.nth(2)` | `first(l)`, `last(l)`, `nth(l, 2)` |
| `locator.filter({hasText: 'Hill'})` | `filter(l, "Hill")` |
| `await locator.click()` | `click(l)` |
| `await locator.fill('214')` | `fill(l, "214")` |
| `await locator.textContent()` | `text_content(l)` |
| `await locator.getAttribute('href')` | `get_attribute(l, "href")`, `Some(value)` or `None({})` |
| `await locator.screenshot()` | `screenshot(l)` |
| `await expect(locator).toHaveCount(2)` | `expect(l).to_have_count(2)` |

`page(name)` follows the latest version of a shown artifact and
`revision(name, version)` a pinned version.
Actions wait for exactly one visible element, like Playwright's strict locators.
Assertions retry until the timeout, 5000 milliseconds unless set with
`with_timeout(l, milliseconds)`. Any failure aborts with the reason.

```eyg
let pw = import "./index.eyg"
let board = pw.page("departures")
let _ = pw.fill(pw.get_by_placeholder(board, "Route"), "214")
let _ = pw.expect(pw.locator(board, "li")).to_have_count(2)
pw.screenshot(board)
```

The screenshot is PNG bytes, the latest screenshots are also shown to the agent
with the result of its tool call.

Test: `eyg script eyg_packages/playwright/entry.eyg` from the repository root.
