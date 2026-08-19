---
name: generate-security-md
description: "Create or update a SECURITY.md file following NVIDIA security documentation standards. Analyzes the repository codebase for languages, frameworks, dependencies, APIs, network exposure, data handling, and auth mechanisms, then generates a contextually rich SECURITY.md with Reporting Policy, Architecture Context, Threat Model, and Critical Security Assumptions. Optionally incorporates a TAVA (Threat and Vulnerability Analysis) document. Use when asked to create SECURITY.md, add security policy, or generate security documentation."
metadata:
  author: "Bryan Wilcox <bwilcox@nvidia.com>"
  tags:
    - security
    - documentation
    - security-standards
    - security-policy
    - vulnerability-disclosure
    - threat-model
    - tava
    - compliance
  domain: security
---

# Generate SECURITY.md

Create or update a SECURITY.md by analyzing the current repository.

## Instructions

Use this skill when the user says "create SECURITY.md", "generate security policy", "add security documentation", "update SECURITY.md", "security policy for this repo", or "we need a SECURITY.md".

This skill analyzes the codebase (languages, dependencies, APIs, auth, data handling) and generates a SECURITY.md with four required sections: Reporting Policy, Architecture Context, Threat Model, and Critical Security Assumptions. It optionally incorporates TAVA documents and persists triage decisions across runs via `.security-triage.yaml`.

## Examples

```
> /generate-security-md
# Analyzes the current repo and generates a complete SECURITY.md

> /generate-security-md path/to/tava-report.md
# Incorporates an existing TAVA document into the threat model

> /generate-security-md
# On re-run with an existing .security-triage.yaml, suppresses
# previously triaged false positives and shows only new findings
```

## Related Skills

- **adversarial-security-review** — Zero-trust security audit; its report can feed this skill's Phase 2 TAVA intake, and it should suggest this skill when a SECURITY.md is missing.
- **tava-diagram-creator** — STRIDE threat-model diagrams; use it when Phase 4c would benefit from a trust-boundary/data-flow diagram, and link the result from the SECURITY.md.

## Phase 0: Pre-flight Checks

1. Verify this is a git repository:
   ```
   git rev-parse --is-inside-work-tree
   ```
   If this fails, tell the user: "This skill should be run from within a git repository." and stop.

2. Get the repository root and name:
   ```
   git rev-parse --show-toplevel
   git remote get-url origin 2>/dev/null
   ```
   Derive the project name from the remote URL, or fall back to the directory name.

## Phase 1: Discover Existing Security Artifacts

Search for existing security documentation:

- Glob for: `**/SECURITY.md`, `**/SECURITY.rst`, `**/SECURITY.txt`, `**/.github/SECURITY.md`
- Glob for TAVA/threat docs: `**/TAVA*`, `**/tava*`, `**/threat-model*`, `**/threat_model*`
- Check for triage file: `.security-triage.yaml` at the repo root
  - If found, read and parse it. Store the `false_positives` and `accepted_risks` lists for use in Phase 3 and Phase 4.
  - Also store any `repository_exposure_classification` and `service_exposure_classification` blocks for reuse in Phase 3i.
  - Validate the `version` field is `"1.0"`. If missing or unrecognized, warn the user and proceed without triage data.
  - Note the `last_updated` timestamp for display in Phase 7.
  - See [references/triage-file-reference.md](references/triage-file-reference.md) for the file schema.

If an existing SECURITY.md is found:
- Read it in full
- Assess which of the four required sections are present, missing, or incomplete:
  1. Reporting Policy
  2. Architecture Context
  3. Threat Model
  4. Critical Security Assumptions
- Store this assessment for Phase 5

## Phase 2: TAVA Intake (Optional)

The user may provide a TAVA document path as `$ARGUMENTS`.

**If `$ARGUMENTS` is a file path:** Read the file (supports .md, .txt, .pdf, .html, .csv).

**If `$ARGUMENTS` is empty:** Ask the user:
> Do you have a TAVA (Threat and Vulnerability Analysis) or other security assessment
> to incorporate? You can:
> 1. Paste it as markdown
> 2. Provide a file path
> 3. Skip (SECURITY.md will still be generated from code analysis)

**Extract from TAVA:**
- Identified threats with severity/likelihood ratings
- Security requirements (confidentiality, integrity, availability, authentication, non-repudiation)
- Trust boundaries and data flow descriptions
- Attack surface definitions and attacker models
- Recommended mitigations, CWE identifiers, CVSS scores

## Phase 3: Codebase Reconnaissance

Perform systematic analysis. Run discovery steps in parallel where possible.

**Triage filtering:** If a `.security-triage.yaml` was loaded in Phase 1, apply it during this phase. For each grep finding in sub-steps 3d-3g, construct a slug using the rules in [references/triage-file-reference.md](references/triage-file-reference.md). Before adding a finding to the internal summary, check if its slug matches any entry in the `false_positives` list. If matched, silently suppress the finding. Track suppressed findings separately — they will be reported as a summary count in Phase 7.

### 3a. Project Identity
- Read README for project description
- Read the primary build/config file for name, version, description

### 3b. Languages and Build System
Glob for build files to identify the tech stack: `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `setup.py`, `requirements.txt`, `pom.xml`, `build.gradle`, `CMakeLists.txt`, `Makefile`, `Dockerfile`, `*.csproj`, `Gemfile`.

Count files by extension:
```
git ls-files | grep -oE '\.[^.]+$' | sort | uniq -c | sort -rn | head -15
```

### 3c. Dependency Analysis
Read dependency manifests for security-relevant libraries:
- **Crypto:** openssl, ring, rustls, cryptography, bcrypt, argon2, jose, jwt
- **Auth:** passport, oauth2, oidc, keycloak, auth0, saml, ldap
- **Web/API:** express, flask, django, fastapi, actix-web, gin, spring
- **Database:** pg, mysql, mongodb, redis, sqlalchemy, diesel, prisma
- **Serialization:** protobuf, grpc, msgpack, pickle, yaml, serde

### 3d. Interface and Exposure Analysis
Grep for how the software interfaces with the outside world:
- **HTTP routes:** `@app\.(get|post|put|delete)`, `router\.(get|post)`, `HandleFunc`, `@(Get|Post)Mapping`, `@route`, `@api_view`
- **gRPC:** `service\s+\w+\s*\{`, `.proto` files, `RegisterServiceServer`
- **Network listeners:** `\.listen\(`, `net\.Listen`, `EXPOSE\s+\d+`, `TcpListener`, `socket\(`
- **CLI parsing:** `argparse`, `cobra\.Command`, `clap::`, `flag\.String`, `@click`, `yargs`
- **File input:** `open\(`, `read_file`, `fs\.readFile`, `io\.ReadAll`, `fopen`

### 3e. Data Handling and Storage
Grep for data handling patterns:
- **DB connections:** `DATABASE_URL`, `connection_string`, `createPool`, `sql\.Open`, `mongoose\.connect`
- **Env var secrets:** `SECRET`, `API_KEY`, `TOKEN`, `PASSWORD`, `CREDENTIALS`
- **Encryption:** `encrypt`, `decrypt`, `hash`, `hmac`, `sha256`, `aes`, `bcrypt`, `sign\(`, `verify\(`

### 3f. Authentication and Authorization
Grep for auth patterns:
- **Auth handlers:** `authenticate`, `authorize`, `requireAuth`, `@login_required`, `jwt\.verify`, `passport\.authenticate`
- **RBAC:** `role`, `permission`, `has_perm`, `@PreAuthorize`, `policy`, `acl`
- **Sessions:** `session`, `cookie`, `csrf`, `bearer`, `refresh_token`

### 3g. Security Configuration
Grep for: `cors`, `Access-Control-Allow`, `tls`, `ssl`, `certificate`, `rate_limit`, `throttle`, `validate`, `sanitize`, `helmet`, `Content-Security-Policy`, `audit`, `security_log`.

### 3h. Internal Summary
Compile (do NOT output to user yet): primary languages, software type, key interfaces, security-relevant dependencies, auth mechanisms (or absence), data sensitivity, attack surface.

Also compile the Service Exposure Classification signals for Phase 3i (program class, release type/audience, deployment environment, exposure, data sensitivity, operational role, regulatory scope) — see [references/service-exposure-classification.md](references/service-exposure-classification.md).

If triage filtering was active, also compile:
- Count of findings suppressed by the triage file, broken down by sub-step
- List of new (untriaged) findings not present in the triage file

### 3i. Classification (Repository + Service)
Determine two independent classifications, each via infer-then-always-confirm, each persisted to `.security-triage.yaml` (Phase 7c); neither is a vulnerability severity. If a block was loaded in Phase 1, offer **reuse** vs **re-classify** and carry it forward on reuse.

**Part A — Repository Exposure Classification (repo visibility).** Determine FIRST; it gates how much detail the document may contain. Detect `Internal` vs `Public` from the `origin` remote (Phase 0): internal/self-managed host → Internal; `github.com` → `gh repo view --json visibility`; `gitlab.com` → `glab repo view --json visibility` (or `glab api`); map public→Public and private/internal→Internal; if the CLI is unavailable or visibility is undetermined, ask and default to `Public` until confirmed. Confirm with the user; if `Public`/`Not determined`, apply the redaction policy to **all** Phase 4 output. See [references/repository-exposure-classification.md](references/repository-exposure-classification.md).

**Part B — Service Exposure Classification (service tier).** Infer a tier (`External / Regulated`, `Internal-Sensitive`, `Internal-Isolated`, or `Not determined (low confidence)`) with confidence + basis from the 3h evidence and any TAVA, then present it and ask the user to confirm or override (override → confidence `high`). See [references/service-exposure-classification.md](references/service-exposure-classification.md).

Hold both for Phase 4 (lines + detail policy) and Phase 7c (persistence); note whether either is new or changed vs Phase 1.

## Phase 4: Synthesis and Generation

Read reference materials for template structure and style guidance:
- [references/security-md-template.md](references/security-md-template.md) for the template
- [references/repository-exposure-classification.md](references/repository-exposure-classification.md) for repo-visibility rules and the detail/redaction policy
- [references/service-exposure-classification.md](references/service-exposure-classification.md) for the Service Exposure Classification rules and output format
- [references/examples/nemoclaw-example.md](references/examples/nemoclaw-example.md) for focused style
- [references/examples/openclaw-example.md](references/examples/openclaw-example.md) for comprehensive style

**Content detail policy:** If the Phase 3i Repository Exposure Classification is `Public` (or `Not determined`), write every section below for public consumption per the redaction policy in [references/repository-exposure-classification.md](references/repository-exposure-classification.md) (suppress internal hosts/IPs/URLs, internal names/codenames, ticket/finding IDs, internal jargon, and exploit/PoC specifics). If `Internal`, full detail is permitted.

Generate each required section:

### 4a. Reporting a Vulnerability (REQUIRED)

Include three NVIDIA reporting channels:
1. **NVIDIA Vulnerability Disclosure Program** (preferred) - https://www.nvidia.com/en-us/security/
2. **Email** - psirt@nvidia.com with PGP key (https://www.nvidia.com/en-us/security/pgp-key)
3. **GitHub/GitLab Private Vulnerability Reporting** via the repo Security tab

Include: "do not open a public issue" warning, required report fields (product/version, vulnerability type, repro steps, PoC, impact), PSIRT response process.

### 4b. Security Architecture & Context (REQUIRED)

Derive from Phase 3: project description, software classification (Application / Service / Driver / Firmware / Library / CLI / SDK), primary security responsibility, key security boundaries and interfaces.

Also include both Phase 3i classification lines (formats in their references): **Repository Exposure Classification** (`Internal`/`Public` + basis; see [references/repository-exposure-classification.md](references/repository-exposure-classification.md)) and **Service Exposure Classification** (tier + confidence + basis; see [references/service-exposure-classification.md](references/service-exposure-classification.md)). Do not present the tiers as official labels or tie them to any internal classification system.

**Must be specific to this project.** Not generic boilerplate.

### 4c. Threat Model (REQUIRED)

Generate 3-7 threats from ACTUAL codebase analysis:
- Each threat must name specific components, interfaces, or code paths from Phase 3
- Include threats from auxiliary code (logging, telemetry, diagnostics, build scripts)
- Incorporate TAVA findings if provided
- Order by severity/likelihood
- Format: `**[Threat Name]:** [Specific scenario with named components]`

Do NOT use generic threats unless the code has patterns susceptible to them. Every threat must trace back to reconnaissance findings.

**Accepted risk filtering:** If `.security-triage.yaml` contains `accepted_risks` entries whose slugs start with `threat-`, check each generated threat's slug against those entries. For matched threats:
- Do NOT include them in the main numbered threat list
- Instead, collect them for an "Accepted Risks" subsection after the threat list
- Format the subsection as:
  ```
  ### Accepted Risks
  Previously triaged threats retained by team decision:
  - **[Threat Name]:** [description] — *Accepted ([date]): [reason]*
  ```

### 4d. Critical Security Assumptions (REQUIRED)

Derive from what the code does NOT protect against:
- Missing input validation at entry points (assumes caller validates)
- No TLS config (assumes trusted network or external TLS termination)
- No authentication (assumes pre-authenticated requests)
- Direct memory access (assumes hardware MMU functioning)
- Trusted upstream components without verification

**Accepted assumption filtering:** If `.security-triage.yaml` contains `accepted_risks` entries whose slugs start with `assumption-`, check each assumption's slug against those entries. For matched assumptions, append the acceptance note inline: `*(Accepted [date]: [reason])*`

### 4e. Optional Enhanced Sections

Add if the codebase warrants it: Supported Versions, Security Update Process, Scope/Out-of-Scope, Deployment Assumptions, Dependency Security, Trust Model, Accepted Risks (auto-populated from triage file).

## Phase 5: Gap Analysis (if existing SECURITY.md found)

Present a compliance table:

| Section | Status | Recommended Action |
|---------|--------|--------------------|
| Reporting Policy | Present / Missing / Incomplete | [specific recommendation] |
| Architecture Context | Present / Missing / Incomplete | [specific recommendation] |
| Threat Model | Present / Missing / Incomplete | [specific recommendation] |
| Critical Assumptions | Present / Missing / Incomplete | [specific recommendation] |

Ask the user:
1. **Replace** entirely with the new version
2. **Update** only missing/incomplete sections (preserve existing content)
3. **Show diff** of proposed changes before editing

## Phase 6: Write the File

1. Present the complete generated SECURITY.md for review
2. Ask for confirmation before writing
3. Write to `SECURITY.md` at the repo root (or same location as existing file)
4. Suggest next steps: review for accuracy, commit and open a PR, consider a security audit
5. If new untriaged findings exist from Phase 3 or Phase 4, **or** either Phase 3i classification (repository or service) is new or changed, proceed to Phase 7

## Phase 7: Triage New Findings

After SECURITY.md is written, review and triage new findings that are not yet in `.security-triage.yaml`.

### 7a. Present New Findings

Display a numbered table of all untriaged items from this run:

| # | Phase | Category | Finding | Status |
|---|-------|----------|---------|--------|
| 1 | 3e | Env var secrets | `TOKEN` matched in `src/config.py` | New |
| 2 | 3d | File input | `open(` matched in `utils/parser.py` | New |
| 3 | 4c | Threat | Injection via REST handler `/api/query` | New |

Also show summary stats:
- **Previously triaged:** N findings suppressed from triage file
- **New findings:** M items requiring triage below

If there are no new findings (all were previously triaged), report that. If either Phase 3i classification (repository or service) is new or changed, still run Phase 7c to persist it; otherwise skip to Phase 7d.

### 7b. Collect Triage Decisions

Ask the user:

> Review the new findings above. For each (or a subset), provide a triage decision:
> - **confirmed** — Real finding, keep it in SECURITY.md as-is
> - **false_positive** — Not a real issue (will be suppressed on next run)
> - **accepted_risk** — Real but accepted (will move to Accepted Risks on next run)
> - **skip** — Defer decision to a future run
>
> Respond with individual decisions (e.g., "1: false_positive, 2: confirmed, 3: accepted_risk")
> or apply one decision to all (e.g., "all: confirmed").

For each item triaged as `false_positive` or `accepted_risk`, also collect:
- **reason** (required): Why this decision was made
- **triaged_by** (required): Name or email of the person triaging

### 7c. Persist Triage Decisions

For items marked `false_positive` or `accepted_risk`:
1. Construct the slug per [references/triage-file-reference.md](references/triage-file-reference.md)
2. If `.security-triage.yaml` exists, read it and append new entries to the appropriate list
3. If it does not exist, create it with the schema header (`version`, `project`, `last_updated`)
4. Update the `last_updated` timestamp
5. Write the file to the repo root
6. Present a summary of what was persisted

If either Phase 3i classification is new or changed, also write/update its block per [references/triage-file-reference.md](references/triage-file-reference.md):
- `repository_exposure_classification` (`visibility`, `basis`, `confirmed_by`, `date`)
- `service_exposure_classification` (`tier`, `confidence`, `basis`, `confirmed_by`, `date`)

Create `.security-triage.yaml` with the schema header if it does not yet exist. Do this even when there are no finding decisions to persist.

Items marked `confirmed` or `skip` are not written to the triage file. Confirmed findings remain in SECURITY.md as-is. Skipped items will reappear as new findings on the next run.

### 7d. Suggest Next Steps

- If triage decisions were saved, suggest committing `.security-triage.yaml` alongside `SECURITY.md`
- Note that the triage file should be checked into version control so decisions persist across the team
- Remind the user they can manually edit `.security-triage.yaml` to adjust decisions later

## Important Guidelines

- **Be specific, not generic.** Every section must reflect THIS project; name real files, modules, APIs, or interfaces.
- **Don't invent.** If reconnaissance reveals no pattern, note the absence as an assumption or risk; scale depth to the actual attack surface.
- **Preserve good content.** Keep existing sections that are well-written.
- **Respect triage decisions.** Never re-report a triaged false positive; show accepted risks in their subsection, not the main threat list.
- **Stable slugs.** Construct triage slugs exactly per [references/triage-file-reference.md](references/triage-file-reference.md) — inconsistent slugs break the feedback loop.
