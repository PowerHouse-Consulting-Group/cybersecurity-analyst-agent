# Changelog - Cybersecurity Analyst Agent (Community Edition)

All notable changes to the **Cybersecurity Analyst Agent** open-source community log analyzer and parallel **PRO Edition** will be documented in this file.

## [1.2.1] - 2026-07-27

### Added (PRO Edition TUI)
- **High-Capacity Event Buffering:** Upgraded the internal log event channel to a buffered channel with a capacity of 5,000 events. This resolves thread congestion and UI freezing under intense log flooding.
- **Proper EOF Log Handling:** Fixed edge-case log loss in tail operations by ensuring any trailing line content without an ending newline (\n) immediately preceding EOF is processed before sleeping.
- **Rapid EOF Polling:** Reduced the EOF tail wait timeout from 50ms to 50ms for near-zero latency threat ingestion.
- **Robust TUI Error Rendering on Blocking:** The active block command is now monitored for execution failures, with error messages rendered clearly in the status bar instead of silently assuming success.
- **Circular Gauge Boundary Fix:** Fixed division-by-zero crashes in the dashboard's circular threat severity gauges when total alert count is zero.

### Changed (Community Edition CLI)
- **Version Realignment:** Synced Community Version release code and installation constants to v1.2.1.

## [1.2.0] - 2026-07-24

### Added (PRO Edition TUI)
- **5-Tab Navigation Panel:** Refactored interface into 5 discrete views: Dashboard, Monitoring, Hardening, Remediation, and Insights. Fully accessible via keyboard shortcuts 1-5 and standard Tab / Shift+Tab cycling.
- **Multi-Pane Dashboard View:** Combined circular threat distribution gauges (CRITICAL/HIGH/MEDIUM/LOW) with a scrollable recent activity feed.
- **Dynamic Threat Filtering:** Implemented a prompt bar triggered by / supporting live filters like sev:critical, ip:203.0.113.42, type:brute, or general search terms with AND combination logic.
- **Interactive Detail Modal Overlay:** Pressing Enter on an alert opens a detailed side pane containing timestamps, threat severity scores, raw log entries, expert AI analysis, and quick mitigation CTAs.
- **Smart Auto-Scroll Logic:** Activity log view automatically scrolls to the newest threats, with smart pausing when navigating upwards to inspect historical logs.
- **Context-Sensitive Help Overlay:** Modal menu triggered by ? providing instant documentation for shortcuts and keyboard navigation.

### Changed (PRO Edition TUI)
- **Modular Code Architecture:** Refactored monolithic 905-line ui/app.go view controller into 16 clean, maintainable view files.
- **Corrected Uptime Calculations:** Replaced static uptime display with dynamic calculation based on time.Since().

## [1.1.7] - 2026-07-09

### Changed (Community Edition CLI)
- **Non-Blocking Sentinel Warning:** Redesigned the configuration warning banner to display prominently above the TUI menu without blocking the execution of non-scan commands (Audits, Upgrades, Quits).
- **Graceful Scan Rejections:** Attempts to trigger log scans while unconfigured now fail gracefully with a single clean, non-blocking notification instead of aborting the script.

## [1.1.6] - 2026-07-09

### Added (Community Edition CLI)
- **Inline Menu Hints:** Added time-range inline suggestions directly inside the main menu items to improve user navigation.
- **Exit Upsell:** Seamlessly integrated licensing up-sell pathways on application quit to support commercial conversions.

## [1.1.5] - 2026-07-09

### Added (Community Edition CLI)
- **Guided Setup Sentinel:** Introduced CONFIGURED=true flag in .env.example to protect users from running audits or scans with default unconfigured values.
- **Dynamic Multi-Range Submenu:** Enabled time-range segmentation (Last 24 hours, Last 3 days, Last 7 days, Last 14 days, Current month).
- **Cross-Month Date Computations:** Implemented dynamic bash-based calculations for log filters during cross-month transitions.

## [1.1.4] - 2026-07-09

### Fixed (Community Edition CLI)
- **License Proxy Timeouts:** Added strict --connect-timeout 10 and --max-time 15 restraints on API validation requests to prevent persistent connection hangs during proxy outages.

## [1.1.3] - 2026-07-09

### Added (Community Edition CLI)
- **Real Proactive Hardening Audit:** Replaced legacy placeholder audit with live security checks for: SSH configurations, firewall status, fail2ban active jails, unattended package updates, and open internet ports with clear ✓/✗ reporting.

## [1.1.2] - 2026-07-09

### Added (Community Edition CLI)
- Centralized VERSION constant integration and TUI header rendering.

## [1.1.1] - 2026-07-09

### Added (Community Edition CLI)
- Interactive, first-run guided configuration experience inside the terminal.
- Fixed global redirects and pricing links to point to the official cybersecurity-analyst/#pricing domain.

## [1.1.0] - 2026-06-17

This is a major feature release focused on improving community accessibility, API reliability, and overall terminal usability.

### Added
- **Developer Gemini API Key Support (cybersecurity_analyst.sh):** Implemented native support for standard developer Gemini API Keys (sourced from Google AI Studio). This allows users to deploy and run the free script instantly without needing a GCP billing project or installing the Google Cloud CLI (gcloud).
- **Global Terminal Command csa (install.sh):** The universal installation script now automatically registers a system-wide csa command wrapper. You can now execute log scans or hardening audits from any directory on your server simply by typing csa.
- **Active Defense Safety Whitelist (remediation/firewall.go - PRO Track):** Integrated a strict IP validation engine that automatically intercepts and filters block requests targeting local loopback (127.0.0.1/::1), server-local interfaces, whitelisted office/developer IPs, or Cloudflare CDN ranges. This ensures zero risk of administrator lockout.
- **Concurrency Worker Pool (scanner/log_watcher.go - PRO Track):** Implemented a decoupled, thread-safe job queue (AIJobQueue with 1,000 capacity) to process log events safely.

### Changed
- **Robust JSON Parsing & Non-Streaming Flow:** Upgraded API requests from :streamGenerateContent to standard :generateContent. This resolves the fragile streaming chunk-by-chunk unmarshaling bug and ensures the entire report is reliably extracted from a single JSON response using jq.

### Fixed
- **Authentication Dependency Check:** Optimized dependency validation to allow running the script without gcloud when GEMINI_API_KEY is present.\n