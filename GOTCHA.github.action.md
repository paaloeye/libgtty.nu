# GitHub Actions Gotchas and Learnings

A reference guide documenting crucial GitHub Actions behaviours, workflow setups, and module integration patterns under a Nushell-centric development pipeline.

---

## Environment Context

This document and the associated workflows were formulated under the following environment:

- **Nushell Version**: `0.114.0`
- **AI Agent**: `Antigravity CLI 1.0.16`
- **Model**: `Google Gemini 3.1 Pro (High)`

---

## 1. Modern Checkout Versioning

Using outdated version tags for core GitHub Action steps can lead to performance regressions, missing capabilities,
or execution failures under newer operating system runners.

### Gotchas

- **Do NOT use**: `actions/checkout@v4` or older versions in new workflow setups unless strictly locked by legacy environments.
- **Do use**: `actions/checkout@v7` to pull down the repository codebase securely and efficiently.

```yaml
# ✅ Modern setup using current major version
- name: Checkout Code
  uses: actions/checkout@v7
```

---

> [!CAUTION]
> This file was compiled and written with AI assistance (Antigravity).
