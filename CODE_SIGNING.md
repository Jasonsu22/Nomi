# Code signing policy

Free code signing on Windows provided by [SignPath.io](https://about.signpath.io/), certificate by [SignPath Foundation](https://signpath.org/).

## What is signed

- **What we sign:** the Windows installer (`Nomi-<version>-x64-setup.exe`) and the programs inside it.
- **How it's built:** by GitHub Actions, from this public repository. Only installers built that way are submitted for signing; nothing built on a personal computer is signed.
- **The Mac app:** distributed separately and not covered by this policy.

## Team and roles

| Role | Members |
| --- | --- |
| Committers and reviewers | [Jasonsu22](https://github.com/Jasonsu22) |
| Approvers | [Jasonsu22](https://github.com/Jasonsu22) |

- **Committers** may change the code in this repository.
- **Reviewers** check changes from other contributors before they are merged.
- **Approvers** approve each signing request, and only for a release built from this repository.

Everyone in these roles uses multi-factor authentication for GitHub and for SignPath.

## Privacy

This program will not transfer any information to other networked systems unless specifically requested by the user or the person installing or operating it. What Nomi sends, and when, is described in the [privacy policy](PRIVACY.md).
