#!/bin/zsh
#
# fetch_nyt_range.zsh
#
# Fetches New York Times front pages for a date range and creates
# Day One journal entries for each day in the range.
#
# Author: Paul Mayne
# Last Updated: 2024-03-14

# -----------------------------------------------------------------------------
# Function Definitions
# -----------------------------------------------------------------------------

# Display usage information when help is requested or invalid args provided
function usage() {
  # Get the actual script name for better examples
  local script=$(basename "$0")
  
  # Display help information  
  echo "Usage: $script DATE_SPEC [END_DATE] [options]"
  echo ""
  echo "Arguments:"
  echo "  DATE_SPEC:  Date to fetch in YYYY-MM-DD format or YYYY-MM format (for entire month)"
  echo "  END_DATE:   Optional last date for a range (YYYY-MM-DD format)"
  echo ""
  echo "Options:"
  echo "  --sleep SEC      Sleep time between API calls in seconds (default: 7)"
  echo ""
  echo "Options: (passed to nyt_to_dayone.zsh)"
  echo "  --pdf            Also attach the PDF file (JPG only by default)"
  echo "  --full-summary   Include comprehensive NYT content analysis"
  echo "  --journal NAME   Specify Day One journal name (default: New York Times)"
  echo ""
  echo "Examples:"
  echo "  $script 2025-01                                # Fetch all of January 2025"
  echo "  $script 2025-01-01 2025-01-31                  # Fetch a custom date range" 
  echo "  $script 2025-01-15 2025-02-15                  # Fetch a custom date range"
  echo "  $script 2025-01 --pdf                          # Include PDF attachments"
  echo "  $script 2025-01-01 2025-01-31 --sleep 3        # Use shorter delay between API calls"
  echo "  $script 2025-01 --journal \"History\"            # Use specific journal"
  
  exit 1
}

# -----------------------------------------------------------------------------
# Input Validation
# -----------------------------------------------------------------------------

# Default settings
SLEEP_TIME=7   # Default sleep between API calls

# Check if required arguments are provided
if [[ $# -lt 1 ]]; then
  echo "Error: Missing required date argument"
  usage
fi

# Store date argument
DATE_SPEC="$1"
shift

# Handle different date format cases
if [[ "$DATE_SPEC" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
  # Year-Month format: process entire month
  # Extract year and month using substring
  YEAR=${DATE_SPEC:0:4}
  MONTH=${DATE_SPEC:5:2}
  
  # Calculate first day of month
  START_DATE="$YEAR-$MONTH-01"
  
  # Calculate last day of month based on which month it is
  case "$MONTH" in
    "01"|"03"|"05"|"07"|"08"|"10"|"12")
      # 31 days
      END_DATE="$YEAR-$MONTH-31"
      ;;
    "04"|"06"|"09"|"11")
      # 30 days
      END_DATE="$YEAR-$MONTH-30"
      ;;
    "02")
      # February - check for leap year
      # Leap year if divisible by 4, except for century years not divisible by 400
      if [[ $(( YEAR % 4 )) -eq 0 && ( $(( YEAR % 100 )) -ne 0 || $(( YEAR % 400 )) -eq 0 ) ]]; then
        # Leap year - 29 days
        END_DATE="$YEAR-$MONTH-29"
      else
        # Not a leap year - 28 days
        END_DATE="$YEAR-$MONTH-28"
      fi
      ;;
  esac
  
  echo "Processing entire month: $YEAR-$MONTH (from $START_DATE to $END_DATE)"
  
elif [[ "$DATE_SPEC" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  # Full date format: expected to be a range if second argument is present
  START_DATE="$DATE_SPEC"
  
  # Check for end date argument
  if [[ $# -gt 0 && "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    END_DATE="$1"
    shift
  else
    # No end date provided, use the start date as the end date (single day)
    END_DATE="$START_DATE"
  fi
  
else
  echo "Error: DATE_SPEC must be in YYYY-MM or YYYY-MM-DD format"
  usage
fi

# -----------------------------------------------------------------------------
# Date Range Processing
# -----------------------------------------------------------------------------

# Convert dates to seconds since epoch for comparison and iteration
START_SECONDS=$(date -j -f "%Y-%m-%d" "$START_DATE" "+%s")
END_SECONDS=$(date -j -f "%Y-%m-%d" "$END_DATE" "+%s")

# Validate date range order
if (( START_SECONDS > END_SECONDS )); then
  echo "Error: START_DATE must be before END_DATE"
  usage
fi

# Check for date limitations - NYT PDFs are only reliably available from July 2012 onwards
LIMIT_DATE_SECONDS=$(date -j -f "%Y-%m-%d" "2012-07-01" +%s)
if (( START_SECONDS < LIMIT_DATE_SECONDS )); then
  echo "Error: NYT front page PDFs are only reliably available from July 2012 onwards"
  echo "The requested start date ($START_DATE) is too early for this service"
  exit 1
fi

# Calculate number of days in the range (inclusive)
DAYS_IN_RANGE=$(( (END_SECONDS - START_SECONDS) / 86400 + 1 ))

# Display processing information
echo "Fetching NYT entries from $START_DATE to $END_DATE ($DAYS_IN_RANGE days)..."
echo "Sleep time between API calls: $SLEEP_TIME seconds"

# Parse command line arguments for sleep parameter
EXTRA_ARGS=()  # Initialize empty array for args to pass to nyt_to_dayone.zsh

# Process arguments to capture sleep parameter and pass the rest to nyt_to_dayone.zsh
while (( $# > 0 )); do
  case "$1" in
    --sleep)
      # Require sleep time argument
      if (( $# > 1 )); then
        SLEEP_TIME="$2"
        shift 2
      else
        echo "Error: --sleep requires a value in seconds"
        usage
      fi
      ;;
    # Known options that need to be passed to nyt_to_dayone.zsh
    --pdf|--full-summary|--journal|--no-tag|--tag)
      if [[ "$1" == "--journal" || "$1" == "--tag" ]] && (( $# > 1 )); then
        # These options require a value
        EXTRA_ARGS+=("$1" "$2")
        shift 2
      else
        # Flag options without a value
        EXTRA_ARGS+=("$1")
        shift
      fi
      ;;
    *)
      # Unknown option - store for passing to the individual day script
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Process Each Day in Range
# -----------------------------------------------------------------------------

# Array to collect all Day One entry URLs
CREATED_ENTRIES=()

# Function to process a single date
function process_date() {
  local date_seconds=$1
  local day_number=$2
  local total_days=$3
  
  # Format date in YYYY-MM-DD format
  local date_str=$(date -j -f "%s" "$date_seconds" "+%Y-%m-%d")
  
  # Show progress
  echo "Processing: $date_str ($day_number of $total_days)"
  
  # Build and execute the command
  local cmd="$PWD/nyt_to_dayone.zsh \"$date_str\""
  [[ ${#EXTRA_ARGS[@]} -gt 0 ]] && cmd+=" ${EXTRA_ARGS[*]}"
  
  # Execute and capture output
  local output=$(eval $cmd)
  
  # Display the captured output
  echo "$output"
  
  # Extract the Day One deep link if present
  local deep_link=$(echo "$output" | grep "dayone://view?entryId=")
  [[ -n "$deep_link" ]] && CREATED_ENTRIES+=("$date_str: $deep_link")
  
  # Return success
  return 0
}

# Process each day in the range
CURRENT_SECONDS=$START_SECONDS
for ((day=1; day<=DAYS_IN_RANGE; day++)); do
  # Process this date
  process_date "$CURRENT_SECONDS" "$day" "$DAYS_IN_RANGE"
  
  # Move to next day
  CURRENT_SECONDS=$((CURRENT_SECONDS + 86400))
  
  # Add delay to avoid API rate limiting (skip for last date)
  if [[ $day -lt $DAYS_IN_RANGE ]]; then
    echo "Waiting $SLEEP_TIME seconds before next request (to avoid API rate limiting)..."
    sleep $SLEEP_TIME
  fi
done

# -----------------------------------------------------------------------------
# Display Results Summary
# -----------------------------------------------------------------------------

# Show completion message
echo "All entries from $START_DATE to $END_DATE created successfully!"

# Display all created entry deep links for easy access
if [[ ${#CREATED_ENTRIES[@]} -gt 0 ]]; then
  echo ""
  echo "Created Entries:"
  for entry in "${CREATED_ENTRIES[@]}"; do
    echo "$entry"
  done
fi