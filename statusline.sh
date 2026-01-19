#!/bin/bash

# Python user bin path (where pip installs user packages)
PYTHON_USER_BIN="$HOME/Library/Python/3.9/bin"

# Helper function to find speedtest-cli
find_speedtest_cli() {
    if command -v speedtest-cli >/dev/null 2>&1; then
        echo "speedtest-cli"
    elif [[ -x "$PYTHON_USER_BIN/speedtest-cli" ]]; then
        echo "$PYTHON_USER_BIN/speedtest-cli"
    else
        echo ""
    fi
}

# Check if this script is being called with "force-speedtest" argument
if [[ "$1" == "force-speedtest" ]]; then
    # Manual speed test mode
    cache_file="/tmp/.claude_speedtest_cache"
    lock_file="/tmp/.claude_speedtest_lock"
    
    echo "Running fresh speed test..."
    echo "This may take 30-60 seconds..."
    
    # Clear existing cache to force fresh test
    rm -f "$cache_file" 2>/dev/null
    
    # Remove any stale lock
    rm -f "$lock_file" 2>/dev/null
    
    # Check if speedtest-cli is available
    SPEEDTEST_CMD=$(find_speedtest_cli)
    if [[ -z "$SPEEDTEST_CMD" ]]; then
        echo "Error: speedtest-cli not found. Installing..."

        if command -v pip3 >/dev/null 2>&1; then
            echo "Installing via pip3..."
            pip3 install speedtest-cli
        elif command -v brew >/dev/null 2>&1; then
            echo "Installing via brew..."
            brew install speedtest-cli
        else
            echo "Error: Neither pip3 nor brew found. Please install speedtest-cli manually:"
            echo "  pip3 install speedtest-cli"
            echo "  # or"
            echo "  brew install speedtest-cli"
            exit 1
        fi

        # Check if installation was successful
        SPEEDTEST_CMD=$(find_speedtest_cli)
        if [[ -z "$SPEEDTEST_CMD" ]]; then
            echo "Error: Failed to install speedtest-cli"
            exit 1
        fi
    fi
    
    # Get current network for cache (reuse existing function)
    source_get_network_id() {
        local network_id=""
        
        # Try to get WiFi SSID using airport command
        local ssid=$((/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | grep " SSID" | awk '{print $2}') 2>/dev/null)
        
        # Fallback to networksetup if airport fails
        if [[ -z "$ssid" ]]; then
            ssid=$((networksetup -getairportnetwork en0 2>/dev/null | cut -d: -f2 | sed 's/^ *//') 2>/dev/null)
        fi
        
        if [[ -n "$ssid" && "$ssid" != "You are not associated with an AirPort network." ]]; then
            network_id="wifi:$ssid"
        else
            # For ethernet or other connections, use interface info
            local interface_info=$(route get default 2>/dev/null | grep interface | awk '{print $2}' 2>/dev/null)
            if [[ -n "$interface_info" ]]; then
                network_id="interface:$interface_info"
            else
                network_id="unknown"
            fi
        fi
        
        echo "$network_id"
    }
    
    current_network=$(source_get_network_id)
    current_time=$(date +%s)
    
    # Create lock file to prevent concurrent tests
    touch "$lock_file"
    
    # Run speed test with detailed output
    echo ""
    echo "Testing internet speed..."
    speedtest_result=$($SPEEDTEST_CMD --simple --timeout 60 2>&1)
    speedtest_exit_code=$?
    
    # Remove lock file
    rm -f "$lock_file"
    
    if [[ $speedtest_exit_code -eq 0 && -n "$speedtest_result" ]]; then
        echo ""
        echo "Speed test results:"
        echo "===================="
        echo "$speedtest_result"
        
        # Parse download and upload speeds for cache
        download=$(echo "$speedtest_result" | grep "Download:" | awk '{print $2}' | sed 's/[^0-9.]//g')
        upload=$(echo "$speedtest_result" | grep "Upload:" | awk '{print $2}' | sed 's/[^0-9.]//g')
        
        if [[ -n "$download" && -n "$upload" ]]; then
            # Format speeds as integers for status line
            down_int=$(printf "%.0f" "$download" 2>/dev/null || echo "0")
            up_int=$(printf "%.0f" "$upload" 2>/dev/null || echo "0")
            
            speed_display="↓ ${down_int}Mbps ↑ ${up_int}Mbps"
            
            # Cache the result
            {
                echo "$current_time"
                echo "$current_network"
                echo "$speed_display"
            } > "$cache_file"
            
            echo ""
            echo "Results cached for status line display."
            echo "Status line will show: $speed_display"
        fi
    else
        echo ""
        echo "Error: Speed test failed"
        if [[ -n "$speedtest_result" ]]; then
            echo "Error details: $speedtest_result"
        fi
        exit 1
    fi
    
    exit 0
fi

# Check if this script is being called with "speed-check" argument for natural language detection
if [[ "$1" == "speed-check" ]]; then
    # Get input either from second argument or stdin
    user_input=""
    if [[ $# -gt 1 ]]; then
        shift  # Remove first argument
        user_input="$*"
    elif [[ ! -t 0 ]]; then
        user_input=$(cat)
    fi
    
    # If no input, just run the speed test
    if [[ -z "$user_input" ]]; then
        bash ~/.claude/statusline.sh force-speedtest
        exit 0
    fi
    
    # Convert to lowercase for pattern matching
    user_input_lower=$(echo "$user_input" | tr '[:upper:]' '[:lower:]')
    
    # Keywords that trigger a speed test
    speed_test_patterns=(
        "run speed test"
        "speed test"
        "check speed"
        "test internet speed"
        "internet speed test"
        "test my speed"
        "check internet speed"
        "run speedtest"
        "speedtest please"
        "test speed"
        "speed check"
        "check my speed"
        "what's my speed"
        "how fast is my internet"
    )
    
    # Check if any pattern matches
    for pattern in "${speed_test_patterns[@]}"; do
        if [[ "$user_input_lower" == *"$pattern"* ]]; then
            echo "Detected speed test request: '$user_input'"
            bash ~/.claude/statusline.sh force-speedtest
            exit 0
        fi
    done
    
    # No speed test pattern found
    echo "No speed test pattern detected in: '$user_input'"
    echo "Try phrases like 'run speed test', 'check my speed', or 'test internet speed'"
    exit 1
fi

# Read JSON input from stdin for normal status line mode
input=$(cat)

# Extract data from JSON input
model_id=$(echo "$input" | jq -r '.model.id')
version=$(echo "$input" | jq -r '.version')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
context_used_percentage=$(echo "$input" | jq -r '.context_window.used_percentage')

# Get git branch name (skip locks to avoid delays)
cd "$current_dir" 2>/dev/null
git_branch=$(git branch --show-current 2>/dev/null || echo "no-git")

# Get current network identifier for cache invalidation
get_network_id() {
    local network_id=""
    
    # Try to get WiFi SSID using airport command
    local ssid=$((/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | grep " SSID" | awk '{print $2}') 2>/dev/null)
    
    # Fallback to networksetup if airport fails
    if [[ -z "$ssid" ]]; then
        ssid=$((networksetup -getairportnetwork en0 2>/dev/null | cut -d: -f2 | sed 's/^ *//') 2>/dev/null)
    fi
    
    if [[ -n "$ssid" && "$ssid" != "You are not associated with an AirPort network." ]]; then
        network_id="wifi:$ssid"
    else
        # For ethernet or other connections, use interface info
        local interface_info=$(route get default 2>/dev/null | grep interface | awk '{print $2}' 2>/dev/null)
        if [[ -n "$interface_info" ]]; then
            network_id="interface:$interface_info"
        else
            network_id="unknown"
        fi
    fi
    
    echo "$network_id"
}

# Get actual internet speed using speedtest with caching
get_speed_test() {
    local cache_file="/tmp/.claude_speedtest_cache"
    local lock_file="/tmp/.claude_speedtest_lock"
    local cache_max_age=3600  # 60 minutes in seconds
    local current_time=$(date +%s)
    local current_network=$(get_network_id)
    local use_cache=false
    
    # Check if cache exists and is fresh
    if [[ -f "$cache_file" ]]; then
        local cache_timestamp=$(head -1 "$cache_file" 2>/dev/null)
        local cached_network=$(sed -n '2p' "$cache_file" 2>/dev/null)
        
        if [[ -n "$cache_timestamp" && "$cache_timestamp" =~ ^[0-9]+$ ]]; then
            local cache_age=$((current_time - cache_timestamp))
            
            # Use cache only if it's fresh AND network hasn't changed
            if [[ $cache_age -lt $cache_max_age && "$cached_network" == "$current_network" ]]; then
                use_cache=true
            fi
        fi
    fi
    
    # Use cached data if fresh
    if [[ "$use_cache" == true ]]; then
        # Read cached speed data (skip timestamp and network lines)
        local cached_result=$(tail -n +3 "$cache_file" 2>/dev/null)
        if [[ -n "$cached_result" ]]; then
            printf " | %s" "$cached_result"
            return
        fi
    fi
    
    # Check if speedtest is running to avoid multiple concurrent tests
    if [[ -f "$lock_file" ]]; then
        local lock_age=$((current_time - $(stat -f %m "$lock_file" 2>/dev/null || echo "0")))
        if [[ $lock_age -lt 120 ]]; then  # Lock timeout after 2 minutes
            # Show cached result or placeholder if test is running
            local cached_result=$(tail -n +3 "$cache_file" 2>/dev/null)
            if [[ -n "$cached_result" ]]; then
                printf " | %s (testing...)" "$cached_result"
            else
                printf " | ↓ --Mbps ↑ --Mbps (testing...)"
            fi
            return
        else
            # Remove stale lock
            rm -f "$lock_file" 2>/dev/null
        fi
    fi
    
    # Check if speedtest-cli is available
    local speedtest_cmd=$(find_speedtest_cli)
    if [[ -z "$speedtest_cmd" ]]; then
        # Try to install speedtest-cli using pip3 or brew
        if command -v pip3 >/dev/null 2>&1; then
            # Run installation in background to not block status line
            (
                touch "$lock_file"
                pip3 install speedtest-cli >/dev/null 2>&1
                rm -f "$lock_file"
            ) &
        elif command -v brew >/dev/null 2>&1; then
            # Run installation in background to not block status line
            (
                touch "$lock_file"
                brew install speedtest-cli >/dev/null 2>&1
                rm -f "$lock_file"
            ) &
        fi
        printf " | ↓ --Mbps ↑ --Mbps (installing...)"
        return
    fi
    
    # Run speed test in background if cache is stale
    if [[ "$use_cache" != true ]]; then
        # Start background speed test
        (
            # Create lock file
            touch "$lock_file"
            
            # Run speed test and parse results
            local speedtest_result
            speedtest_result=$($speedtest_cmd --simple --timeout 60 2>/dev/null)
            
            if [[ $? -eq 0 && -n "$speedtest_result" ]]; then
                # Parse download and upload speeds
                local download upload
                download=$(echo "$speedtest_result" | grep "Download:" | awk '{print $2}' | sed 's/[^0-9.]//g')
                upload=$(echo "$speedtest_result" | grep "Upload:" | awk '{print $2}' | sed 's/[^0-9.]//g')
                
                if [[ -n "$download" && -n "$upload" ]]; then
                    # Format speeds as integers for cleaner display
                    local down_int up_int
                    down_int=$(printf "%.0f" "$download" 2>/dev/null || echo "0")
                    up_int=$(printf "%.0f" "$upload" 2>/dev/null || echo "0")
                    
                    local speed_display="↓ ${down_int}Mbps ↑ ${up_int}Mbps"
                    
                    # Cache the result with network identifier
                    {
                        echo "$current_time"
                        echo "$current_network"
                        echo "$speed_display"
                    } > "$cache_file"
                fi
            fi
            
            # Remove lock file
            rm -f "$lock_file"
        ) &
    fi
    
    # Show cached result or placeholder while test runs
    local cached_result=$(tail -n +3 "$cache_file" 2>/dev/null)
    if [[ -n "$cached_result" ]]; then
        printf " | %s" "$cached_result"
    else
        printf " | ↓ --Mbps ↑ --Mbps"
    fi
}

# Get context usage progress bar
get_context_progress_bar() {
    local used_percentage="$1"
    local bar_char="█"
    local empty_char="░"
    local bar=""
    local color_start=""
    local color_end="\033[0m"

    # Handle missing or invalid percentage
    if [[ -z "$used_percentage" || "$used_percentage" == "null" ]]; then
        return
    fi

    # Round to integer for display and calculations
    local percent_int=$(printf "%.0f" "$used_percentage" 2>/dev/null || echo "0")

    # Set bar width and format based on threshold
    local bar_width
    local show_percentage=false
    if [[ $percent_int -ge 80 ]]; then
        bar_width=16
        show_percentage=true
        color_start="\033[31m"  # Red
    else
        bar_width=20
    fi

    # Calculate filled width
    local filled_width=$((percent_int * bar_width / 100))
    local empty_width=$((bar_width - filled_width))

    # Build the progress bar
    for ((i=0; i<filled_width; i++)); do
        bar+="$bar_char"
    done
    for ((i=0; i<empty_width; i++)); do
        bar+="$empty_char"
    done

    # Output the progress bar (with percentage only if >= 80%)
    if [[ "$show_percentage" == true ]]; then
        printf "\n%b[%s] %d%%%b" "$color_start" "$bar" "$percent_int" "$color_end"
    else
        printf "\n[%s]" "$bar"
    fi
}

# Get weather information with caching using Open-Meteo API
get_weather() {
    local cache_file="/tmp/.claude_weather_cache"
    local cache_max_age=1200  # 20 minutes in seconds
    local current_time=$(date +%s)
    local weather_json current_temp high_temp low_temp weather_code weather_text
    local use_cache=false
    
    # CUSTOMIZE: Set your location coordinates and timezone
    # Default: San Francisco (Anthropic HQ) - Update these for your location
    # Find coordinates at: https://www.latlong.net/
    local latitude="37.790024"
    local longitude="-122.400833"
    local timezone="America/Los_Angeles"
    
    # Check if cache exists and is fresh
    if [[ -f "$cache_file" ]]; then
        local cache_timestamp=$(head -1 "$cache_file" 2>/dev/null)
        if [[ -n "$cache_timestamp" && "$cache_timestamp" =~ ^[0-9]+$ ]]; then
            local cache_age=$((current_time - cache_timestamp))
            if [[ $cache_age -lt $cache_max_age ]]; then
                use_cache=true
            fi
        fi
    fi
    
    # Use cached data if fresh, otherwise fetch new data
    if [[ "$use_cache" == true ]]; then
        # Read cached weather data (skip timestamp line)
        weather_json=$(tail -n +2 "$cache_file" 2>/dev/null)
    else
        # Fetch fresh weather data from Open-Meteo API
        # Get current conditions plus daily high/low
        local api_url="https://api.open-meteo.com/v1/forecast?latitude=${latitude}&longitude=${longitude}&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit&timezone=${timezone}&forecast_days=1"
        weather_json=$(curl -s -m 3 "$api_url" 2>/dev/null)
        
        # Cache the data if we got a valid response
        if [[ -n "$weather_json" && "$weather_json" != *"error"* ]]; then
            # Store timestamp and weather data in cache file
            {
                echo "$current_time"
                echo "$weather_json"
            } > "$cache_file"
        fi
    fi
    
    # Process weather data (whether from cache or fresh fetch)
    if [[ -n "$weather_json" && "$weather_json" != *"error"* ]]; then
        # Extract data using jq
        current_temp=$(echo "$weather_json" | jq -r '.current.temperature_2m' 2>/dev/null)
        weather_code=$(echo "$weather_json" | jq -r '.current.weather_code' 2>/dev/null)
        high_temp=$(echo "$weather_json" | jq -r '.daily.temperature_2m_max[0]' 2>/dev/null)
        low_temp=$(echo "$weather_json" | jq -r '.daily.temperature_2m_min[0]' 2>/dev/null)
        
        # Check if we got valid data
        if [[ -n "$current_temp" && -n "$weather_code" && -n "$high_temp" && -n "$low_temp" && \
              "$current_temp" != "null" && "$weather_code" != "null" && "$high_temp" != "null" && "$low_temp" != "null" ]]; then
            
            # Map weather codes to text descriptions
            case "$weather_code" in
                0) weather_text="sunny" ;;
                1|2) weather_text="partly-cloudy" ;;
                3) weather_text="cloudy" ;;
                45|48) weather_text="fog" ;;
            
                # drizzle (includes freezing drizzle 56/57)
                51|53|55|56|57) weather_text="drizzle" ;;
            
                # freezing rain (not drizzle)
                66|67) weather_text="freezing-rain" ;;
            
                # rain (non-freezing)
                61|63|65|80|81|82) weather_text="rain" ;;
            
                # keep other groups
                71|73|75|77|85|86) weather_text="snow" ;;
                95|96|99) weather_text="thunderstorm" ;;
                *) weather_text="fair" ;;
            esac
            
            # Round temperatures to integers for display
            current_temp_int=$(printf "%.0f" "$current_temp" 2>/dev/null || echo "$current_temp")
            high_temp_int=$(printf "%.0f" "$high_temp" 2>/dev/null || echo "$high_temp")
            low_temp_int=$(printf "%.0f" "$low_temp" 2>/dev/null || echo "$low_temp")
            
            # Format: [condition] [temp]°F ([high]°F/[low]°F)
            printf " | %s %s°F (%s°F/%s°F)" "$weather_text" "$current_temp_int" "$high_temp_int" "$low_temp_int"
        else
            # Fallback if JSON parsing fails
            printf " | weather --"
        fi
    else
        # Fallback if weather service is unavailable
        printf " | weather --"
    fi
}

# Check for SPM package updates
check_spm_updates() {
    local cache_file="/tmp/.claude_spm_cache"
    local session_marker="/tmp/.claude_session_marker"
    local cache_max_age=14400  # 4 hours in seconds
    local current_time=$(date +%s)
    local project_pbxproj=""
    local use_cache=false
    
    # Check if this is a new Claude Code session
    local is_new_session=false
    if [[ ! -f "$session_marker" ]]; then
        is_new_session=true
        # Create session marker with current time
        echo "$current_time" > "$session_marker"
    else
        # Check if session marker is stale (older than 4 hours - matches cache TTL)
        local session_start=$(cat "$session_marker" 2>/dev/null || echo "0")
        # Validate session_start is numeric before arithmetic (guards against corrupted cache)
        if [[ "$session_start" =~ ^[0-9]+$ ]]; then
            local session_age=$((current_time - session_start))
            if [[ $session_age -gt 14400 ]]; then
                is_new_session=true
                # Update session marker
                echo "$current_time" > "$session_marker"
            fi
        else
            # Session marker is corrupted, treat as new session
            is_new_session=true
            echo "$current_time" > "$session_marker"
        fi
    fi
    
    # CUSTOMIZE: Set your primary Xcode project path (optional)
    # If set, this project will be checked first for SPM updates
    # Example: "/Users/yourname/Projects/your-app/YourApp.xcodeproj/project.pbxproj"
    local primary_project=""

    # Find .xcodeproj - check primary project first, then current/parent directories
    local search_dir="$(pwd)"

    # First check primary project if configured
    if [[ -n "$primary_project" && -f "$primary_project" ]]; then
        project_pbxproj="$primary_project"
    else
        # Fall back to searching current and parent directories
        local max_depth=5
        local depth=0

        while [[ $depth -lt $max_depth && "$search_dir" != "/" ]]; do
            if [[ -d "$search_dir" ]]; then
                # Check current directory for any .xcodeproj
                local xcodeproj=$(find "$search_dir" -maxdepth 1 -name "*.xcodeproj" -type d 2>/dev/null | head -1)
                if [[ -n "$xcodeproj" ]]; then
                    project_pbxproj="$xcodeproj/project.pbxproj"
                    break
                fi
            fi
            search_dir=$(dirname "$search_dir")
            ((depth++))
        done
    fi
    
    # Exit early if no .xcodeproj found
    [[ ! -f "$project_pbxproj" ]] && return
    
    local project_mod_time=$(stat -f %m "$project_pbxproj" 2>/dev/null || echo "0")

    # Check if cache exists and is fresh
    if [[ -f "$cache_file" ]]; then
        local cache_timestamp=$(head -1 "$cache_file" 2>/dev/null)
        local cached_mod_time=$(sed -n '2p' "$cache_file" 2>/dev/null)
        
        if [[ -n "$cache_timestamp" && "$cache_timestamp" =~ ^[0-9]+$ && 
              -n "$cached_mod_time" && "$cached_mod_time" =~ ^[0-9]+$ ]]; then
            local cache_age=$((current_time - cache_timestamp))
            
            # Use cache if fresh and project hasn't been modified (unless it's a new session)
            if [[ $cache_age -lt $cache_max_age && "$cached_mod_time" == "$project_mod_time" ]]; then
                use_cache=true
            fi
        fi
    fi
    
    # Use cached data if available
    if [[ "$use_cache" == true ]]; then
        local cached_updates=$(tail -n +3 "$cache_file" 2>/dev/null)
        if [[ -n "$cached_updates" ]]; then
            # Get cache timestamp and format it
            local cache_timestamp=$(head -1 "$cache_file" 2>/dev/null)
            local time_diff=$((current_time - cache_timestamp))
            # Use absolute value to avoid negative times
            [[ $time_diff -lt 0 ]] && time_diff=$((-time_diff))
            local last_checked=""

            if [[ $time_diff -lt 3600 ]]; then
                last_checked=" (checked $((time_diff / 60))m ago)"
            elif [[ $time_diff -lt 86400 ]]; then
                last_checked=" (checked $((time_diff / 3600))h ago)"
            else
                last_checked=" (checked $((time_diff / 86400))d ago)"
            fi
            
            # Display cached results with timestamp
            printf "\n\033[33m%s\033[90m%s\033[0m" "$cached_updates" "$last_checked"
        fi
        return
    fi
    
    # Parse project.pbxproj for SPM packages
    local smp_packages=$(awk '
        /XCRemoteSwiftPackageReference/ {
            in_package = 1
            url = ""
            version = ""
        }
        in_package && /repositoryURL = / {
            gsub(/.*repositoryURL = "/, "")
            gsub(/";.*/, "")
            url = $0
        }
        in_package && (/version = / || /minimumVersion = /) {
            # Handle both quoted and unquoted versions
            if (/version = /) {
                gsub(/.*version = /, "")
            } else if (/minimumVersion = /) {
                gsub(/.*minimumVersion = /, "")
            }
            # Remove quotes if present, then remove semicolon and any trailing content
            gsub(/"/, "")
            gsub(/;.*/, "")
            version = $0
        }
        in_package && /};$/ {
            if (url != "" && version != "" && match(url, /github\.com/)) {
                print url "|" version
            }
            in_package = 0
        }
    ' "$project_pbxproj" 2>/dev/null)
    
    # Exit if no packages found
    [[ -z "$smp_packages" ]] && return
    
    local updates_found=""
    local update_count=0
    local rate_limited=false

    # Read GitHub token for authenticated requests (5000/hour vs 60/hour)
    local github_token=""
    local auth_header=""
    if [[ -f "$HOME/.config/github/token" ]]; then
        github_token=$(cat "$HOME/.config/github/token" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "$github_token" ]]; then
            auth_header="Authorization: Bearer $github_token"
        fi
    fi

    # Check each package for updates
    while read -r line; do
        repo_url=$(echo "$line" | cut -d'|' -f1)
        current_version=$(echo "$line" | cut -d'|' -f2)
        [[ -z "$repo_url" || -z "$current_version" ]] && continue

        # Extract package name
        local package_name=$(basename "$repo_url" .git)

        # Extract owner/repo from GitHub URL (handles both HTTPS and SSH)
        local github_path=$(echo "$repo_url" | sed -E 's|^https://github\.com/||; s|^git@github\.com:||; s|\.git$||')
        [[ ! "$github_path" =~ ^[^/]+/[^/]+$ ]] && continue

        # Get latest release from GitHub API with rate limit detection
        local api_response
        if [[ -n "$auth_header" ]]; then
            api_response=$(curl -s -i -m 5 -H "$auth_header" "https://api.github.com/repos/$github_path/releases/latest" 2>/dev/null)
        else
            api_response=$(curl -s -i -m 5 "https://api.github.com/repos/$github_path/releases/latest" 2>/dev/null)
        fi

        # Check for rate limit (403 status with rate limit message)
        if echo "$api_response" | head -20 | grep -q "^HTTP.*403"; then
            if echo "$api_response" | grep -qi "rate limit"; then
                rate_limited=true
                break
            fi
        fi

        # Extract version from response body (skip headers, handle CRLF)
        local latest_version=$(echo "$api_response" | tr -d '\r' | sed '1,/^$/d' | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//')

        # If releases API returned 404 (no releases), fall back to tags API
        # This handles repos like RevenueCat/purchases-ios-spm that only use tags
        if [[ -z "$latest_version" ]]; then
            if echo "$api_response" | head -5 | grep -q "^HTTP.*404"; then
                local tags_response
                if [[ -n "$auth_header" ]]; then
                    tags_response=$(curl -s -m 5 -H "$auth_header" "https://api.github.com/repos/$github_path/tags?per_page=20" 2>/dev/null)
                else
                    tags_response=$(curl -s -m 5 "https://api.github.com/repos/$github_path/tags?per_page=20" 2>/dev/null)
                fi

                # Extract semver tags only (filter out non-semver like "playgrounds-test-*")
                # Match patterns like "5.51.1", "v5.51.1", "1.2.3", etc.
                latest_version=$(echo "$tags_response" | jq -r '.[].name' 2>/dev/null | \
                    grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | \
                    sed 's/^v//' | \
                    sort -t. -k1,1nr -k2,2nr -k3,3nr | \
                    head -1)
            fi
        fi

        [[ -z "$latest_version" ]] && continue

        # Compare versions (simple semantic version comparison)
        local current_clean=$(echo "$current_version" | sed 's/^v//')
        local latest_clean="$latest_version"

        # Skip if versions are the same
        [[ "$current_clean" == "$latest_clean" ]] && continue

        # Simple version comparison - convert to comparable numbers
        local current_num=$(echo "$current_clean" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}' 2>/dev/null)
        local latest_num=$(echo "$latest_clean" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}' 2>/dev/null)

        # Use 10# prefix to force decimal interpretation (avoid octal with leading zeros)
        if [[ -n "$current_num" && -n "$latest_num" && "10#$latest_num" -gt "10#$current_num" ]]; then
            if [[ -n "$updates_found" ]]; then
                updates_found+="\n"
            fi
            updates_found+="  $package_name: $current_clean → $latest_clean ($repo_url)"
            ((update_count++))
        fi
    done <<< "$smp_packages"

    # If rate limited, use cached data instead of overwriting cache
    if [[ "$rate_limited" == true ]]; then
        # Show cached results with rate limit indicator
        if [[ -f "$cache_file" ]]; then
            local cached_updates=$(tail -n +3 "$cache_file" 2>/dev/null)
            if [[ -n "$cached_updates" ]]; then
                local cache_timestamp=$(head -1 "$cache_file" 2>/dev/null)
                local time_diff=$((current_time - cache_timestamp))
                # Use absolute value to avoid negative times
                [[ $time_diff -lt 0 ]] && time_diff=$((-time_diff))
                local last_checked=""

                if [[ $time_diff -lt 3600 ]]; then
                    last_checked=" (cached $((time_diff / 60))m ago, rate limited)"
                elif [[ $time_diff -lt 86400 ]]; then
                    last_checked=" (cached $((time_diff / 3600))h ago, rate limited)"
                else
                    last_checked=" (cached $((time_diff / 86400))d ago, rate limited)"
                fi

                printf "\n\033[33m%s\033[90m%s\033[0m" "$cached_updates" "$last_checked"
            fi
        fi
        return
    fi

    # Cache the results (only if not rate limited)
    {
        echo "$current_time"
        echo "$project_mod_time"
        if [[ -n "$updates_found" ]]; then
            echo "SPM Updates Available:"
            echo -e "$updates_found"
        fi
    } > "$cache_file"

    # Output updates if any found
    if [[ -n "$updates_found" ]]; then
        printf "\n\033[33mSPM Updates Available:\n%b\033[0m" "$updates_found"
    else
        # If no updates found, show cached results if available
        if [[ -f "$cache_file" ]]; then
            local cached_updates=$(tail -n +3 "$cache_file" 2>/dev/null)
            if [[ -n "$cached_updates" ]]; then
                local cache_timestamp=$(head -1 "$cache_file" 2>/dev/null)
                local time_diff=$((current_time - cache_timestamp))
                # Use absolute value to avoid negative times
                [[ $time_diff -lt 0 ]] && time_diff=$((-time_diff))
                local last_checked=""

                if [[ $time_diff -lt 3600 ]]; then
                    last_checked=" (checked $((time_diff / 60))m ago)"
                elif [[ $time_diff -lt 86400 ]]; then
                    last_checked=" (checked $((time_diff / 3600))h ago)"
                else
                    last_checked=" (checked $((time_diff / 86400))d ago)"
                fi

                printf "\n\033[33m%s\033[90m%s\033[0m" "$cached_updates" "$last_checked"
            fi
        fi
    fi
}

# Format and output the status line
printf "⎇ %s | %s | v%s%s%s" \
    "$git_branch" \
    "$model_id" \
    "$version" \
    "$(get_speed_test)" \
    "$(get_weather)"

# Display context usage progress bar
get_context_progress_bar "$context_used_percentage"

# Check and display SPM updates on separate line
check_spm_updates
