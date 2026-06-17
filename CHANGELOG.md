# Changelog - Cybersecurity Analyst Agent (Community Edition)

All notable changes to the **Cybersecurity Analyst Agent** open-source community log analyzer will be documented in this file.

## [1.1.0] - 2026-06-17

This is a major feature release focused on improving community accessibility, API reliability, and overall terminal usability.

### Added
- **Developer Gemini API Key Support (`cybersecurity_analyst.sh`):** Implemented native support for standard developer Gemini API Keys (sourced from Google AI Studio). This allows users to deploy and run the free script instantly without needing a GCP billing project or installing the Google Cloud CLI (`gcloud`).
- **Global Terminal Command `csa` (`install.sh`):** The universal installation script now automatically registers a system-wide `csa` command wrapper. You can now execute log scans or hardening audits from any directory on your server simply by typing `csa` (with options like `csa --scan` or `csa --interactive`).

### Changed
- **Robust JSON Parsing & Non-Streaming Flow:** Upgraded API requests from `:streamGenerateContent` to standard `:generateContent`. This resolves the fragile streaming chunk-by-chunk unmarshaling bug and ensures the entire report is reliably extracted from a single JSON response using `jq`.

### Fixed
- **Authentication Dependency Check:** Optimized dependency validation to allow running the script without `gcloud` when `GEMINI_API_KEY` is present.
