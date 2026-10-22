# App Composition

- Own app entry, root containers, localization preferences, and iOS app-shell navigation here.
- Create one explicit production dependency graph and inject it at app or feature roots.
- Keep composition owners plain and non-observable. They assemble dependencies, not duplicate feature state.
- Keep live, preview, and test assembly explicit; previews must not start external work.
