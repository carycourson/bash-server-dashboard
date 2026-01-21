#!/bin/bash

# --- CONFIGURATION ---
SERVICES=("service" "names" "separated" "by" "spaces")
SMB_CONF="/etc/samba/smb.conf"
APACHE_DIR="/etc/apache2/sites-enabled"
SPEEDTEST_LOG="/path/to/your/speedtest.log"

WIDTH=105
COL_2_START=60

# --- COLORS ---
NC='\033[0m'
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'

# --- PUBLIC IP CACHING ---
IP_CACHE="/tmp/my_public_ip"
CACHE_TIME=300
if [ -f "$IP_CACHE" ]; then
    if [ $(( $(date +%s) - $(stat -c %Y "$IP_CACHE") )) -ge $CACHE_TIME ]; then rm "$IP_CACHE"; fi
fi
if [ ! -f "$IP_CACHE" ]; then
    (curl -s --max-time 3 https://ifconfig.me > "$IP_CACHE.tmp" && mv "$IP_CACHE.tmp" "$IP_CACHE") &
    if [ ! -f "$IP_CACHE" ]; then echo "Loading..." > "$IP_CACHE"; fi
fi
PUBLIC_IP=$(cat "$IP_CACHE")

# ==============================================================================
# DATA GATHERING
# ==============================================================================

# --- CALCULATE CPU USAGE (Sample over 0.1s) ---
cpu_read1=$(grep '^cpu ' /proc/stat)
sleep 0.1
cpu_read2=$(grep '^cpu ' /proc/stat)
cpu_usage=$(echo -e "$cpu_read1\n$cpu_read2" | awk '
    {
        total = $2 + $3 + $4 + $5 + $6 + $7 + $8
        idle = $5 + $6
        if (NR==1) { prev_total = total; prev_idle = idle }
        else { 
            diff_total = total - prev_total
            diff_idle = idle - prev_idle
            if (diff_total == 0) diff_total = 1 
            usage = (1 - (diff_idle / diff_total)) * 100
            printf "%.1f%%", usage
        }
    }
')

# --- LEFT STACK (Health -> Storage -> SMB) ---
LEFT_STACK=()
LEFT_STACK+=("${CYAN}[ SYSTEM HEALTH ]${NC}")
LEFT_STACK+=(" $(printf "%-10s : %s" "Uptime" "$(uptime -p | sed 's/up //')")")
LEFT_STACK+=(" $(printf "%-10s : %s" "CPU Usage" "$cpu_usage")")
LEFT_STACK+=(" $(printf "%-10s : %s" "Memory" "$(free -h | awk '/^Mem:/ {print $3 " / " $2}')")")
LEFT_STACK+=("")
LEFT_STACK+=("${CYAN}[ STORAGE ]${NC}")
LEFT_STACK+=("$(printf " %-25s %-8s %-8s %-8s" "MOUNT POINT" "SIZE" "USED" "FREE")")
LEFT_STACK+=(" -----------------------------------------------------")
while read -r target size pcent avail; do
    row=$(printf " %-25s ${YELLOW}%-8s${NC} ${GREEN}%-8s${NC} ${YELLOW}%-8s${NC}" "$target" "$size" "$pcent" "$avail")
    LEFT_STACK+=("$row")
done < <(df -h --output=target,size,pcent,avail -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs | tail -n +2 | sort)
LEFT_STACK+=("")
LEFT_STACK+=("${CYAN}[ SMB SHARES ]${NC}")
if [ -f "$SMB_CONF" ]; then
    while read sharename; do
        path=$(grep -A 10 "\[$sharename\]" $SMB_CONF | grep "path =" | head -1 | awk -F '=' '{print $2}' | xargs)
        row=$(printf " %-15s -> %s" "$sharename" "$path")
        LEFT_STACK+=("$row")
    done < <(grep -E '^\[.*\]' $SMB_CONF | grep -v "global" | grep -v "printers" | grep -v "print$" | tr -d '[]' | sort)
fi

# --- RIGHT STACK (Network -> Speedtest -> Services -> Domains) ---
RIGHT_STACK=()
RIGHT_STACK+=("${CYAN}[ NETWORK INTERFACES ]${NC}")
for iface in $(ls /sys/class/net/ | sort); do
    if [ "$iface" == "lo" ]; then continue; fi
    ip_addr=$(ip -4 addr show $iface | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [ -z "$ip_addr" ]; then
        RIGHT_STACK+=(" $(printf "%-12s : ${RED}Down${NC}" "$iface")")
    else
        RIGHT_STACK+=(" $(printf "%-12s : ${GREEN}$ip_addr${NC}" "$iface")")
    fi
done

# --- SPEEDTEST SECTION ---
RIGHT_STACK+=("")
RIGHT_STACK+=("${CYAN}[ SPEEDTEST TRACKER ]${NC}")
if [ -f "$SPEEDTEST_LOG" ]; then
    # Parse last 144 lines
    # Returns: raw_timestamp last_dl last_ul avg5_dl avg5_ul avg24_dl avg24_ul
    read last_raw_ts last_dl last_ul avg5_dl avg5_ul avg24_dl avg24_ul <<< $(tail -n 144 "$SPEEDTEST_LOG" | awk -F',' '
        {
            if (NF < 5) next; 
            # $(NF-6) is timestamp, $(NF-3) is Download, $(NF-2) is Upload
            # We count from END to be safe against commas in names
            t[NR] = $(NF-6);
            d[NR] = $(NF-3) / 1000000;
            u[NR] = $(NF-2) / 1000000;
        }
        END {
            if (NR == 0) { print "0 0 0 0 0 0 0"; exit }

            # LAST
            l_t = t[NR];
            l_d = d[NR]; 
            l_u = u[NR];

            # AVG 5
            count5 = 0; sum5_d = 0; sum5_u = 0;
            start5 = (NR >= 5) ? NR - 4 : 1;
            for (i = start5; i <= NR; i++) { sum5_d += d[i]; sum5_u += u[i]; count5++; }
            a5_d = (count5 > 0) ? sum5_d / count5 : 0;
            a5_u = (count5 > 0) ? sum5_u / count5 : 0;

            # AVG 24H
            sum24_d = 0; sum24_u = 0;
            for (i = 1; i <= NR; i++) { sum24_d += d[i]; sum24_u += u[i]; }
            a24_d = sum24_d / NR; a24_u = sum24_u / NR;

            printf "%s %.1f %.1f %.1f %.1f %.1f %.1f", l_t, l_d, l_u, a5_d, a5_u, a24_d, a24_u
        }
    ')
    
    # Convert timestamp to local HH:MM
    # (date -d automatically handles the timezone if system is set correctly)
    if [ "$last_raw_ts" != "0" ]; then
        display_time=$(date -d "$last_raw_ts" +'%H:%M' 2>/dev/null)
        if [ -z "$display_time" ]; then display_time="--:--"; fi
    else
        display_time="--:--"
    fi
    
    label="Latest ($display_time)"
    RIGHT_STACK+=(" $(printf "%-15s : ${GREEN}%s${NC} ↓ / ${GREEN}%s${NC} ↑ Mbps" "$label" "$last_dl" "$last_ul")")
    RIGHT_STACK+=(" $(printf "%-15s : ${YELLOW}%s${NC} ↓ / ${YELLOW}%s${NC} ↑ Mbps" "Avg (Last 5)" "$avg5_dl" "$avg5_ul")")
    RIGHT_STACK+=(" $(printf "%-15s : ${YELLOW}%s${NC} ↓ / ${YELLOW}%s${NC} ↑ Mbps" "Avg (24 Hours)" "$avg24_dl" "$avg24_ul")")
else
    RIGHT_STACK+=(" Waiting for data... (Check Cron)")
fi

RIGHT_STACK+=("")
RIGHT_STACK+=("${CYAN}[ SERVICES ]${NC}")
for service in $(printf "%s\n" "${SERVICES[@]}" | sort); do
    if systemctl is-active --quiet "$service"; then status="${GREEN}Active${NC}"; else status="${RED}Down${NC}"; fi
    RIGHT_STACK+=(" $(printf "%-15s : %b" "$service" "$status")")
done
RIGHT_STACK+=("")
RIGHT_STACK+=("${CYAN}[ VIRTUAL DOMAINS ]${NC}")
if [ -d "$APACHE_DIR" ]; then
    mapfile -t domain_list < <(awk '
        BEGIN { IGNORECASE=1 }
        /<virtualhost/ { dom=""; port="Local"; }
        /servername/ { dom=$2 }
        /proxypass / {
            split($3, parts, ":");
            if (length(parts) >= 3) {
                val = parts[length(parts)]
                gsub(/[^0-9]/, "", val)
                if (val != "") port = val
            }
        }
        /<\/virtualhost>/ { if (dom != "") unique[dom] = port }
        END { for (d in unique) print d ":" unique[d] }
    ' $APACHE_DIR/*.conf 2>/dev/null | sort)

    max_len=0
    for line in "${domain_list[@]}"; do
        name="${line%%:*}"
        len=${#name}
        if [ $len -gt $max_len ]; then max_len=$len; fi
    done
    for line in "${domain_list[@]}"; do
        name="${line%%:*}"
        port="${line##*:}"
        RIGHT_STACK+=(" $(printf "%-*s : ${YELLOW}%s${NC}" "$max_len" "$name" "$port")")
    done
else
    RIGHT_STACK+=(" Apache dir not found")
fi

# ==============================================================================
# CALCULATE DIMENSIONS & PADDING
# ==============================================================================

# 1. Height Calculation
max_rows=${#LEFT_STACK[@]}
if [ ${#RIGHT_STACK[@]} -gt $max_rows ]; then max_rows=${#RIGHT_STACK[@]}; fi
content_height=$((max_rows + 4)) # +4 for Header/Footers/Dividers

# 2. Vertical Padding
lines=$(tput lines)
v_pad=$(( (lines - content_height) / 2 ))
if [ $v_pad -lt 0 ]; then v_pad=0; fi

# 3. Horizontal Padding
cols=$(tput cols)
h_pad=$(( (cols - WIDTH) / 2 ))
if [ $h_pad -lt 0 ]; then h_pad=0; fi

# Create the spacer string for horizontal centering
PAD_STR=$(printf "%*s" $h_pad "")

# --- HELPER: PRINT LINE WITH BORDERS (AND PADDING) ---
print_line() {
    local text="$1"
    local clean_text=$(echo -e "$text" | sed "s/\x1B\[[0-9;]*[a-zA-Z]//g")
    local len=${#clean_text}
    local pad=$((WIDTH - 4 - len))
    if [ $pad -lt 0 ]; then pad=0; fi

    # We prepend $PAD_STR to the output
    printf "%s${CYAN}|${NC} %b%*s ${CYAN}|${NC}\n" "$PAD_STR" "$text" $pad ""
}

# ==============================================================================
# DRAW DASHBOARD
# ==============================================================================
DIVIDER="${CYAN}+$(printf '%*s' $((WIDTH-2)) '' | tr ' ' '-')+${NC}"

clear

# 1. Apply Vertical Padding
for ((i=0; i<v_pad; i++)); do echo ""; done

# 2. Header
echo -e "${PAD_STR}${DIVIDER}"
header_text="${BLUE}SYSTEM:${NC} ${BOLD}$(hostname)${NC}   |   ${BLUE}DATE:${NC} $(date '+%Y-%m-%d %H:%M:%S')   |   ${BLUE}PUBLIC IP:${NC} ${YELLOW}$PUBLIC_IP${NC}"
print_line "$header_text"
echo -e "${PAD_STR}${DIVIDER}"

# 3. Content Rows
for ((i=0; i<max_rows; i++)); do
    l_str="${LEFT_STACK[$i]}"
    r_str="${RIGHT_STACK[$i]}"

    # Internal column alignment
    clean_l=$(echo -e "$l_str" | sed "s/\x1B\[[0-9;]*[a-zA-Z]//g")
    pad_len=$((COL_2_START - ${#clean_l}))
    if [ $pad_len -lt 0 ]; then pad_len=1; fi

    combined_row=$(printf "%s%*s%b" "$l_str" $pad_len "" "$r_str")
    print_line "$combined_row"
done

# 4. Footer
echo -e "${PAD_STR}${DIVIDER}"
echo ""
