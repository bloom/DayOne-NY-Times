#!/bin/zsh
#
# fetch_historical_events.zsh
#
# Creates Day One journal entries for historical events using 
# New York Times front pages from the day after each event.
#
# Author: Paul Mayne
# Last Updated: 2025-03-15

# -----------------------------------------------------------------------------
# Function Definitions
# -----------------------------------------------------------------------------

# Display usage information when help is requested or invalid args provided
function usage() {
  # Get the actual script name for better examples
  local script=$(basename "$0")
  
  # Display help information  
  echo "Usage: $script [options]"
  echo ""
  echo "Options:"
  echo "  --sleep SEC      Sleep time between API calls in seconds (default: 7)"
  echo "  --journal NAME   Specify Day One journal name (default: The New York Times)"
  echo "  --pdf            Also attach the PDF file (JPG only by default)"
  echo "  --full-summary   Include comprehensive NYT content analysis"
  echo "  --help, -h       Show this help message"
  echo ""
  echo "Examples:"
  echo "  $script                              # Process all historical events"
  echo "  $script --pdf                        # Include PDF attachments"
  echo "  $script --sleep 3                    # Use shorter delay between API calls"
  echo "  $script --journal \"History\"          # Use specific journal"
  
  exit 1
}

# Function to convert various date formats to YYYY-MM-DD
function normalize_date() {
  local input_date="$1"
  local normalized_date=""
  
  # For dates already in YYYY-MM-DD format
  if [[ $input_date = [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] ]]; then
    normalized_date="$input_date"
    return
  fi
  
  # For "Month Day, Year" format (e.g., "January 20, 2025")
  if [[ $input_date = *[0-9]","\ [0-9][0-9][0-9][0-9] ]]; then
    normalized_date=$(date -j -f "%B %d, %Y" "$input_date" "+%Y-%m-%d" 2>/dev/null)
    if [[ -z "$normalized_date" ]]; then
      normalized_date=$(date -j -f "%b %d, %Y" "$input_date" "+%Y-%m-%d" 2>/dev/null)
    fi
    if [[ -n "$normalized_date" ]]; then
      echo "$normalized_date"
      return
    fi
  fi
  
  # For "Month Year" format (e.g., "March 2014")
  if [[ $input_date = *\ [0-9][0-9][0-9][0-9] ]]; then
    local month=$(echo "$input_date" | awk '{print $1}')
    local year=$(echo "$input_date" | awk '{print $NF}')
    normalized_date=$(date -j -f "%B %Y" "$month $year" "+%Y-%m-01" 2>/dev/null)
    if [[ -z "$normalized_date" ]]; then
      normalized_date=$(date -j -f "%b %Y" "$month $year" "+%Y-%m-01" 2>/dev/null)
    fi
    if [[ -n "$normalized_date" ]]; then
      echo "$normalized_date"
      return
    fi
  fi
  
  # Return the result
  echo "$normalized_date"
}

# -----------------------------------------------------------------------------
# Input Validation and Setup
# -----------------------------------------------------------------------------

# Default settings
SLEEP_TIME=7   # Default sleep between API calls
JOURNAL_NAME="The New York Times"  # Default journal name
ATTACH_PDF=false
FULL_SUMMARY=false

# Parse command line arguments
while (( $# > 0 )); do
  case "$1" in
    -h|--help)
      usage
      ;;
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
    --journal)
      # Require journal name argument
      if (( $# > 1 )); then
        JOURNAL_NAME="$2"
        shift 2
      else
        echo "Error: --journal requires a journal name"
        usage
      fi
      ;;
    --pdf)
      ATTACH_PDF=true
      shift
      ;;
    --full-summary)
      FULL_SUMMARY=true
      shift
      ;;
    *)
      echo "Error: Unknown option: $1"
      usage
      ;;
  esac
done

# Check for JSON file existence
EVENTS_FILE="$PWD/historical-events.json"
if [[ ! -f "$EVENTS_FILE" ]]; then
  echo "Error: historical-events.json file not found at $EVENTS_FILE"
  exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "Error: jq not found. Please install jq to parse JSON files."
  echo "You can install jq with: brew install jq"
  exit 1
fi

# -----------------------------------------------------------------------------
# Process Historical Events
# -----------------------------------------------------------------------------

# Get number of events
EVENT_COUNT=$(jq '. | length' "$EVENTS_FILE")
echo "Found $EVENT_COUNT historical events to process."
echo "Sleep time between API calls: $SLEEP_TIME seconds"

# Array to collect all Day One entry URLs
CREATED_ENTRIES=()

# Process each event
for ((i=0; i<EVENT_COUNT; i++)); do
  # Extract event data
  EVENT=$(jq -r ".[$i].Event" "$EVENTS_FILE")
  EVENT_DATE=$(jq -r ".[$i].Date" "$EVENTS_FILE")
  
  # Convert event date to YYYY-MM-DD format
  EVENT_DATE_FORMATTED=$(normalize_date "$EVENT_DATE")
  
  # Check if date conversion was successful
  if [[ -z "$EVENT_DATE_FORMATTED" ]]; then
    echo "Warning: Could not parse date format for '$EVENT_DATE'. Skipping event."
    continue
  fi
  
  # Calculate the newspaper date (day after the event)
  if [[ $EVENT_DATE_FORMATTED == [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] ]]; then
    # For specific day events, add one day
    NEWSPAPER_DATE_FORMATTED=$(date -j -v+1d -f "%Y-%m-%d" "$EVENT_DATE_FORMATTED" "+%Y-%m-%d" 2>/dev/null)
  else
    # For month-only events (like "March 2014"), use the 2nd of the month
    NEWSPAPER_DATE_FORMATTED=$(echo "$EVENT_DATE_FORMATTED" | sed 's/-01$/-02/')
  fi
  
  # Show progress
  echo ""
  echo "Processing event $((i+1)) of $EVENT_COUNT:"
  echo "  Event: $EVENT"
  echo "  Event Date: $EVENT_DATE (converted to $EVENT_DATE_FORMATTED)"
  echo "  Newspaper Date: Next day - $NEWSPAPER_DATE_FORMATTED"
  
  # Check for valid date
  LIMIT_DATE="2012-07-01"
  if [[ "$NEWSPAPER_DATE_FORMATTED" < "$LIMIT_DATE" ]]; then
    echo "Warning: Date $NEWSPAPER_DATE_FORMATTED is before July 2012. NYT front pages may not be available."
    echo "Skipping this event."
    continue
  fi
  
  # Build command arguments
  ARGS=()
  if [[ "$ATTACH_PDF" = true ]]; then
    ARGS+=("--pdf")
  fi
  if [[ "$FULL_SUMMARY" = true ]]; then
    ARGS+=("--full-summary")
  fi
  ARGS+=("--journal" "$JOURNAL_NAME")
  
  # Add the special historical event tag and first headline replacement
  ARGS+=("--tag" "Historical Event")
  ARGS+=("--headline" "$EVENT")
  
  # Call the single-day script with appropriate arguments and capture output
  echo "Creating Day One entry..."
  OUTPUT=$($PWD/nyt_to_dayone.zsh "$NEWSPAPER_DATE_FORMATTED" "${ARGS[@]}" 2>&1)
  
  # Check for success
  if [[ "$OUTPUT" == *"Error"* ]]; then
    echo "Failed to create entry for $EVENT:"
    echo "$OUTPUT"
  else
    echo "Successfully created entry for $EVENT"
    
    # Extract the Day One deep link if present in the output
    DEEP_LINK=$(echo "$OUTPUT" | grep "dayone://view?entryId=")
    if [[ -n "$DEEP_LINK" ]]; then
      CREATED_ENTRIES+=("$EVENT: $DEEP_LINK")
    fi
  fi
  
  # Add delay to avoid API rate limiting if not the last event
  if (( i < EVENT_COUNT-1 )); then
    echo "Waiting $SLEEP_TIME seconds before next request (to avoid API rate limiting)..."
    sleep $SLEEP_TIME
  fi
done

# -----------------------------------------------------------------------------
# Display Results Summary
# -----------------------------------------------------------------------------

# Show completion message
echo ""
echo "Historical events processing completed!"
echo "Successfully created ${#CREATED_ENTRIES[@]} of $EVENT_COUNT entries."

# Display all created entry deep links for easy access
if [[ ${#CREATED_ENTRIES[@]} -gt 0 ]]; then
  echo ""
  echo "Created Entries:"
  for entry in "${CREATED_ENTRIES[@]}"; do
    echo "$entry"
  done
fi

exit 0