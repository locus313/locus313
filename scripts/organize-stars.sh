#!/usr/bin/env bash
# organize-stars.sh — Classify newly starred GitHub repos into lists.
#
# Usage:
#   ./scripts/organize-stars.sh           # process only unclassified repos
#   ./scripts/organize-stars.sh --all     # re-process all starred repos
#   ./scripts/organize-stars.sh --dry-run # preview without making changes
#
# Requirements:
#   - GitHub CLI (gh) authenticated with 'user' scope
#     Run: gh auth refresh --scopes user
#   - jq installed

set -uo pipefail

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
DRY_RUN=false
PROCESS_ALL=false

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --all)     PROCESS_ALL=true ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--all] [--dry-run]"
            echo "  --all      Re-process all starred repos (default: new/unclassified only)"
            echo "  --dry-run  Preview changes without applying them"
            exit 0 ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------
for cmd in gh jq; do
    command -v "$cmd" &>/dev/null || { echo "ERROR: '$cmd' is required but not found"; exit 1; }
done

# ---------------------------------------------------------------------------
# Manual overrides  (lowercase owner/repo -> list name)
# Add entries here when auto-classify gets something wrong.
# ---------------------------------------------------------------------------
declare -A MANUAL=(
    ["felax/spellactivationoverlaytextures"]="World of Warcraft"
    ["app-auto-patch/app-auto-patch"]="macOS / Apple Admin"
    ["testdasi/grafana-unraid-stack"]="Self-hosted / Homelab"
    ["community-scripts/proxmoxve"]="Self-hosted / Homelab"
    ["itflow-org/itflow"]="Self-hosted / Homelab"
    ["99designs/aws-vault"]="DevOps / Infrastructure"
    ["kamranahmedse/aws-cost-cli"]="DevOps / Infrastructure"
    ["thomaskur/m365documentation"]="Intune / Microsoft 365"
    ["locus313/notebook"]="Notes / Knowledge Base"
    ["christianlempa/cheat-sheets"]="Notes / Knowledge Base"
    ["locus313/cheat-sheets"]="Notes / Knowledge Base"
    ["twpayne/chezmoi"]="Dotfiles / Config"
    ["wei/pull"]="DevOps / Infrastructure"
    ["gam-team/gam"]="CLI Tools"
    ["googlecontainertools/distroless"]="DevOps / Infrastructure"
    ["kdemaria/kometa-config"]="Gaming / Game Servers"
    ["boredazfcuk/docker-icloudpd"]="macOS / Apple Admin"
    ["macadmins/sofa"]="macOS / Apple Admin"
    ["root3nl/supportapp"]="macOS / Apple Admin"
    ["dhowett/framework-laptop-kmod"]="Linux / Desktop"
    ["neutrinolabs/xrdp"]="Linux / Desktop"
    ["ibm/mac-ibm-migration-tool"]="macOS / Apple Admin"
    ["webadderall/recordly"]="macOS / Apple Admin"
    ["jaredc01/labstack-rack"]="Self-hosted / Homelab"
    ["stirling-tools/stirling-pdf"]="Self-hosted / Homelab"
    ["punk-security/dnsreaper"]="Security"
    ["elder-plinius/l1b3rt4s"]="AI / ML"
    ["beyondtrust/bedrock-keys-security"]="Security"
    ["dmno-dev/varlock"]="Security"
    ["androz2091/backups-bot"]="Miscellaneous"
    ["androz2091/discord-backup"]="Miscellaneous"
    ["locus313/ssh-key-sync"]="DevOps / Infrastructure"
    ["locus313/github-api-scripts"]="DevOps / Infrastructure"
    ["plesk/centos2alma"]="DevOps / Infrastructure"
    ["architecpoint/plesk-scripts"]="DevOps / Infrastructure"
    ["reviewdog/action-tflint"]="DevOps / Infrastructure"
    ["levelrmm/scripts"]="Miscellaneous"
    ["antirez/aocla"]="Miscellaneous"
    ["prowler-cloud/prowler"]="Security"
    ["anchore/grype"]="Security"
    ["basecamp/omarchy"]="Linux / Desktop"
    ["coollabsio/coolify"]="Self-hosted / Homelab"
    ["mitchmac/serverlesswp"]="Static Sites / Blogs"
    ["basecamp/kamal"]="Ruby"
    ["basecamp/once-campfire"]="Ruby"
    ["siderolabs/omni"]="DevOps / Infrastructure"
    ["goharbor/harbor"]="DevOps / Infrastructure"
    ["nwesterhausen/domain-monitor"]="CLI Tools"
    ["bootc-dev/bootc"]="Linux / Desktop"
    ["ublue-os/bazzite"]="Gaming / Game Servers"
    ["simplecontainer/smr"]="DevOps / Infrastructure"
    ["zecrypt-io/zecrypt-server"]="Self-hosted / Homelab"
    ["nicotsx/zerobyte"]="Self-hosted / Homelab"
    ["sharkord/sharkord"]="Self-hosted / Homelab"
    ["rackulalives/rackula"]="Self-hosted / Homelab"
    ["teifun2/cs-unifi-bouncer"]="Tailscale / Networking"
    ["rtk-ai/rtk"]="AI / ML"
    ["onyx-dot-app/onyx"]="AI / ML"
    ["mintoolkit/mint"]="DevOps / Infrastructure"
    ["rustfs/rustfs"]="Rust"
    ["aws-samples/aws-health-aware"]="DevOps / Infrastructure"
    ["scalecomputing/terraform-provider-hypercore"]="DevOps / Infrastructure"
    ["kestra-io/kestra"]="DevOps / Infrastructure"
    ["openobserve/openobserve"]="DevOps / Infrastructure"
    ["tibixdev/winboat"]="Windows Tools"
    ["makeplane/plane"]="Self-hosted / Homelab"
    ["logtide-dev/logtide"]="DevOps / Infrastructure"
    ["xpipe-io/xpipe"]="DevOps / Infrastructure"
    ["patchmon/patchmon"]="DevOps / Infrastructure"
    ["newtechweb/infra-gitops"]="DevOps / Infrastructure"
    ["architecpoint/infra-gitops"]="DevOps / Infrastructure"
    ["owenthereal/upterm"]="CLI Tools"
    ["trparky/bitwarden-vault-export-script"]="Windows Tools"
    ["rnbwkat/presents"]="Miscellaneous"
    ["francescobori/ngx-page-object-model"]="Miscellaneous"
    ["locus313/misc-linux-scripts"]="Linux / Desktop"
    ["pgsty/pigsty"]="Self-hosted / Homelab"
    ["corentiinth/enclosed"]="Self-hosted / Homelab"
    ["raidowl/homelab-hub"]="Self-hosted / Homelab"
    ["aws-solutions-library-samples/cloud-intelligence-dashboards-data-collection"]="DevOps / Infrastructure"
    ["mysteriumnetwork/node"]="Tailscale / Networking"
    ["davidc/subnets"]="Tailscale / Networking"
    ["greenshot/greenshot"]="Windows Tools"
    ["apple/container"]="macOS / Apple Admin"
    ["kopia/kopia"]="Self-hosted / Homelab"
    ["miantiao-me/sink"]="Self-hosted / Homelab"
    ["asheroto/winget-install"]="Windows Tools"
)

# ---------------------------------------------------------------------------
# Globals set per-repo before calling classify functions
# ---------------------------------------------------------------------------
_NAME=""    # lowercase nameWithOwner
_DESC=""    # lowercase description
_LANG=""    # primary language name
_TOPICS=""  # newline-separated lowercase topic names

# ---------------------------------------------------------------------------
# Matching helpers — no subshells, fast bash builtins only
# ---------------------------------------------------------------------------

# Exact topic membership (safe for short words like 'ai', 'ml')
topic_in() {
    local kw
    for kw in "$@"; do
        [[ $'\n'"${_TOPICS}"$'\n' == *$'\n'"${kw}"$'\n'* ]] && return 0
    done
    return 1
}

# Topic substring match (only use for long/distinctive keywords)
topic_has() {
    local kw
    for kw in "$@"; do
        [[ "${_TOPICS}" == *"${kw}"* ]] && return 0
    done
    return 1
}

name_has() {
    local kw
    for kw in "$@"; do
        [[ "${_NAME}" == *"${kw}"* ]] && return 0
    done
    return 1
}

desc_has() {
    local kw
    for kw in "$@"; do
        [[ "${_DESC}" == *"${kw}"* ]] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Primary classification — one list per repo
# ---------------------------------------------------------------------------
classify_primary() {
    [[ -v MANUAL["${_NAME}"] ]] && { echo "${MANUAL[${_NAME}]}"; return; }

    if topic_in "azerothcore" "wow" "world-of-warcraft" "trinitycore" "mangos" "wotlk" \
                "azerothcore-module" "azerothcore-lua" "azerothcore-tools" "mmorpg-server" \
       || name_has "azerothcore" "wotlk" "chromiecraft" \
       || desc_has "world of warcraft" "azerothcore" "wow private server"; then
        echo "World of Warcraft"; return; fi

    if topic_in "intune" "m365" "microsoft-365" "microsoft365" "entra" "azuread" \
                "office365" "microsoft-endpoint-manager" \
       || topic_has "intune" "microsoft365" "microsoft-365" \
       || name_has "intune" "cipp" "maester" "wintuner" "intunecd" "intuneget" \
                   "intunemonitoring" "entraexporter" "monkey365" \
       || desc_has "intune" "microsoft 365" "endpoint manager"; then
        echo "Intune / Microsoft 365"; return; fi

    if topic_in "tailscale" "headscale" "zerotier" "wireguard" \
       || name_has "tailscale" "headscale" "zerotier" "ionscale" "tsflow" "golink" \
       || desc_has "tailscale" "headscale"; then
        echo "Tailscale / Networking"; return; fi

    if topic_in "macos" "apple" "jamf" "mdm" "macadmin" "enrollment" \
       || topic_has "jamf-pro" "jamf-school" "swiftdialog" "macadmin" \
       || name_has "setup-your-mac" "installomator" "macjutsu" "desktoppr" "macos-" \
       || desc_has "macos" "jamf"; then
        echo "macOS / Apple Admin"; return; fi

    if topic_in "security" "cybersecurity" "osint" "phishing" "gitleaks" \
                "spam-filter" "spam-filtering" "dmarc" "orgleaks" "threat-hunting" "reconnaissance" \
       || topic_has "phishing-detection" "certificate-transparency" "spam-detection" \
                    "security-tools" "threat-hunting" \
       || name_has "orgleaks" "gitleaks" "testssl" "parsedmarc" "domainthreat" "certthreat" \
                   "rspamd" "mta-sts" "certmate" \
       || desc_has "dmarc" "spam filter" "phishing detection" "certificate transparency" \
                   "secrets scanning"; then
        echo "Security"; return; fi

    # Use topic_in (not topic_has) for short words 'ai' and 'ml' to avoid false matches
    if topic_in "ai" "llm" "mcp" "ollama" "openai" \
       || topic_has "machine-learning" "artificial-intelligence" "prompt-engineering" \
                    "github-copilot" "large-language-model" "deep-learning" \
       || name_has "open-webui" "awesome-mcp" "awesome-copilot" "copilot-metrics" \
       || desc_has "large language model" "ai assistant" "machine learning"; then
        echo "AI / ML"; return; fi

    if topic_in "gaming" "game-server" \
       || topic_has "game-server" \
       || name_has "enshrouded" "minecraft" "game-server" \
       || desc_has "game server"; then
        echo "Gaming / Game Servers"; return; fi

    if topic_in "jekyll" "blog" "github-pages" "jamstack" "hugo" \
       || topic_has "jekyll-theme" "jekyll-blog" "static-site" "jekyll-site" \
       || name_has "reverie" "chirpy" \
       || desc_has "jekyll theme" "static site" "blog theme"; then
        echo "Static Sites / Blogs"; return; fi

    if topic_in "notes" "obsidian" "wiki" \
       || topic_has "knowledge-base" "cheat-sheet" "second-brain" "notebook" \
       || name_has "obsidian" "notebook" \
       || desc_has "cheat sheet" "knowledge base" "note-taking"; then
        echo "Notes / Knowledge Base"; return; fi

    if topic_in "self-hosted" "selfhosted" "homelab" "self-hosting" "unraid" \
                "proxmox" "home-assistant" "lxc" "homelab-setup" \
       || name_has "uptime-kuma" "healthchecks" "homarr" "dockge" "metube" \
                   "bitwarden/self-host" "nexterm" "kopia" "resticprofile" "pangolin" \
                   "beszel" "n8n-io/n8n" "checkcle" "wolnut" "komodo" "watchtower" "unpoller" \
       || desc_has "self-host" " homelab" "home lab"; then
        echo "Self-hosted / Homelab"; return; fi

    if topic_in "dotfiles" "chezmoi" \
       || name_has "dotfiles" "dotfile" \
       || desc_has "dotfiles"; then
        echo "Dotfiles / Config"; return; fi

    if topic_in "terraform" "ansible" "docker" "kubernetes" "ci" "cicd" "devops" \
                "infrastructure" "packer" "github-actions" "infrastructure-as-code" \
                "ops" "monitoring" "aws" "azure" "helm" "prometheus" "grafana" \
                "checkmk" "vagrant" \
       || [[ "${_LANG}" == "HCL" || "${_LANG}" == "Dockerfile" || "${_LANG}" == "YAML" ]] \
       || topic_has "terraform-provider" "ansible-role" "github-actions" "ci-cd" \
       || name_has "terraform" "ansible" "packer" "grafana" "checkmk" "check_mk" \
                   "check-mk" "infra-" "gitea" \
       || desc_has "infrastructure as code" "devops" "terraform" "ansible"; then
        echo "DevOps / Infrastructure"; return; fi

    if topic_in "cli" "terminal" \
       || topic_has "command-line-tool" "command-line" \
       || desc_has "command-line tool" "cli tool"; then
        echo "CLI Tools"; return; fi

    if topic_in "windows" "powershell" "rdp" "winget" \
       || [[ "${_LANG}" == "PowerShell" ]] \
       || name_has "dockur/windows" "winapps" \
       || desc_has "windows tool" "powershell module"; then
        echo "Windows Tools"; return; fi

    if topic_in "linux" "desktop" \
       || topic_has "linux-desktop" "arch-linux" "fedora-linux" \
       || name_has "linux" "desktop"; then
        echo "Linux / Desktop"; return; fi

    case "${_LANG}" in
        PHP)        echo "PHP";   return ;;
        Ruby)       echo "Ruby";  return ;;
        Rust)       echo "Rust";  return ;;
        Go)         echo "Go";    return ;;
    esac

    echo "Miscellaneous"
}

# ---------------------------------------------------------------------------
# Secondary classification — additional lists a repo can also appear in
# ---------------------------------------------------------------------------
classify_secondary() {
    [[ "${_LANG}" == "PowerShell" ]] && echo "PowerShell"
    [[ "${_LANG}" == "Python" ]]     && echo "Python"

    if topic_in "rspamd" "dmarc" "smartermail" "spam-filter" "spam-filtering" "spam-detection" \
       || topic_has "smartermail" "rspamd" \
       || name_has "rspamd" "smartermail" "parsedmarc" "smspamconfig" "mta-sts" \
       || desc_has "smartermail" "rspamd" "spam" "dmarc" "mail server"; then
        echo "Smartermail"; fi

    if topic_in "terraform" \
       || topic_has "terraform-provider" "terraform-module" \
       || name_has "terraform" \
       || desc_has "terraform"; then
        echo "terraform"; fi

    if topic_in "monitoring" "observability" "prometheus" "grafana" "influxdb" \
                "telegraf" "loki" "alerting" "uptime" "metrics" "logs" "traces" \
       || name_has "uptime-kuma" "healthchecks" "beszel" "checkcle" "openobserve" \
                   "grafana" "check_mk" "check-mk" "checkmk" "unpoller" "patchmon" \
       || desc_has "monitoring" "observability" "metrics collection" "uptime monitoring"; then
        echo "Monitoring"; fi

    if name_has "github-api-scripts" "github-misc-scripts" "get-user-teams-membership" \
                "wei/pull" "myoung34/docker-github-actions-runner" \
                "azerothcore/github-azerothcore" "thecybermafia/orgleaks" \
                "locus313/github-api-scripts" "joshjohanning/github-misc-scripts" \
                "terraform-import-github-organization" "copilot-metrics-viewer" "awesome-copilot" \
       || topic_in "github" "github-actions" \
       || topic_has "github-api" "github-actions" "probot" \
       || desc_has "github api" "github actions" "github organization"; then
        echo "github"; fi

    if name_has "terraform-provider-aws" "aws-vault" "aws-cost-cli" \
                "cloud-intelligence-dashboards" "aws-health-aware" \
                "terraform-aws" "terraform-module-aws" "leapp" \
       || topic_in "aws" \
       || topic_has "aws-cost" "aws-vault" "amazon-web-services" \
       || desc_has "aws" "amazon web services"; then
        echo "AWS"; fi
}

# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------
declare -A LIST_IDS        # list name  -> list ID
declare -A CLASSIFIED_IDS  # repo ID    -> 1

fetch_lists() {
    printf "Fetching your lists..." >&2
    local result
    result=$(gh api graphql -f query='{
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
    }')

    while IFS=$'\t' read -r lid lname; do
        LIST_IDS["${lname}"]="${lid}"
    done < <(echo "$result" | jq -r '.data.viewer.lists.nodes[] | (.id + "\t" + .name)')

    while read -r repo_id; do
        [[ -n "$repo_id" ]] && CLASSIFIED_IDS["$repo_id"]=1
    done < <(echo "$result" | jq -r '.data.viewer.lists.nodes[].items.nodes[] | select(has("id")) | .id')

    printf " %d lists, %d repos already classified\n" "${#LIST_IDS[@]}" "${#CLASSIFIED_IDS[@]}" >&2
}

STARRED_FILE=""
cleanup() { rm -f "${STARRED_FILE}"; }
trap cleanup EXIT

fetch_starred() {
    printf "Fetching starred repos..." >&2
    STARRED_FILE=$(mktemp)
    local cursor="" has_next="true" count=0

    while [[ "$has_next" == "true" ]]; do
        local after=""
        [[ -n "$cursor" ]] && after=", after: \"$cursor\""
        local result
        result=$(gh api graphql -f query="{
          viewer {
            starredRepositories(first: 100${after}) {
              nodes {
                id nameWithOwner description
                primaryLanguage { name }
                repositoryTopics(first: 15) { nodes { topic { name } } }
              }
              pageInfo { hasNextPage endCursor }
            }
          }
        }")
        echo "$result" | jq -c '.data.viewer.starredRepositories.nodes[]' >> "$STARRED_FILE"
        local n
        n=$(echo "$result" | jq '.data.viewer.starredRepositories.nodes | length')
        (( count += n ))
        has_next=$(echo "$result" | jq -r '.data.viewer.starredRepositories.pageInfo.hasNextPage')
        cursor=$(echo "$result" | jq -r '.data.viewer.starredRepositories.pageInfo.endCursor // ""')
    done

    printf " %d starred repos\n" "$count" >&2
}

apply_lists() {
    local repo_id="$1"; shift
    local args=("-F" "itemId=${repo_id}")
    local lid
    for lid in "$@"; do
        args+=("-F" "listIds[]=${lid}")
    done
    gh api graphql \
        -f query='mutation($itemId: ID!, $listIds: [ID!]!) {
          updateUserListsForItem(input: {itemId: $itemId, listIds: $listIds}) {
            lists { name }
          }
        }' \
        "${args[@]}" > /dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    fetch_lists
    fetch_starred

    local total=0 processed=0 success=0 errors=0 skipped=0

    while IFS= read -r repo_json; do
        (( ++total ))
        local repo_id
        repo_id=$(echo "$repo_json" | jq -r '.id')

        if [[ "$PROCESS_ALL" == "false" && -v CLASSIFIED_IDS["$repo_id"] ]]; then
            continue
        fi
        (( ++processed ))

        _NAME=$(echo "$repo_json" | jq -r '.nameWithOwner | ascii_downcase')
        _DESC=$(echo "$repo_json" | jq -r '.description // "" | ascii_downcase')
        _LANG=$(echo "$repo_json" | jq -r '.primaryLanguage.name // ""')
        _TOPICS=$(echo "$repo_json" | jq -r '.repositoryTopics.nodes[].topic.name | ascii_downcase')

        local prim prim_id
        prim=$(classify_primary)
        prim_id="${LIST_IDS["$prim"]-}"

        if [[ -z "$prim_id" ]]; then
            printf "  ? %-52s → '%s' (list not found)\n" \
                "$(echo "$repo_json" | jq -r '.nameWithOwner')" "$prim"
            (( ++skipped ))
            continue
        fi

        # Collect all list IDs (primary + secondary), deduplicated
        local -A seen=(["$prim_id"]=1)
        local all_ids=("$prim_id")
        local labels="$prim"
        while IFS= read -r sec; do
            [[ -z "$sec" ]] && continue
            local sec_id="${LIST_IDS["$sec"]-}"
            if [[ -n "$sec_id" && ! -v seen["$sec_id"] ]]; then
                all_ids+=("$sec_id")
                seen["$sec_id"]=1
                labels+=" + $sec"
            fi
        done < <(classify_secondary)

        local display_name
        display_name=$(echo "$repo_json" | jq -r '.nameWithOwner')

        if [[ "$DRY_RUN" == "true" ]]; then
            printf "  → %-52s [%s]\n" "$display_name" "$labels"
            (( ++success ))
        else
            if apply_lists "$repo_id" "${all_ids[@]}"; then
                printf "  ✓ %-52s [%s]\n" "$display_name" "$labels"
                (( ++success ))
            else
                printf "  ✗ %-52s\n" "$display_name"
                (( ++errors ))
            fi
        fi
    done < "$STARRED_FILE"

    printf "\n"
    if (( processed == 0 )); then
        printf "Nothing to do — all %d starred repos are already in lists.\n" "$total"
        return
    fi

    local prefix=""
    [[ "$DRY_RUN" == "true" ]] && prefix="[DRY RUN] "
    printf "%s%d/%d repos processed: %d classified" "$prefix" "$processed" "$total" "$success"
    (( errors > 0  )) && printf ", %d failed"  "$errors"
    (( skipped > 0 )) && printf ", %d skipped" "$skipped"
    printf "\n"
    [[ "$DRY_RUN" == "true" ]] && printf "Run without --dry-run to apply changes.\n"
}

main
