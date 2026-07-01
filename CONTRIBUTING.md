# Contributing to QalKulator Calculator

Thanks for your interest! QalKulator Calculator is **beta** software under active
development, and contributions are genuinely welcome.

## Who can contribute

- **People** — bug reports, feature ideas, code, docs, translations, testing.
- **Human-guided AI agents** — using an AI assistant to help you write a patch or
  file a report is fine, **as long as a person is directing and reviewing the work**
  and stands behind the result.

## What is not accepted

- **Automated or unguided agent contributions.** No unattended bots, no
  mass-generated issues/PRs, and no AI agents acting without a responsible human
  who understands the change and can discuss it.

Every submission must have a real person behind it who can explain it, respond to
review feedback, and take responsibility for it. Contributions that appear to be
automated or unguided will be closed without detailed review.

## How to contribute

1. **Discuss first for anything non-trivial.** Open an issue describing the bug or
   proposal before writing a large change.
2. **Keep pull requests focused.** One logical change per PR; describe what and why.
3. **Match the surrounding code.** Follow the existing style, naming, and structure;
   the app is a thin C++/QML shell over [libqalculate](https://qalculate.github.io/) —
   no custom math.
4. **Build and test locally** before submitting:
   ```sh
   cmake -B build -S . -DCMAKE_BUILD_TYPE=RelWithDebInfo
   cmake --build build -j$(nproc)
   ```
5. **Sign off your commits** to certify you wrote the change and have the right to
   submit it (`git commit -s`, per the [Developer Certificate of Origin](https://developercertificate.org/)).

## Licensing

By contributing you agree that your contributions are licensed under the project's
**GNU Affero General Public License v3.0 or later** (see [`LICENSE`](LICENSE)).

## Reporting bugs

Use the issue tracker. Please include your OS/distro, how you installed QalKulator
(deb/rpm/Arch/Flatpak/AppImage/Windows), the version (**Help → About**), and clear
steps to reproduce.
