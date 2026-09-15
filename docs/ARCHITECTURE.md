# envpilot 0.4 architecture

The Bash and PowerShell component installers remain platform adapters. `envpilot-core` supplies one strict YAML boundary, structured configuration export, shell-file generation, recovery snapshots, release-package updates and a local Codex protocol readiness probe. Linux builds disable CGO; end users do not need a language runtime to load configuration.

Shell profiles contain only a marked loader. Generated files hold envpilot-owned settings and namespaced helpers. User dotfiles, arbitrary functions and aliases remain user-owned. The old large templates are retained as compatibility fixtures, not installed for new users.

Codex state is identified by user, node, control socket and process start identity. Runtime generations remain separate from persistent credentials and sessions. Readiness includes a WebSocket/JSON-RPC initialize exchange. Native daemon management is used only where its installation-path requirements apply; its presence in `--help` alone does not establish that it can launch a node-local cache.

Maintenance jobs download into staging locations and replace validated file sets transactionally. A private GitHub App installed only on this repository supplies short-lived Contents/Pull requests tokens. Configure repository variable `ENVPILOT_APP_ID` and secret `ENVPILOT_APP_PRIVATE_KEY`; never store a private key or installation token in the repository. PR CI retains read-only permissions.

References reviewed on 2026-09-15:

| Project | Stars | Applied idea |
| --- | ---: | --- |
| [mise](https://mise.jdx.dev/getting-started.html) | 33,943 | Central configuration and explicit command environments. |
| [chezmoi](https://www.chezmoi.io/quick-start/) | 21,604 | Preview changes and preserve recoverable state. |
| [direnv](https://direnv.net/docs/hook.html) | 15,446 | Small shell entrypoints with independent implementation. |
| [Dotbot](https://github.com/anishathalye/dotbot) | 8,004 | Declarative YAML and repeatable application. |

These projects are design references, not envpilot runtime dependencies. Codex protocol behavior follows [official documentation](https://developers.openai.com/codex/app-server/); GitHub automation follows [workflow trigger documentation](https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-when-your-workflow-runs/triggering-a-workflow).
