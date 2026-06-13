# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | ✅        |

This is pre-1.0-era software in active development; security fixes land on the latest minor release.

## Reporting a vulnerability

Please report security issues **privately**, not as public GitHub issues.

Use GitHub's private vulnerability reporting: go to the **Security** tab of this repository and click **Report a vulnerability**. That opens a private advisory visible only to the maintainer.

When you report, include:

- the affected version or commit,
- a description of the issue and its impact,
- steps to reproduce, and
- any suggested remediation.

You can expect an acknowledgement within a few days. Once a fix is ready, a patched release is published and the advisory is disclosed with credit to the reporter, unless you ask to stay anonymous.

## Scope worth extra care

This package handles bearer tokens for the Cohere API. The areas most relevant to a security report:

- token handling in `TokenProvider`, `KeychainTokenStore`, and the request `Authorization` header,
- anything that could cause a token, API key, or auth header to be logged, persisted, or placed in a URL, and
- the SSE parser and stream decoder, which process untrusted network input.

Tokens are never logged at any level and are read per request; if you find a path that breaks that invariant, it is a valid report.
