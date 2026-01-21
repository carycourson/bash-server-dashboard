# MiniDash 🖥️

A lightweight, zero-dependency TUI (Text User Interface) dashboard for monitoring headless Linux servers.

**MiniDash** was built to provide an "at-a-glance" status of system health, network performance, and service availability without the overhead of heavy monitoring stacks like Grafana or Zabbix. It is written entirely in Bash and relies on standard Linux utilities.

![Dashboard Screenshot](minidash-screenshot.png)
*(Note: Add a screenshot of your dashboard here!)*

## 🚀 Features

* **Real-time System Stats:** Parses `/proc/stat` and `/proc/loadavg` for accurate, instant CPU and memory usage.
* **Network Performance Tracking:** background tracking of internet speed (Latest, Avg 5, Avg 24h) via a non-blocking Cron job.
* **Service Monitoring:** Checks `systemd` status for critical services (Docker containers, Samba, Apache, etc.).
* **Storage Visualization:** Color-coded usage stats for mounted drives.
* **Apache VHost Parser:** Automatically detects and lists enabled Apache VirtualHosts and their proxy ports.

## 🛠️ Prerequisites

* **Bash** (4.0+)
* **speedtest-cli** (Optional, for network tracking)
    ```bash
    sudo apt install speedtest-cli
    ```
* **Standard Utils:** `curl`, `awk`, `grep`, `sed`, `ip` (usually pre-installed on most distros).

## 📥 Installation

1.  **Clone the repository:**
    ```bash
    git clone [https://github.com/carycourson/minidash.git](https://github.com/carycourson/minidash.git)
    cd minidash
    ```

2.  **Make executable:**
    ```bash
    chmod +x minidash.sh
    ```

3.  **Configure your settings:**
    Open `minidash.sh` and edit the top configuration block:
    ```bash
    # Services to check (names must match systemd service names)
    SERVICES=("jellyfin" "apache2" "smbd" "ssh")
    
    # Path to your Samba config (optional)
    SMB_CONF="/etc/samba/smb.conf"
    
    # Path to Apache sites (optional)
    APACHE_DIR="/etc/apache2/sites-enabled"
    ```

## ⚡ Setting up the Speedtest Tracker

To keep the dashboard fast, network tests run in the background via Cron.

1.  **Add the cron job:**
    Run `crontab -e` and add the following line to run a test every 10 minutes:
    ```bash
    */10 * * * * /usr/bin/speedtest-cli --csv >> /var/log/speedtest.log; tail -n 2100 /var/log/speedtest.log > /var/log/speedtest.log.tmp && mv /var/log/speedtest.log.tmp /var/log/speedtest.log
    ```

2.  **Point the script to the log:**
    Update the `SPEEDTEST_LOG` variable in `minidash.sh` to match the path you used in Cron:
    ```bash
    SPEEDTEST_LOG="/var/log/speedtest.log"
    ```

## 🖥️ Usage

Simply run the script:
```bash
./minidash.sh

