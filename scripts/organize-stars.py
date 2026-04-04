#!/usr/bin/env python3
"""
organize-stars.py — Classify newly starred GitHub repos into lists.

Usage:
    python3 organize-stars.py           # process only unclassified repos
    python3 organize-stars.py --all     # re-process all starred repos
    python3 organize-stars.py --dry-run # preview without making changes

Requirements:
    - GitHub CLI (`gh`) installed and authenticated
    - Token needs 'user' scope: gh auth refresh --scopes user
"""

import argparse
import json
import subprocess
import sys


# ---------------------------------------------------------------------------
# Manual classification overrides — add entries here when auto-classify
# gets something wrong. Key = lowercase "owner/repo".
# ---------------------------------------------------------------------------
MANUAL = {
    "felax/spellactivationoverlaytextures": "World of Warcraft",
    "app-auto-patch/app-auto-patch":        "macOS / Apple Admin",
    "testdasi/grafana-unraid-stack":        "Self-hosted / Homelab",
    "community-scripts/proxmoxve":          "Self-hosted / Homelab",
    "itflow-org/itflow":                    "Self-hosted / Homelab",
    "99designs/aws-vault":                  "DevOps / Infrastructure",
    "kamranahmedse/aws-cost-cli":           "DevOps / Infrastructure",
    "thomaskur/m365documentation":          "Intune / Microsoft 365",
    "locus313/notebook":                    "Notes / Knowledge Base",
    "christianlempa/cheat-sheets":          "Notes / Knowledge Base",
    "locus313/cheat-sheets":               "Notes / Knowledge Base",
    "twpayne/chezmoi":                      "Dotfiles / Config",
    "wei/pull":                             "DevOps / Infrastructure",
    "gam-team/gam":                         "CLI Tools",
    "googlecontainertools/distroless":      "DevOps / Infrastructure",
    "kdemaria/kometa-config":               "Gaming / Game Servers",
    "boredazfcuk/docker-icloudpd":          "macOS / Apple Admin",
    "macadmins/sofa":                       "macOS / Apple Admin",
    "root3nl/supportapp":                   "macOS / Apple Admin",
    "dhowett/framework-laptop-kmod":        "Linux / Desktop",
    "neutrinolabs/xrdp":                    "Linux / Desktop",
    "ibm/mac-ibm-migration-tool":           "macOS / Apple Admin",
    "webadderall/recordly":                 "macOS / Apple Admin",
    "jaredc01/labstack-rack":              "Self-hosted / Homelab",
    "stirling-tools/stirling-pdf":          "Self-hosted / Homelab",
    "punk-security/dnsreaper":              "Security",
    "elder-plinius/l1b3rt4s":              "AI / ML",
    "beyondtrust/bedrock-keys-security":    "Security",
    "dmno-dev/varlock":                     "Security",
    "androz2091/backups-bot":               "Miscellaneous",
    "androz2091/discord-backup":            "Miscellaneous",
    "locus313/ssh-key-sync":               "DevOps / Infrastructure",
    "locus313/github-api-scripts":         "DevOps / Infrastructure",
    "plesk/centos2alma":                    "DevOps / Infrastructure",
    "architecpoint/plesk-scripts":          "DevOps / Infrastructure",
    "reviewdog/action-tflint":              "DevOps / Infrastructure",
    "levelrmm/scripts":                     "Miscellaneous",
    "antirez/aocla":                        "Miscellaneous",
    "prowler-cloud/prowler":                "Security",
    "anchore/grype":                        "Security",
    "basecamp/omarchy":                     "Linux / Desktop",
    "coollabsio/coolify":                   "Self-hosted / Homelab",
    "mitchmac/serverlesswp":               "Static Sites / Blogs",
    "basecamp/kamal":                       "Ruby",
    "basecamp/once-campfire":               "Ruby",
    "siderolabs/omni":                      "DevOps / Infrastructure",
    "goharbor/harbor":                      "DevOps / Infrastructure",
    "nwesterhausen/domain-monitor":         "CLI Tools",
    "bootc-dev/bootc":                      "Linux / Desktop",
    "ublue-os/bazzite":                     "Gaming / Game Servers",
    "simplecontainer/smr":                  "DevOps / Infrastructure",
    "zecrypt-io/zecrypt-server":            "Self-hosted / Homelab",
    "nicotsx/zerobyte":                     "Self-hosted / Homelab",
    "sharkord/sharkord":                    "Self-hosted / Homelab",
    "rackulalives/rackula":                 "Self-hosted / Homelab",
    "teifun2/cs-unifi-bouncer":             "Tailscale / Networking",
    "rtk-ai/rtk":                           "AI / ML",
    "onyx-dot-app/onyx":                    "AI / ML",
    "mintoolkit/mint":                      "DevOps / Infrastructure",
    "rustfs/rustfs":                        "Rust",
    "aws-samples/aws-health-aware":         "DevOps / Infrastructure",
    "scalecomputing/terraform-provider-hypercore": "DevOps / Infrastructure",
    "kestra-io/kestra":                     "DevOps / Infrastructure",
    "openobserve/openobserve":              "DevOps / Infrastructure",
    "tibixdev/winboat":                     "Windows Tools",
    "makeplane/plane":                      "Self-hosted / Homelab",
    "logtide-dev/logtide":                  "DevOps / Infrastructure",
    "xpipe-io/xpipe":                       "DevOps / Infrastructure",
    "patchmon/patchmon":                    "DevOps / Infrastructure",
    "newtechweb/infra-gitops":              "DevOps / Infrastructure",
    "architecpoint/infra-gitops":           "DevOps / Infrastructure",
    "owenthereal/upterm":                   "CLI Tools",
    "trparky/bitwarden-vault-export-script": "Windows Tools",
    "rnbwkat/presents":                     "Miscellaneous",
    "francescobori/ngx-page-object-model":  "Miscellaneous",
    "locus313/misc-linux-scripts":          "Linux / Desktop",
    "pgsty/pigsty":                         "Self-hosted / Homelab",
    "corentiinth/enclosed":                 "Self-hosted / Homelab",
    "raidowl/homelab-hub":                  "Self-hosted / Homelab",
    "aws-solutions-library-samples/cloud-intelligence-dashboards-data-collection": "DevOps / Infrastructure",
    "mysteriumnetwork/node":               "Tailscale / Networking",
    "davidc/subnets":                      "Tailscale / Networking",
    "greenshot/greenshot":                 "Windows Tools",
    "apple/container":                      "macOS / Apple Admin",
    "kopia/kopia":                          "Self-hosted / Homelab",
    "miantiao-me/sink":                     "Self-hosted / Homelab",
    "asheroto/winget-install":              "Windows Tools",
}


# ---------------------------------------------------------------------------
# Primary classification
# ---------------------------------------------------------------------------
def primary_list(repo):
    name = repo["nameWithOwner"].lower()
    if name in MANUAL:
        return MANUAL[name]

    desc  = (repo["description"] or "").lower()
    lang  = repo["primaryLanguage"]["name"] if repo["primaryLanguage"] else ""
    topics = {t["topic"]["name"].lower() for t in repo["repositoryTopics"]["nodes"]}

    def t_in(*kws):  return any(k in topics for k in kws)
    def t_has(*kws): return any(k in t for k in kws for t in topics)
    def n(*kws):     return any(k in name for k in kws)
    def d(*kws):     return any(k in desc for k in kws)

    if t_in("azerothcore", "wow", "world-of-warcraft", "trinitycore", "mangos", "wotlk",
             "azerothcore-module", "azerothcore-lua", "azerothcore-tools", "mmorpg-server") or \
       n("azerothcore", "wotlk", "chromiecraft") or \
       d("world of warcraft", "azerothcore", "wow private server"):
        return "World of Warcraft"

    if t_in("intune", "m365", "microsoft-365", "microsoft365", "entra", "azuread",
             "office365", "microsoft-endpoint-manager") or \
       t_has("intune", "microsoft365", "microsoft-365") or \
       n("intune", "cipp", "maester", "wintuner", "intunecd", "intuneget",
         "intunemonitoring", "entraexporter", "monkey365") or \
       d("intune", "microsoft 365", "endpoint manager"):
        return "Intune / Microsoft 365"

    if t_in("tailscale", "headscale", "zerotier", "wireguard") or \
       n("tailscale", "headscale", "zerotier", "ionscale", "tsflow", "golink") or \
       d("tailscale", "headscale"):
        return "Tailscale / Networking"

    if t_in("macos", "apple", "jamf", "mdm", "macadmin", "enrollment") or \
       t_has("jamf-pro", "jamf-school", "swiftdialog", "macadmin") or \
       n("setup-your-mac", "installomator", "macjutsu", "desktoppr", "macos-") or \
       d("macos", "jamf"):
        return "macOS / Apple Admin"

    if t_in("security", "cybersecurity", "osint", "phishing", "gitleaks",
             "spam-filter", "spam-filtering", "dmarc", "orgleaks", "threat-hunting",
             "reconnaissance") or \
       t_has("phishing-detection", "certificate-transparency", "spam-detection",
             "security-tools", "threat-hunting") or \
       n("orgleaks", "gitleaks", "testssl", "parsedmarc", "domainthreat", "certthreat",
         "rspamd", "mta-sts", "certmate") or \
       d("dmarc", "spam filter", "phishing detection", "certificate transparency",
         "secrets scanning"):
        return "Security"

    if t_in("ai", "llm", "mcp", "ollama", "openai") or \
       t_has("machine-learning", "artificial-intelligence", "prompt-engineering",
             "github-copilot", "large-language-model", "deep-learning") or \
       n("open-webui", "awesome-mcp", "awesome-copilot", "copilot-metrics") or \
       d("large language model", "ai assistant", "machine learning"):
        return "AI / ML"

    if t_in("gaming", "game-server") or t_has("game-server") or \
       n("enshrouded", "minecraft", "game-server") or d("game server"):
        return "Gaming / Game Servers"

    if t_in("jekyll", "blog", "github-pages", "jamstack", "hugo") or \
       t_has("jekyll-theme", "jekyll-blog", "static-site", "jekyll-site") or \
       n("reverie", "chirpy") or d("jekyll theme", "static site", "blog theme"):
        return "Static Sites / Blogs"

    if t_in("notes", "obsidian", "wiki") or \
       t_has("knowledge-base", "cheat-sheet", "second-brain", "notebook") or \
       n("obsidian", "notebook") or d("cheat sheet", "knowledge base", "note-taking"):
        return "Notes / Knowledge Base"

    SELFHOSTED = {"self-hosted", "selfhosted", "homelab", "self-hosting", "unraid",
                   "proxmox", "home-assistant", "lxc", "homelab-setup"}
    if any(t in topics for t in SELFHOSTED) or \
       any(s in name for s in ["uptime-kuma", "healthchecks", "homarr", "dockge",
                                "metube", "bitwarden/self-host", "nexterm", "kopia",
                                "resticprofile", "pangolin", "beszel", "n8n-io/n8n",
                                "checkcle", "wolnut", "komodo", "watchtower", "unpoller"]) or \
       d("self-host", " homelab", "home lab"):
        return "Self-hosted / Homelab"

    if t_in("dotfiles", "chezmoi") or n("dotfiles", "dotfile") or d("dotfiles"):
        return "Dotfiles / Config"

    DEVOPS = {"terraform", "ansible", "docker", "kubernetes", "ci", "cicd", "devops",
               "infrastructure", "packer", "github-actions", "infrastructure-as-code",
               "ops", "monitoring", "aws", "azure", "helm", "prometheus", "grafana",
               "checkmk", "vagrant"}
    if any(t in topics for t in DEVOPS) or lang in ("HCL", "Dockerfile", "YAML") or \
       t_has("terraform-provider", "ansible-role", "github-actions", "ci-cd") or \
       n("terraform", "ansible", "packer", "grafana", "checkmk", "check_mk",
         "check-mk", "infra-", "gitea") or \
       d("infrastructure as code", "devops", "terraform", "ansible"):
        return "DevOps / Infrastructure"

    if t_in("cli", "terminal") or t_has("command-line-tool", "command-line") or \
       d("command-line tool", "cli tool"):
        return "CLI Tools"

    if t_in("windows", "powershell", "rdp", "winget") or lang == "PowerShell" or \
       n("dockur/windows", "winapps") or d("windows tool", "powershell module"):
        return "Windows Tools"

    if t_in("linux", "desktop") or t_has("linux-desktop", "arch-linux", "fedora-linux") or \
       n("linux", "desktop"):
        return "Linux / Desktop"

    if lang == "PHP":   return "PHP"
    if lang == "Ruby":  return "Ruby"
    if lang == "Rust":  return "Rust"
    if lang == "Go":    return "Go"

    return "Miscellaneous"


# ---------------------------------------------------------------------------
# Secondary (additional) list membership
# ---------------------------------------------------------------------------
def secondary_lists(repo):
    name   = repo["nameWithOwner"].lower()
    desc   = (repo["description"] or "").lower()
    lang   = repo["primaryLanguage"]["name"] if repo["primaryLanguage"] else ""
    topics = {t["topic"]["name"].lower() for t in repo["repositoryTopics"]["nodes"]}

    def t_in(*kws):  return any(k in topics for k in kws)
    def t_has(*kws): return any(k in t for k in kws for t in topics)
    def n(*kws):     return any(k in name for k in kws)
    def d(*kws):     return any(k in desc for k in kws)

    extras = []

    if lang == "PowerShell":
        extras.append("PowerShell")

    if lang == "Python":
        extras.append("Python")

    if t_in("rspamd", "dmarc", "smartermail", "spam-filter", "spam-filtering",
             "spam-detection") or t_has("smartermail", "rspamd") or \
       n("rspamd", "smartermail", "parsedmarc", "smspamconfig", "mta-sts") or \
       d("smartermail", "rspamd", "spam", "dmarc", "mail server"):
        extras.append("Smartermail")

    if t_in("terraform") or t_has("terraform-provider", "terraform-module") or \
       n("terraform") or d("terraform"):
        extras.append("terraform")

    MONITORING_TOPICS = {"monitoring", "observability", "prometheus", "grafana",
                          "influxdb", "telegraf", "loki", "alerting", "uptime",
                          "metrics", "logs", "traces"}
    MONITORING_NAMES  = ["uptime-kuma", "healthchecks", "beszel", "checkcle",
                          "openobserve", "grafana", "check_mk", "check-mk",
                          "checkmk", "unpoller", "patchmon"]
    if any(t in topics for t in MONITORING_TOPICS) or \
       any(s in name for s in MONITORING_NAMES) or \
       d("monitoring", "observability", "metrics collection", "uptime monitoring"):
        extras.append("Monitoring")

    GITHUB_NAMES = ["github-api-scripts", "github-misc-scripts",
                     "get-user-teams-membership", "wei/pull",
                     "myoung34/docker-github-actions-runner",
                     "azerothcore/github-azerothcore",
                     "thecybermafia/orgleaks", "locus313/github-api-scripts",
                     "joshjohanning/github-misc-scripts",
                     "chrisanthropic/terraform-import-github-organization",
                     "locus313/terraform-import-github-organization",
                     "copilot-metrics-viewer", "awesome-copilot"]
    if any(s in name for s in GITHUB_NAMES) or t_in("github", "github-actions") or \
       t_has("github-api", "github-actions", "probot") or \
       d("github api", "github actions", "github organization"):
        extras.append("github")

    AWS_NAMES = ["terraform-provider-aws", "aws-vault", "aws-cost-cli",
                  "cloud-intelligence-dashboards", "aws-health-aware",
                  "terraform-aws", "terraform-module-aws", "leapp"]
    if any(s in name for s in AWS_NAMES) or t_in("aws") or \
       t_has("aws-cost", "aws-vault", "amazon-web-services") or \
       d("aws", "amazon web services"):
        extras.append("AWS")

    return extras


# ---------------------------------------------------------------------------
# GitHub API helpers
# ---------------------------------------------------------------------------
def run_graphql(query, extra_args=None):
    cmd = ["gh", "api", "graphql", "-f", f"query={query}"]
    if extra_args:
        cmd += extra_args
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"ERROR: {r.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    data = json.loads(r.stdout)
    if "errors" in data:
        print(f"GraphQL ERROR: {data['errors']}", file=sys.stderr)
        sys.exit(1)
    return data["data"]


def fetch_lists():
    """Return dict: list_name -> list_id, and set of repo IDs already in any list."""
    data = run_graphql("""{
      viewer {
        lists(first: 50) {
          nodes {
            id
            name
            items(first: 100) {
              nodes { ... on Repository { id } }
            }
          }
        }
      }
    }""")
    lists_by_name = {}
    classified_ids = set()
    for lst in data["viewer"]["lists"]["nodes"]:
        lists_by_name[lst["name"]] = lst["id"]
        for item in lst["items"]["nodes"]:
            if "id" in item:
                classified_ids.add(item["id"])
    return lists_by_name, classified_ids


def fetch_all_starred():
    """Return list of all starred repo objects."""
    repos = []
    cursor = None
    while True:
        after = f', after: "{cursor}"' if cursor else ""
        data = run_graphql(f"""{{
          viewer {{
            starredRepositories(first: 100{after}) {{
              nodes {{
                id
                nameWithOwner
                description
                primaryLanguage {{ name }}
                repositoryTopics(first: 15) {{
                  nodes {{ topic {{ name }} }}
                }}
              }}
              pageInfo {{ hasNextPage endCursor }}
            }}
          }}
        }}""")
        page = data["viewer"]["starredRepositories"]
        repos.extend(page["nodes"])
        if not page["pageInfo"]["hasNextPage"]:
            break
        cursor = page["pageInfo"]["endCursor"]
    return repos


def set_lists(repo_id, list_ids, dry_run=False):
    if dry_run:
        return True
    mutation = """
mutation($itemId: ID!, $listIds: [ID!]!) {
  updateUserListsForItem(input: {itemId: $itemId, listIds: $listIds}) {
    lists { name }
  }
}"""
    args = ["-F", f"itemId={repo_id}"]
    for lid in list_ids:
        args += ["-F", f"listIds[]={lid}"]
    r = subprocess.run(
        ["gh", "api", "graphql", "-f", f"query={mutation}"] + args,
        capture_output=True, text=True
    )
    if r.returncode != 0 or '"errors"' in r.stdout:
        return False
    return True


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Organize starred GitHub repos into lists.")
    parser.add_argument("--all",     action="store_true", help="Re-process all stars, not just new ones")
    parser.add_argument("--dry-run", action="store_true", help="Preview changes without applying them")
    args = parser.parse_args()

    print("Fetching your lists...", end=" ", flush=True)
    lists_by_name, classified_ids = fetch_lists()
    print(f"found {len(lists_by_name)} lists, {len(classified_ids)} repos already classified")

    print("Fetching starred repos...", end=" ", flush=True)
    all_repos = fetch_all_starred()
    print(f"found {len(all_repos)} starred repos")

    # Filter to only unclassified unless --all
    to_process = all_repos if args.all else [r for r in all_repos if r["id"] not in classified_ids]
    print(f"\n{'Re-processing all' if args.all else 'New/unclassified'}: {len(to_process)} repos\n")

    if not to_process:
        print("Nothing to do — all starred repos are already in lists.")
        return

    success = errors = skipped = 0

    for repo in to_process:
        name = repo["nameWithOwner"]
        prim = primary_list(repo)
        secs = secondary_lists(repo)

        prim_id = lists_by_name.get(prim)
        if not prim_id:
            print(f"  ? {name:<52} → '{prim}' (list not found, skipping)")
            skipped += 1
            continue

        all_ids = list(dict.fromkeys(
            [prim_id] + [lists_by_name[s] for s in secs if s in lists_by_name]
        ))
        lists_str = prim + (f" + {', '.join(secs)}" if secs else "")

        if args.dry_run:
            print(f"  → {name:<52} [{lists_str}]")
            success += 1
        else:
            ok = set_lists(repo["id"], all_ids)
            marker = "✓" if ok else "✗"
            print(f"  {marker} {name:<52} [{lists_str}]")
            if ok: success += 1
            else:  errors += 1

    print(f"\n{'[DRY RUN] ' if args.dry_run else ''}Done: {success} classified"
          + (f", {errors} failed" if errors else "")
          + (f", {skipped} skipped (list not found)" if skipped else ""))
    if args.dry_run:
        print("Run without --dry-run to apply changes.")


if __name__ == "__main__":
    main()
