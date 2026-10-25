# Security policy

## Supported versions

tosk is in preview. Only the **latest preview release** (the newest `preview-*` release on this repository, and the web app at https://linguaperta.github.io/tosk/) gets security fixes. Fixes are not backported; update to the newest preview.

Course packs are published separately in [linguaperta/tosk-data](https://github.com/linguaperta/tosk-data); report problems with a pack's content there, and problems with how the app or the pipeline handles packs here.

## Reporting a vulnerability

Please report vulnerabilities **privately**:

1. Use GitHub's private vulnerability reporting: open the repository's **Security** tab and click **Report a vulnerability** (https://github.com/linguaperta/tosk/security/advisories/new).
2. If that button is not available, open a regular [issue](https://github.com/linguaperta/tosk/issues) that says only that you have a security report and asks for a private channel. Don't put details, proof-of-concept files or affected data in the public issue.

Helpful to include: the affected version (Settings → About) and platform, what an attacker needs (a crafted course pack, a backup file, a course index, network position), the steps to reproduce, and the impact.

This is a hobby project maintained by one person, so there is no bounty and no fixed response time; expect an answer within a couple of weeks. Once a fix is released, the report can be credited in the release notes if you like.

## Scope

In scope: the app (Android, iOS, Windows, web), its handling of course packs, course indexes and backup files, cloud sync and its Firestore security rules (`firebase/`), the AI key handling, the pack toolkit in `pipeline/`, and this repository's CI workflows.

Out of scope: the AI provider you configure (Anthropic, OpenAI or your own server), Google and Firebase services themselves, GitHub, and attacks that need full control of an unlocked device.
