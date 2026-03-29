#!/usr/bin/env bash
# sthunt.sh — autonomous stego & web intelligence hunter
# Usage: sthunt.sh <url | image_file> [options]
#   -p, --pass PASSWORD     extra steghide password
#   -d, --depth N           crawl depth (default: 3)
#   -w, --wordlist FILE     stegseek wordlist (auto-detects rockyou)
#   --binwalk               run binwalk scan + auto-extract (off by default)
set -u

# ── colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YLW='\033[1;33m'; GRN='\033[0;32m'
CYN='\033[0;36m'; BLD='\033[1m'; RST='\033[0m'
DIM='\033[2m'

# ── display helpers ───────────────────────────────────────────────────────────
# Write to log file only — nothing on screen
log()    { printf '%b\n' "$*" >> "${REPORT:-/dev/null}"; }
banner() { printf '%b\n' "$*" >> "${REPORT:-/dev/null}"; }
info()   { printf '%b\n' "$*" >> "${REPORT:-/dev/null}"; }

# Warnings: screen (yellow) only — plain text to file (no ANSI codes)
warn() {
    printf "${YLW}[!] %b${RST}\n" "$*"
    printf '[!] %b\n' "$*" >> "${REPORT:-/dev/null}"
}
die()    { printf "${RED}[-] %b${RST}\n" "$*" >&2; exit 1; }

# Findings: screen (green bold) + file
hit() {
    printf "${BLD}${GRN}  ★  %b${RST}\n" "$*"
    printf '  ★  %b\n' "$*" >> "${REPORT:-/dev/null}"
}

print_logo() {
    printf "${BLD}${CYN}"
    printf '  ███████╗████████╗██╗  ██╗██╗   ██╗███╗   ██╗████████╗\n'
    printf '  ██╔════╝╚══██╔══╝██║  ██║██║   ██║████╗  ██║╚══██╔══╝\n'
    printf '  ███████╗   ██║   ███████║██║   ██║██╔██╗ ██║   ██║   \n'
    printf '  ╚════██║   ██║   ██╔══██║██║   ██║██║╚████║   ██║   \n'
    printf '  ███████║   ██║   ██║  ██║╚██████╔╝██║ ╚███║   ██║   \n'
    printf '  ╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚══╝   ╚═╝  \n'
    printf "${RST}"
    printf "  ${DIM}autonomous stego & web hunter${RST}\n\n"
}

usage() {
    echo -e "${BLD}Usage:${RST} sthunt.sh <url | image_file> [options]"
    echo "  -p, --pass PASSWORD     extra steghide password to try"
    echo "  -d, --depth N           crawl depth (default: 3)"
    echo "  -w, --wordlist FILE     wordlist for stegseek bruteforce"
    echo "  --binwalk               run binwalk scan + auto-extract (off by default)"
    exit 1
}

[[ $# -lt 1 ]] && usage

TARGET="$1"; shift
EXTRA_PASS=""
CRAWL_DEPTH=3
WORDLIST=""
RUN_BINWALK=0

# auto-detect rockyou
for _wl in /usr/share/wordlists/rockyou.txt /usr/share/wordlists/rockyou.txt.gz; do
    [[ -f "$_wl" && "$_wl" != *.gz ]] && { WORDLIST="$_wl"; break; }
done

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--pass)     EXTRA_PASS="$2";  shift 2 ;;
        -d|--depth)    CRAWL_DEPTH="$2"; shift 2 ;;
        -w|--wordlist) WORDLIST="$2";    shift 2 ;;
        --binwalk)     RUN_BINWALK=1;    shift ;;
        *) [[ -z "$EXTRA_PASS" ]] && EXTRA_PASS="$1"; shift ;;
    esac
done

# ── output dirs ───────────────────────────────────────────────────────────────
OUTDIR="stego-$(echo "$TARGET" | sed 's|https\?://||;s|[/: ]|_|g' | cut -c1-40)"
mkdir -p "$OUTDIR"/{images,extracted,reports,pages}
REPORT="$OUTDIR/reports/findings.txt"
: > "$REPORT"

print_logo

# Log the run header to file
{
    echo "STHUNT — AUTONOMOUS WEB STEGO HUNT"
    echo "Target   : $TARGET"
    echo "Depth    : $CRAWL_DEPTH"
    echo "Wordlist : ${WORDLIST:-none}"
    echo "Outdir   : $OUTDIR"
    echo "Date     : $(date '+%Y-%m-%d %H:%M')"
    echo "========================================================"
} >> "$REPORT"

# ── built-in directory/file wordlist ──────────────────────────────────────────
BUILTIN_WORDLIST=(
    # Common directories
    admin administrator backup backups bin cache cgi-bin config configs
    console control dashboard data db debug dev docs download downloads
    files hidden img images includes js lib login logs manager media
    old panel phpmyadmin portal private protected public robots secret
    secure setup shop sql static store temp test tmp upload uploads
    user users web wp-admin wp-content wp-includes
    # Common files
    .env .git .htpasswd .htaccess .bash_history
    config.php config.inc.php configuration.php settings.php
    admin.php index.php login.php info.php phpinfo.php
    robots.txt sitemap.xml readme.txt README.md changelog.txt
    # CTF favourites
    flag flag.txt secret.txt password.txt key.txt note.txt notes.txt
    hint.txt creds.txt credentials.txt initech.html
)

# ── URL helpers ───────────────────────────────────────────────────────────────
is_url()       { [[ "$1" =~ ^https?:// ]]; }
is_image_url() { [[ "$1" =~ \.(jpg|jpeg|png|gif|bmp|webp|tiff?)(\?.*)?$ ]]; }

get_origin() {
    local proto host
    proto=$(echo "$1" | grep -oE '^https?://')
    host=$(echo "$1" | sed 's|^https\?://||;s|[/?#].*||')
    echo "${proto}${host}"
}

resolve_url() {
    local base="$1" href="$2" origin
    origin=$(get_origin "$base")
    if   [[ "$href" =~ ^https?:// ]]; then echo "$href"
    elif [[ "$href" =~ ^// ]];        then echo "$(echo "$base" | grep -oE '^https?:')$href"
    elif [[ "$href" =~ ^/ ]];         then echo "${origin}${href}"
    elif [[ "$href" =~ ^[#?] || -z "$href" ]]; then echo ""
    else
        local base_dir
        base_dir=$(echo "$base" | sed 's|[^/]*$||')
        echo "${base_dir}${href}"
    fi
}

# ── state ─────────────────────────────────────────────────────────────────────
declare -A VISITED
declare -A DOWNLOADED
declare -A FOUND_PW_CTX
declare -A EXTRACTED_SEEN
IMAGES=()
FOUND_PASSWORDS=()
FOUND_CREDS=()
HTML_FINDINGS=()
MANUAL_CHECKS=()
FORBIDDEN_PATHS=()

# Strings that are never useful as passwords (exif metadata noise, etc.)
PASS_DENYLIST=('(none)' 'none' 'true' 'false' 'null' 'undefined' 'unknown'
               'Independent' 'Not Embedded, Independent')

# Dedup at insertion time and record source context
add_password() {
    local val="$1" ctx="${2:-unknown}"
    [[ -z "$val" ]] && return
    # denylist — skip known-noise values
    local _d; for _d in "${PASS_DENYLIST[@]}"; do [[ "$val" == "$_d" ]] && return; done
    local p; for p in "${FOUND_PASSWORDS[@]:-}"; do [[ "$p" == "$val" ]] && return; done
    FOUND_PASSWORDS+=("$val")
    FOUND_PW_CTX["$val"]="$ctx"
}

# ── image download ────────────────────────────────────────────────────────────
download_image() {
    local full="$1"
    [[ -n "${DOWNLOADED[$full]:-}" ]] && return
    local fname dest
    fname=$(basename "${full%%\?*}")
    dest="$OUTDIR/images/$fname"
    local c=1
    while [[ -e "$dest" ]]; do
        dest="$OUTDIR/images/${fname%.*}_${c}.${fname##*.}"
        (( c++ ))
    done
    if curl -skL --max-time 15 "$full" -o "$dest" 2>/dev/null && [[ -s "$dest" ]]; then
        DOWNLOADED["$full"]="$dest"
        IMAGES+=("$dest")
        log "Downloaded: $fname"
    else
        rm -f "$dest" 2>/dev/null
    fi
}

# ── extract images + links from a page ───────────────────────────────────────
extract_from_page() {
    local page="$1"
    local -n _imgs="$2"
    local -n _links="$3"

    # src=/href= images
    while IFS= read -r u; do [[ -n "$u" ]] && _imgs+=("$u"); done \
        < <(echo "$page" | grep -oiE '(src|href)="[^"]*\.(jpg|jpeg|png|gif|bmp|webp|tiff?)[^"]*"' \
            | grep -oiE '"[^"]*"' | tr -d '"')
    # unquoted src=
    while IFS= read -r u; do [[ -n "$u" ]] && _imgs+=("$u"); done \
        < <(echo "$page" | grep -oiE "src=[^>[:space:]\"']*\.(jpg|jpeg|png|gif|bmp|webp|tiff?)[^>[:space:]\"']*" \
            | sed "s/src=//;s/['\"]//g")
    # srcset= / <picture><source srcset>
    while IFS= read -r u; do [[ -n "$u" ]] && is_image_url "$u" && _imgs+=("$u"); done \
        < <({ echo "$page" | grep -oiE 'srcset="[^"]*"'
              echo "$page" | grep -oiE '<source[^>]*srcset="[^"]*"' | grep -oiE 'srcset="[^"]*"'; } \
            | tr -d '"' | sed 's/srcset=//' | tr ',' '\n' | awk '{print $1}')
    # CSS url(...)
    while IFS= read -r u; do [[ -n "$u" ]] && is_image_url "$u" && _imgs+=("$u"); done \
        < <(echo "$page" | grep -oiE "url\(['\"]?[^)'\"]+\.(jpg|jpeg|png|gif|bmp|webp|tiff?)[^)'\"]*['\"]?\)" \
            | grep -oiE "['\"]?[^()'\"]+\.(jpg|jpeg|png|gif|bmp|webp|tiff?)[^)'\"]*" | tr -d "'\"")
    # <a href> links
    while IFS= read -r u; do [[ -n "$u" ]] && _links+=("$u"); done \
        < <(echo "$page" | grep -oiE 'href="[^"]*"' | tr -d '"' | sed 's/href=//' \
            | grep -viE '\.(css|js|xml|pdf|zip|gz|tar|ico|svg|woff|ttf|eot)(\?|$)')
}

# ── directory listing ─────────────────────────────────────────────────────────
is_dir_listing() { echo "$1" | grep -qiE 'Index of /|Directory listing|<title>Index of'; }

scrape_dirlist() {
    local page="$1" base_url="$2"
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        local full
        full=$(resolve_url "${base_url%/}/" "$entry")
        [[ -z "$full" ]] && continue
        if is_image_url "$full"; then
            download_image "$full"
        elif [[ "$full" =~ /$ && -z "${VISITED[$full]:-}" ]]; then
            crawl_page "$full" 1
        fi
    done < <(echo "$page" | grep -oiE 'href="[^"?]+"' | tr -d '"' | sed 's/href=//' \
        | grep -v '^\.\.' | grep -vE '^https?://' | grep -v '^/')
}

# ── HTML source intelligence ──────────────────────────────────────────────────
try_b64_decode() {
    local token="$1" source_url="$2" context="$3"
    [[ ${#token} -lt 16 ]] && return
    # strip decorative non-b64 prefix/suffix (e.g. "----", ">>>", ": ")
    token=$(echo "$token" | sed 's/^[^A-Za-z0-9+/]*//;s/[^A-Za-z0-9+/=]*$//')
    [[ ${#token} -lt 16 ]] && return
    echo "$token" | grep -qE '^[A-Za-z0-9+/]{16,}={0,2}$' || return

    local decoded
    decoded=$(echo "$token" | base64 -d 2>/dev/null | tr -d '\0')
    [[ -z "$decoded" ]] && return
    # reject if any non-printable / non-ASCII bytes survive
    local _clean
    _clean=$(printf '%s' "$decoded" | LC_ALL=C tr -cd '[:print:][:space:]')
    [[ "$_clean" != "$decoded" ]] && return

    log "→ b64[$context]: $decoded"
    add_password "$decoded" "$source_url|$context|b64"
    HTML_FINDINGS+=("$source_url | $context | b64: $decoded")

    # double decode — this is the interesting result (often user:pass)
    local decoded2
    decoded2=$(echo "$decoded" | base64 -d 2>/dev/null | tr -d '\0')
    if [[ -n "$decoded2" && $(echo "$decoded2" | cat -v | grep -c '\^') -lt 3 ]]; then
        hit "b64 → $decoded2  ${DIM}(${context})${RST}"
        log "→ double-b64[$context]: $decoded2"
        FOUND_CREDS+=("$source_url | $context | $decoded2")
        HTML_FINDINGS+=("$source_url | $context | double-b64: $decoded2")
        add_password "$decoded2" "$source_url|$context|double-b64"
    fi
}

scan_html() {
    local page="$1" source_url="$2"
    local label
    label=$(echo "$source_url" | sed 's|https\?://||')
    log "\n[HTML ANALYSIS — $label]"

    # ── HTML comments ─────────────────────────────────────────────────────────
    while IFS= read -r comment; do
        [[ -z "$comment" ]] && continue
        local content
        content=$(echo "$comment" | sed 's/<!--//;s/-->//;s/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$content" ]] && continue
        log "COMMENT: $content"
        # Only surface comments that look interesting (credentials, hints, encoded data)
        local _interesting=0
        echo "$content" | grep -qiE 'password|passwd|flag|secret|key|token|user|login|admin|cred|nothing|hidden|email|hint|backdoor|shell' && _interesting=1
        [[ ${#content} -gt 40 ]] && _interesting=1
        if [[ $_interesting -eq 1 ]]; then
            hit "comment: $content  ${DIM}(${label})${RST}"
            HTML_FINDINGS+=("$source_url | comment | $content")
        fi
        for token in $content; do
            try_b64_decode "$token" "$source_url" "comment"
        done
    done < <(echo "$page" | tr '\n' ' ' | grep -oiE '<!--[^>]*-->' | head -20)

    # ── hidden input fields ───────────────────────────────────────────────────
    while IFS= read -r field; do
        [[ -z "$field" ]] && continue
        local val name
        val=$(echo "$field"  | grep -oiE 'value="[^"]*"' | sed 's/value=//;s/"//g')
        name=$(echo "$field" | grep -oiE 'name="[^"]*"'  | sed 's/name=//;s/"//g')
        [[ -z "$val" || "$val" == "0" ]] && continue
        log "HIDDEN FIELD: $name=$val"
        # Skip common benign form ops
        echo "$val" | grep -qiE '^(login|logout|register|mailpasswd|results|submit|1|true|false|yes|no|post|get|/[a-z])' && { try_b64_decode "$val" "$source_url" "hidden_field"; continue; }
        # Only surface if value looks like a token/credential (>8 chars, or 32-char hex)
        if [[ ${#val} -ge 8 ]] || echo "$val" | grep -qE '^[0-9a-f]{32}$'; then
            hit "hidden: ${name}=${val}  ${DIM}(${label})${RST}"
            HTML_FINDINGS+=("$source_url | hidden_field | $name=$val")
            add_password "$val" "$source_url|hidden_field:$name"
        fi
        try_b64_decode "$val" "$source_url" "hidden_field"
    done < <(echo "$page" | grep -oiE '<input[^>]+type="?hidden[^>]*>' | head -10)

    # ── inline credential/flag patterns ──────────────────────────────────────
    local _cred_pat='(password|passwd|flag|secret|key|token|cred)[[:space:]]*[:=][[:space:]]*[^<"&[:space:]]{4,}'
    while IFS= read -r hit_line; do
        [[ -z "$hit_line" ]] && continue
        hit "Pattern: ${hit_line}  ${DIM}(${label})${RST}"
        log "★ PATTERN: $hit_line"
        HTML_FINDINGS+=("$source_url | pattern | $hit_line")
        local pval
        pval=$(echo "$hit_line" | sed 's/^[^:=]*[:=][[:space:]]*//')
        add_password "$pval" "$source_url|pattern"
        try_b64_decode "$pval" "$source_url" "pattern"
    done < <(echo "$page" | grep -oiE "$_cred_pat" | head -10)

    # ── meta tags (log only — too noisy for screen) ───────────────────────────
    while IFS= read -r meta; do
        [[ -z "$meta" ]] && continue
        log "META: $meta"
    done < <(echo "$page" | grep -oiE '<meta[^>]*(name|content)[^>]*>' \
        | grep -iE 'author|description|keyword|generator|password|secret|flag' | head -5)
}

# ── BFS crawler ───────────────────────────────────────────────────────────────
crawl_page() {
    local url="$1" depth="$2"
    local origin
    origin=$(get_origin "$TARGET")
    [[ -n "${VISITED[$url]:-}" ]] && return
    VISITED["$url"]=1

    log "[CRAWL depth=$depth] $url"
    local page
    page=$(curl -skL --max-time 15 "$url") || { log "curl failed: $url"; return; }

    local slug
    slug=$(echo "$url" | sed 's|https\?://||;s|[/: ?]|_|g' | cut -c1-50)
    echo "$page" > "$OUTDIR/pages/${slug}.html"

    scan_html "$page" "$url"

    if is_dir_listing "$page"; then
        hit "Directory listing: $url"
        scrape_dirlist "$page" "$url"
        return
    fi

    local raw_imgs=() raw_links=()
    extract_from_page "$page" raw_imgs raw_links

    for u in "${raw_imgs[@]}"; do
        local full
        full=$(resolve_url "$url" "$u")
        [[ -n "$full" ]] && is_image_url "$full" && download_image "$full"
    done

    if [[ $depth -gt 0 ]]; then
        for u in "${raw_links[@]}"; do
            local full
            full=$(resolve_url "$url" "$u")
            [[ -z "$full" ]] && continue
            [[ "$(get_origin "$full")" != "$origin" ]] && continue
            [[ -n "${VISITED[$full]:-}" ]] && continue
            crawl_page "$full" $(( depth - 1 ))
        done
    fi
}

# ── built-in directory discovery ─────────────────────────────────────────────
discover_dirs() {
    local origin
    origin=$(get_origin "$TARGET")
    local total=${#BUILTIN_WORDLIST[@]}
    log "[DIRSCAN] $origin — ${total} probes"

    local tmpfile
    tmpfile=$(mktemp)

    for word in "${BUILTIN_WORDLIST[@]}"; do
        {
            local url="${origin}/${word}"
            local code
            code=$(curl -skL --max-time 4 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
            case "$code" in
                200|301|302|403) echo "$code $url" >> "$tmpfile" ;;
            esac
        } &
        (( $(jobs -r | wc -l) >= 20 )) && wait
    done
    wait

    if [[ -s "$tmpfile" ]]; then
        while IFS= read -r line; do
            local code furl
            code=$(echo "$line" | awk '{print $1}')
            furl=$(echo "$line"  | awk '{print $2}')
            log "→ FOUND: $furl [$code]"
            if [[ "$code" == "403" ]]; then
                FORBIDDEN_PATHS+=("$furl")
                log "→ FORBIDDEN (403): $furl"
                continue
            fi
            hit "Found path [$code]: $furl"
            [[ -n "${VISITED[$furl]:-}" ]] && continue
            crawl_page "$furl" 1
        done < <(sort "$tmpfile")
    else
        log "No additional paths discovered."
    fi
    rm -f "$tmpfile"
}

# ── exiftool analysis ─────────────────────────────────────────────────────────
SUSPICIOUS_FIELDS=(
    "Comment" "UserComment" "ImageDescription" "Description"
    "Artist" "Author" "Creator" "Copyright" "Writer"
    "XPComment" "Subject" "Keywords" "Caption" "Headline"
    "Label" "Nickname"
)
DATA_PATTERNS='[A-Za-z0-9+/]{20,}={0,2}|[0-9a-f]{32,}|password|passwd|secret|flag|cred|token|key|user|login|admin|root|ssh'

analyse_image() {
    local img="$1" base
    base=$(basename "$img")
    log "\n════════════════════════════════════════════"
    log " IMAGE: $base"
    log "════════════════════════════════════════════"

    # ── strings ───────────────────────────────────────────────────────────────
    if command -v strings &>/dev/null; then
        local str_hits
        str_hits=$(strings "$img" 2>/dev/null \
            | grep -iE 'password|passwd|flag|secret|key|token|admin|root|ssh|BEGIN' | head -10)
        if [[ -n "$str_hits" ]]; then
            while IFS= read -r s; do
                log "★ STRINGS: $s"
                add_password "$s" "strings:$base"
                hit "strings: $s"
            done <<< "$str_hits"
        fi
    fi

    # ── binwalk (opt-in) ──────────────────────────────────────────────────────
    if [[ $RUN_BINWALK -eq 1 ]] && command -v binwalk &>/dev/null; then
        local bw_out
        bw_out=$(binwalk "$img" 2>/dev/null | grep -v "DECIMAL\|-------\|^$")
        if [[ -n "$bw_out" ]]; then
            log "$bw_out"
            local bw_outdir="$OUTDIR/extracted/binwalk_${base%.*}"
            mkdir -p "$bw_outdir"
            binwalk -e -C "$bw_outdir" "$img" &>/dev/null
            hit "binwalk: embedded data found → $bw_outdir"
            log "★ BINWALK-EXTRACT: $bw_outdir"
            while IFS= read -r ef; do
                local ef_hits
                ef_hits=$(strings "$ef" 2>/dev/null \
                    | grep -iE 'password|passwd|flag|secret|key|token|admin|root|ssh|BEGIN' | head -5)
                [[ -z "$ef_hits" ]] && continue
                while IFS= read -r s; do
                    hit "binwalk/strings: $s"
                    log "★ BINWALK-STRINGS: $s"
                    add_password "$s" "binwalk_extract:$base"
                done <<< "$ef_hits"
            done < <(find "$bw_outdir" -type f 2>/dev/null)
        fi
    fi

    # ── exiftool ──────────────────────────────────────────────────────────────
    if ! command -v exiftool &>/dev/null; then
        warn "exiftool not found — apt install libimage-exiftool-perl"
        return
    fi

    local exif_out
    exif_out=$(exiftool "$img" 2>/dev/null)
    echo "$exif_out" >> "$REPORT"

    if echo "$exif_out" | grep -qi "chunk.*after\|after.*IDAT\|after.*data"; then
        hit "PNG chunk injection detected in $base"
        log "★ CHUNK INJECTION"
    fi

    local found_any=0
    for field in "${SUSPICIOUS_FIELDS[@]}"; do
        local val
        val=$(echo "$exif_out" | grep -i "^${field}[[:space:]]*:" | sed 's/^[^:]*: *//')
        [[ -z "$val" ]] && continue
        found_any=1
        hit "exif ${field}: ${val}"
        log "★ $field: $val"
        try_b64_decode "$val" "$base" "exif:$field"
        [[ ${#val} -le 64 ]] && add_password "$val" "exif:$field:$base"
    done

    local pattern_hits
    pattern_hits=$(echo "$exif_out" | grep -iE "$DATA_PATTERNS" \
        | grep -v "^File\|^MIME\|^Image Size\|^Megapixels\|^Bits Per\|^Color\|^Encoding\|^Exif\|^JFIF\|^X Resolution\|^Y Resolution\|^Create Date\|^Modify Date\|^Date\|^APP14\|^CMM\|^Profile\|^Device\|^Rendering\|^Connection\|^Primary\|^Viewing\|^Luminance\|^Measurement\|^Technology\|^Red \|^Green \|^Blue \|^Media ")
    if [[ -n "$pattern_hits" ]]; then
        found_any=1
        while IFS= read -r line; do
            log "? $line"
            local pval
            pval=$(echo "$line" | sed 's/^[^:]*:[[:space:]]*//')
            try_b64_decode "$pval" "$base" "exif:pattern"
            [[ ${#pval} -le 64 ]] && add_password "$pval" "exif:pattern:$base"
        done <<< "$pattern_hits"
    fi
}

# ── re-analyse any successfully extracted file ────────────────────────────────
analyse_extracted() {
    local ef="$1" source="$2"
    [[ -f "$ef" && -s "$ef" ]] || return
    [[ -n "${EXTRACTED_SEEN[$ef]:-}" ]] && return
    EXTRACTED_SEEN["$ef"]=1
    local ef_base
    ef_base=$(basename "$ef")
    log "\n[ANALYSE EXTRACTED — $ef_base ← $source]"

    # b64 decode every whitespace-delimited token in the file
    while IFS= read -r token; do
        try_b64_decode "$token" "$source" "extracted:$ef_base"
    done < <(tr '[:space:]' '\n' < "$ef" | grep -E '^.{16,}$')

    # strings keyword scan
    if command -v strings &>/dev/null; then
        local s_hits
        s_hits=$(strings "$ef" 2>/dev/null \
            | grep -iE 'password|passwd|flag|secret|key|token|admin|root|ssh|BEGIN' | head -5)
        if [[ -n "$s_hits" ]]; then
            while IFS= read -r s; do
                hit "extracted strings: $s  ${DIM}(from $source)${RST}"
                log "★ EXTRACTED-STRINGS: $s"
                add_password "$s" "extracted:$ef_base"
            done <<< "$s_hits"
        fi
    fi

    # if the extracted file is itself an image, run the full stego pipeline on it
    if file "$ef" 2>/dev/null | grep -qiE 'JPEG|PNG|bitmap|GIF'; then
        hit "Extracted payload is an image — running stego pipeline"
        analyse_image "$ef"
        run_steghide "$ef"
        run_stegseek "$ef"
        run_zsteg "$ef"
        run_outguess "$ef"
    fi
}

# ── steghide ──────────────────────────────────────────────────────────────────
try_steghide() {
    local img="$1" pass="$2"
    local base out_file
    base=$(basename "$img")
    out_file="$OUTDIR/extracted/${base%.*}_steghide_$(echo "$pass" | tr -dc 'a-zA-Z0-9_' | cut -c1-16).txt"
    steghide extract -sf "$img" -p "$pass" -f -q -xf "$out_file" 2>/dev/null
    if [[ $? -eq 0 && -s "$out_file" ]]; then
        hit "steghide CRACKED: $base  pass='${pass}'  → $(cat "$out_file")"
        log "[STEGHIDE HIT — $base]  pass='$pass'"
        log "Contents: $(cat "$out_file")"
        FOUND_CREDS+=("steghide | $base | $(cat "$out_file")")
        analyse_extracted "$out_file" "steghide:$base"
        return 0
    fi
    rm -f "$out_file" 2>/dev/null
    return 1
}

run_steghide() {
    local img="$1" base
    base=$(basename "$img")
    [[ "$base" =~ \.(jpg|jpeg|bmp|wav|au)$ ]] || return

    log "\n[STEGHIDE — $base]"
    local passwords=("" "password" "secret" "hidden" "stego" "admin" "root" "flag"
                     "letmein" "12345" "qwerty" "abc123" "monkey" "dragon" "master"
                     "initech" "lumbergh" "gibbons" "milton")
    [[ -n "$EXTRA_PASS" ]] && passwords=("$EXTRA_PASS" "${passwords[@]}")
    for p in "${FOUND_PASSWORDS[@]:-}"; do passwords=("$p" "${passwords[@]}"); done

    # deduplicate password list
    local deduped=()
    for pw in "${passwords[@]}"; do
        local seen=0
        local d; for d in "${deduped[@]:-}"; do [[ "$d" == "$pw" ]] && seen=1 && break; done
        [[ $seen -eq 0 ]] && deduped+=("$pw")
    done

    for pass in "${deduped[@]}"; do
        log "  trying: '${pass:-<empty>}'"
        try_steghide "$img" "$pass" && return
    done
    log "  steghide: no match (${#deduped[@]} tried)"
    [[ -z "$WORDLIST" ]] && MANUAL_CHECKS+=("stegseek $img /usr/share/wordlists/rockyou.txt")
}

run_stegseek() {
    local img="$1" base
    base=$(basename "$img")
    [[ "$base" =~ \.(jpg|jpeg|bmp|wav|au)$ ]] || return
    command -v stegseek &>/dev/null || { warn "stegseek not found — skipping $base"; return; }

    log "\n[STEGSEEK — $base]"

    # Pass 1: custom mini-wordlist from all discovered passwords
    if [[ ${#FOUND_PASSWORDS[@]} -gt 0 ]]; then
        local custom_wl out_custom
        custom_wl=$(mktemp)
        printf '%s\n' "${FOUND_PASSWORDS[@]}" | sort -u > "$custom_wl"
        out_custom="$OUTDIR/extracted/${base%.*}_stegseek_custom.txt"
        log "  Pass 1: ${#FOUND_PASSWORDS[@]} discovered password(s)"
        if stegseek "$img" "$custom_wl" "$out_custom" 2>/dev/null; then
            hit "stegseek CRACKED (discovered passwords): $base  → $(cat "$out_custom" 2>/dev/null)"
            log "Contents: $(cat "$out_custom" 2>/dev/null)"
            FOUND_CREDS+=("stegseek | $base | $(cat "$out_custom" 2>/dev/null)")
            analyse_extracted "$out_custom" "stegseek:$base"
            rm -f "$custom_wl"
            return
        fi
        rm -f "$custom_wl" "$out_custom" 2>/dev/null
    fi

    # Pass 2: full wordlist bruteforce
    if [[ -z "$WORDLIST" ]]; then
        log "  stegseek: no wordlist"
        return
    fi
    log "  Pass 2: wordlist $WORDLIST"
    local out_file="$OUTDIR/extracted/${base%.*}_stegseek.txt"
    if stegseek "$img" "$WORDLIST" "$out_file" 2>/dev/null; then
        hit "stegseek CRACKED: $base  → $(cat "$out_file" 2>/dev/null)"
        log "Contents: $(cat "$out_file" 2>/dev/null)"
        FOUND_CREDS+=("stegseek | $base | $(cat "$out_file" 2>/dev/null)")
        analyse_extracted "$out_file" "stegseek:$base"
    else
        log "  stegseek: no match (wordlist exhausted)"
        rm -f "$out_file" 2>/dev/null
    fi
}

# ── zsteg (PNG/BMP LSB) ───────────────────────────────────────────────────────
run_zsteg() {
    local img="$1" base
    base=$(basename "$img")
    [[ "$base" =~ \.(png|bmp)$ ]] || return
    command -v zsteg &>/dev/null || { warn "zsteg not found — skipping LSB on $base (gem install zsteg)"; return; }

    log "\n[ZSTEG — $base]"
    local zsteg_out
    zsteg_out=$(zsteg "$img" 2>/dev/null | head -50)
    echo "$zsteg_out" >> "$REPORT"

    [[ -z "$zsteg_out" ]] && return

    while IFS= read -r line; do
        local zval
        zval=$(echo "$line" | sed 's/.*text:[[:space:]]*//' | tr -d '"')
        [[ ${#zval} -lt 4 ]] && continue
        hit "zsteg: $zval"
        add_password "$zval" "zsteg:$base"
        try_b64_decode "$zval" "$base" "zsteg"
        FOUND_CREDS+=("zsteg | $base | $zval")
    done < <(echo "$zsteg_out" | grep -i 'text:')
}

# ── outguess ──────────────────────────────────────────────────────────────────
run_outguess() {
    local img="$1" base
    base=$(basename "$img")
    [[ "$base" =~ \.(jpg|jpeg|png)$ ]] || return
    command -v outguess &>/dev/null || return

    log "\n[OUTGUESS — $base]"
    local passwords=("" "${FOUND_PASSWORDS[@]:-}")
    [[ -n "$EXTRA_PASS" ]] && passwords=("$EXTRA_PASS" "${passwords[@]}")

    local deduped=()
    for pw in "${passwords[@]}"; do
        local seen=0
        local d; for d in "${deduped[@]:-}"; do [[ "$d" == "$pw" ]] && seen=1 && break; done
        [[ $seen -eq 0 ]] && deduped+=("$pw")
    done

    for pass in "${deduped[@]}"; do
        log "  trying: '${pass:-<empty>}'"

        local out_file
        out_file="$OUTDIR/extracted/${base%.*}_outguess_$(echo "$pass" | tr -dc 'a-zA-Z0-9_' | cut -c1-16).txt"
        local og_args=()
        [[ -n "$pass" ]] && og_args+=(-k "$pass")
        og_args+=(-r "$img" "$out_file")

        if outguess "${og_args[@]}" 2>/dev/null && [[ -s "$out_file" ]]; then
            hit "outguess CRACKED: $base  pass='${pass:-<empty>}'  → $(cat "$out_file")"
            log "[OUTGUESS HIT — $base]  pass='$pass'"
            log "Contents: $(cat "$out_file")"
            FOUND_CREDS+=("outguess | $base | $(cat "$out_file")")
            analyse_extracted "$out_file" "outguess:$base"
            return
        fi
        rm -f "$out_file" 2>/dev/null
    done
}

# ── main ──────────────────────────────────────────────────────────────────────
if is_url "$TARGET"; then
    if is_image_url "$TARGET"; then
        download_image "$TARGET"
    else
        crawl_page "$TARGET" "$CRAWL_DEPTH"
        discover_dirs
    fi
elif [[ -f "$TARGET" ]]; then
    cp "$TARGET" "$OUTDIR/images/$(basename "$TARGET")"
    IMAGES+=("$OUTDIR/images/$(basename "$TARGET")")
else
    die "Target '$TARGET' is not a valid file or URL."
fi

log "\n[IMAGES COLLECTED — ${#IMAGES[@]} total]"
for img in "${IMAGES[@]}"; do log "  → $(basename "$img")"; done

# analyse every image
for img in "${IMAGES[@]}"; do
    [[ -f "$img" ]] || continue
    analyse_image "$img"
    run_steghide "$img"
    run_stegseek "$img"
    run_zsteg "$img"
    run_outguess "$img"
done

# ── log final report ──────────────────────────────────────────────────────────
{
    echo ""
    echo "========================================================"
    echo "FINAL REPORT"
    echo "========================================================"
    if [[ ${#FOUND_CREDS[@]} -gt 0 ]]; then
        echo ""
        echo "★ CREDENTIALS / EXTRACTED DATA:"
        for c in "${FOUND_CREDS[@]}"; do echo "  → $c"; done
    fi
    if [[ ${#HTML_FINDINGS[@]} -gt 0 ]]; then
        echo ""
        echo "★ HTML SOURCE FINDINGS:"
        for h in "${HTML_FINDINGS[@]}"; do echo "  → $h"; done
    fi
    if [[ ${#FOUND_PASSWORDS[@]} -gt 0 ]]; then
        echo ""
        echo "★ POTENTIAL PASSWORDS / STRINGS:"
        for p in "${FOUND_PASSWORDS[@]}"; do
            echo "  → $p  ← ${FOUND_PW_CTX[$p]:-unknown}"
        done
    fi
    if [[ ${#FORBIDDEN_PATHS[@]} -gt 0 ]]; then
        echo ""
        echo "⊘ FORBIDDEN PATHS (403):"
        for f in "${FORBIDDEN_PATHS[@]}"; do echo "  → $f"; done
    fi
    if [[ ${#MANUAL_CHECKS[@]} -gt 0 ]]; then
        echo ""
        echo "⚠ MANUAL CHECKS:"
        for m in "${MANUAL_CHECKS[@]}"; do echo "  - $m"; done
    fi
    echo ""
    echo "Images analysed : ${#IMAGES[@]}"
    echo "Pages crawled   : ${#VISITED[@]}"
    echo "Full log        : $REPORT"
    echo "Extracted files : $OUTDIR/extracted/"
} >> "$REPORT"

# ── screen summary ────────────────────────────────────────────────────────────
SUMMARY="$OUTDIR/reports/summary.txt"

print_summary() {
    local SEP="${DIM}────────────────────────────────────────────────────────${RST}"

    printf '\n'
    printf "${BLD}${CYN}  STHUNT SUMMARY${RST}  ${DIM}%s${RST}\n" "$(date '+%Y-%m-%d %H:%M')"
    printf "${SEP}\n"
    printf "  ${DIM}target${RST}   %s\n"   "$TARGET"
    printf "  ${DIM}pages${RST}    %s    ${DIM}images${RST}  %s    ${DIM}outdir${RST}  %s\n" \
        "${#VISITED[@]}" "${#IMAGES[@]}" "$OUTDIR"
    printf "${SEP}\n"

    # ── credentials ───────────────────────────────────────────────────────────
    if [[ ${#FOUND_CREDS[@]} -gt 0 ]]; then
        printf "\n  ${BLD}${GRN}★  CREDENTIALS / EXTRACTED PAYLOADS${RST}\n\n"
        for c in "${FOUND_CREDS[@]}"; do
            # split on " | " into tool, file, value
            local _tool _file _val
            _tool=$(echo "$c" | awk -F' \\| ' '{print $1}')
            _file=$(echo "$c" | awk -F' \\| ' '{print $2}')
            _val=$(echo  "$c" | awk -F' \\| ' '{print $3}')
            printf "  ${GRN}▸${RST}  ${BLD}%s${RST}\n" "$_val"
            printf "     ${DIM}via %s  ←  %s${RST}\n" "$_tool" "$_file"
        done
        printf '\n'
        printf "${SEP}\n"
    fi

    # ── password candidates ───────────────────────────────────────────────────
    _pw_filtered=()
    for p in "${FOUND_PASSWORDS[@]}"; do
        echo "$p" | grep -q ' ' && ! echo "$p" | grep -qE '^[^:]+:[^ ]+$' && continue
        [[ ${#p} -gt 80 ]] && continue
        # skip if already surfaced as a confirmed credential
        local _in_creds=0
        local _c; for _c in "${FOUND_CREDS[@]:-}"; do
            local _cv; _cv=$(echo "$_c" | awk -F' \\| ' '{print $3}')
            [[ "$_cv" == "$p" ]] && _in_creds=1 && break
        done
        [[ $_in_creds -eq 1 ]] && continue
        _pw_filtered+=("$p")
    done
    if [[ ${#_pw_filtered[@]} -gt 0 ]]; then
        printf "\n  ${BLD}${YLW}⚑  PASSWORD CANDIDATES${RST}  ${DIM}(${#_pw_filtered[@]})${RST}\n\n"
        for p in "${_pw_filtered[@]}"; do
            local _ctx="${FOUND_PW_CTX[$p]:-unknown}"
            printf "  ${YLW}▸${RST}  %-40s  ${DIM}%s${RST}\n" "$p" "$_ctx"
        done
        printf '\n'
        printf "${SEP}\n"
    fi

    # ── discovered paths ──────────────────────────────────────────────────────
    if [[ ${#VISITED[@]} -gt 0 ]]; then
        printf "\n  ${BLD}${CYN}◈  PAGES CRAWLED${RST}  ${DIM}(${#VISITED[@]})${RST}\n\n"
        for url in "${!VISITED[@]}"; do
            printf "  ${DIM}·${RST}  %s\n" "$url"
        done
        printf '\n'
        printf "${SEP}\n"
    fi

    # ── forbidden paths (403) ─────────────────────────────────────────────────
    if [[ ${#FORBIDDEN_PATHS[@]} -gt 0 ]]; then
        printf "\n  ${BLD}${RED}⊘  FORBIDDEN PATHS (403)${RST}  ${DIM}(${#FORBIDDEN_PATHS[@]})${RST}\n\n"
        for f in "${FORBIDDEN_PATHS[@]}"; do
            printf "  ${RED}▸${RST}  %s\n" "$f"
        done
        printf '\n'
        printf "${SEP}\n"
    fi

    # ── manual checks ─────────────────────────────────────────────────────────
    if [[ ${#MANUAL_CHECKS[@]} -gt 0 ]]; then
        printf "\n  ${BLD}${RED}⚠  MANUAL CHECKS RECOMMENDED${RST}\n\n"
        for m in "${MANUAL_CHECKS[@]}"; do
            printf "  ${RED}▸${RST}  %s\n" "$m"
        done
        printf '\n'
        printf "${SEP}\n"
    fi

    # ── output locations ──────────────────────────────────────────────────────
    printf "\n  ${DIM}log      %s${RST}\n"  "$REPORT"
    printf "  ${DIM}data     %s${RST}\n\n"  "$OUTDIR/extracted/"
}

print_summary | tee "$SUMMARY"
