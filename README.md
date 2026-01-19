# Claude Code Statusline

A custom statusline script for [Claude Code](https://claude.ai/code) that displays useful information at a glance.

## Features

- **Git branch** - Current branch name
- **Model ID** - Active Claude model
- **Version** - Claude Code version
- **Internet speed** - Download/upload speeds (cached, updates hourly or on network change)
- **Weather** - Current conditions and temperature with daily high/low
- **Context usage** - Progress bar showing context window usage (turns red at 80%)
- **SPM updates** - Swift Package Manager dependency update notifications

## Screenshot

```
⎇ main | claude-opus-4-5-20251101 | v1.0.45 | ↓ 150Mbps ↑ 12Mbps | sunny 72°F (78°F/65°F)
[████████████░░░░░░░░]
SPM Updates Available:
  SomePackage: 1.0.0 → 1.1.0 (https://github.com/owner/repo)
```

## Installation

1. Copy `statusline.sh` to `~/.claude/`:
   ```bash
   cp statusline.sh ~/.claude/statusline.sh
   chmod +x ~/.claude/statusline.sh
   ```

2. Merge the settings from `settings.json` into your `~/.claude/settings.json`. The key settings are:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline.sh"
     },
     "commands": {
       "speedtest": {
         "command": "bash ~/.claude/statusline.sh force-speedtest",
         "description": "Run a fresh internet speed test"
       }
     }
   }
   ```

   The included `settings.json` also contains recommended `permissions`, `includeCoAuthoredBy`, and `enabledPlugins` settings that you can optionally adopt.

3. Install dependencies:
   ```bash
   # jq (required for JSON parsing)
   brew install jq

   # speedtest-cli (optional, will auto-install if missing)
   pip3 install speedtest-cli
   # or
   brew install speedtest-cli
   ```

## Configuration

### Weather Location (Required)

The script defaults to San Francisco (Anthropic HQ). **Update this to your location** in `statusline.sh`:

```bash
# Find this section in get_weather() function (~line 413)
# CUSTOMIZE: Set your location coordinates and timezone
local latitude="37.790024"    # Your latitude
local longitude="-122.400833" # Your longitude
local timezone="America/Los_Angeles"  # Your timezone
```

**How to find your coordinates:**
- Visit [latlong.net](https://www.latlong.net/)
- Enter your city or zip code
- Copy the latitude and longitude values

**Common timezones:**
- `America/New_York` - Eastern
- `America/Chicago` - Central
- `America/Denver` - Mountain
- `America/Los_Angeles` - Pacific

### Primary Xcode Project (Optional)

If you want SPM update checking for a specific project regardless of your current directory, set the primary project path in `statusline.sh`:

```bash
# Find this section in check_spm_updates() function (~line 535)
# CUSTOMIZE: Set your primary Xcode project path (optional)
local primary_project="/Users/yourname/Projects/YourApp/YourApp.xcodeproj/project.pbxproj"
```

If left empty, the script will search for `.xcodeproj` files in the current directory and parent directories.

### GitHub Token (Optional)

For higher GitHub API rate limits (5000/hour vs 60/hour) when checking SPM updates, create a token file:

```bash
mkdir -p ~/.config/github
echo "your_github_token" > ~/.config/github/token
chmod 600 ~/.config/github/token
```

## Commands

### Manual Speed Test

Run a fresh speed test (bypasses cache):

```
/speedtest
```

Or from terminal:
```bash
~/.claude/statusline.sh force-speedtest
```

## Caching

| Feature | Cache Duration | Invalidation |
|---------|----------------|--------------|
| Speed test | 60 minutes | Network change (WiFi SSID or interface) |
| Weather | 20 minutes | Time-based |
| SPM updates | 4 hours | Project file modification |

## Context Progress Bar

The progress bar shows context window usage:
- **Below 80%**: Simple bar, no percentage shown
- **80% and above**: Bar turns red, percentage displayed

This gives you warning before Claude Code's auto-compact triggers (~95%).

## Dependencies

- **bash** - Shell interpreter
- **jq** - JSON parsing (required)
- **curl** - API requests (usually pre-installed)
- **speedtest-cli** - Internet speed testing (optional, auto-installs)

## macOS Specific

This script uses macOS-specific commands for:
- WiFi SSID detection (`airport`, `networksetup`)
- File timestamps (`stat -f`)

Modifications may be needed for Linux compatibility.

## License

This project is released under the MIT License. See the [LICENSE](https://github.com/DanielStormApps/claude-code-statusline/blob/main/LICENSE) file for more information.
