#!/bin/zsh
#
# fetch_historical.zsh
#
# Creates Day One entries for all historical events listed in historical-events.json
# Each entry is created for the day AFTER the event date (the "newspaper date")
#
# Author: Paul Mayne
# Last Updated: 2025-03-15
#

# Enable extended globbing for better pattern matching
setopt EXTENDED_GLOB

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
  echo "  -h, --help                Show this help message"
  echo "  --journal NAME            Specify Day One journal name (default: Historical Events)"
  echo "  --no-tag                  Don't add the default tags"
  echo "  --pdf                     Also attach the PDF file (JPG only by default)"
  echo "  --full-summary            Include comprehensive NYT content analysis"
  echo "  --dry-run                 Show what would be done without creating entries"
  echo "  --sleep SEC               Sleep time between API calls in seconds (default: 7)"
  echo "  --max-retries NUM         Maximum number of retry attempts on failure (default: 3)"
  echo "  --retry-delay SEC         Seconds to wait between retry attempts (default: 30)"
  echo "  --start-date YYYY-MM-DD   Process events starting from this date"
  echo "  --end-date YYYY-MM-DD     Process events until this date"
  echo "  --event EVENT_NAME        Process only the specific event matching this name"
  echo ""
  echo "The script reads historical-events.json and creates Day One entries"
  echo "for each event on the day AFTER the event date (the 'newspaper date')."
  echo ""
  echo "Date formats in historical-events.json:"
  echo "  1. Full dates: \"January 21, 2017\" (Month Day, Year)"
  echo "  2. Month-only: \"March 2014\" - will use the 15th as the default day"
  echo ""
  echo "Examples:"
  echo "  $script                                   # Process all events"
  echo "  $script --dry-run                         # Show what would be done without creating entries"
  echo "  $script --journal \"History\"              # Save to different journal"
  echo "  $script --start-date 2020-01-01           # Process events from 2020 onwards"
  echo "  $script --event \"Capitol Riots\"          # Process only the Capitol Riots event"
  echo "  $script --sleep 10                        # Use longer delay between API calls"
  echo "  $script --max-retries 5 --retry-delay 60  # More resilient error handling"
  echo ""
  
  exit 1
}

# Process a single event and create a Day One entry for it
function process_event() {
  local event_date="$1"
  local event_text="$2"
  
  # Convert event date to correct format for processing
  local formatted_date=""
  
  # Try parsing full date in format "January 6, 2021"
  formatted_date=$(date -j -f "%B %d, %Y" "$event_date" +%Y-%m-%d 2>/dev/null)
  
  # If that fails, try parsing month-year only format "March 2014"
  if [[ -z "$formatted_date" ]]; then
    # For month-year format, use the 15th as the default day of the month
    if [[ "$event_date" =~ ^([A-Za-z]+)[[:space:]]+([0-9]{4})$ ]]; then
      local month="${BASH_REMATCH[1]}"
      local year="${BASH_REMATCH[2]}"
      formatted_date=$(date -j -f "%B %d, %Y" "$month 15, $year" +%Y-%m-%d 2>/dev/null)
      
      if [[ -n "$formatted_date" ]]; then
        echo "Note: Month-only date '$event_date' interpreted as '$month 15, $year'"
      fi
    fi
  fi
  
  # If all parsing attempts failed
  if [[ -z "$formatted_date" ]]; then
    echo "Error: Could not parse date: $event_date. Skipping event."
    return 1
  fi
  
  # Calculate the newspaper date (day after the event)
  local newspaper_date=$(date -j -v+1d -f "%Y-%m-%d" "$formatted_date" +%Y-%m-%d)
  local newspaper_display_date=$(date -j -f "%Y-%m-%d" "$newspaper_date" +"%B %d, %Y")
  
  echo "Processing event: \"$event_text\""
  echo "  Event date: $event_date"
  echo "  Newspaper date: $newspaper_display_date"
  
  # Skip if the event is outside our date range
  if [[ -n "$START_DATE" && "$newspaper_date" < "$START_DATE" ]]; then
    echo "  Skipping: Newspaper date is before start date ($START_DATE)"
    return 0
  fi
  
  if [[ -n "$END_DATE" && "$newspaper_date" > "$END_DATE" ]]; then
    echo "  Skipping: Newspaper date is after end date ($END_DATE)"
    return 0
  fi
  
  # Build the command to create the entry
  local nyt_cmd="./nyt_to_dayone.zsh"
  
  # Add all options based on command line flags
  [[ "$PDF_ATTACHMENT" = true ]] && nyt_cmd+=" --pdf"
  [[ "$FULL_SUMMARY" = true ]] && nyt_cmd+=" --full-summary"
  [[ "$NO_TAG" = true ]] && nyt_cmd+=" --no-tag"
  
  # Add headline and journal
  nyt_cmd+=" --headline \"$event_text\""
  [[ -n "$JOURNAL_NAME" ]] && nyt_cmd+=" --journal \"$JOURNAL_NAME\""
  
  # Add the newspaper date
  nyt_cmd+=" $newspaper_date"
  
  # Run the command (or just show it in dry-run mode)
  if [[ "$DRY_RUN" = true ]]; then
    echo "  Dry run - would execute: $nyt_cmd"
    return 0
  fi
  
  # Execute the command and handle potential fallbacks
  echo "  Creating entry: $nyt_cmd"
  eval $nyt_cmd
  
  # Check if the command succeeded
  if [[ $? -eq 0 ]]; then
    echo "  Entry creation successful!"
    return 0
  fi
  
  echo "  Error: Failed to create entry"
  
  # Only try fallbacks if using the default "Historical Events" journal
  if [[ "$JOURNAL_NAME" != "Historical Events" ]]; then
    return 1
  fi
  
  # Try with "The New York Times" journal
  echo "  Retrying with 'The New York Times' journal..."
  local retry_cmd="${nyt_cmd/--journal \"$JOURNAL_NAME\"/--journal \"The New York Times\"}"
  eval $retry_cmd
  
  if [[ $? -eq 0 ]]; then
    echo "  Entry creation successful with 'The New York Times' journal!"
    return 0
  fi
  
  # If that also fails, try without specifying a journal
  echo "  Retrying without specifying a journal..."
  local no_journal_cmd="${nyt_cmd/--journal \"$JOURNAL_NAME\"/}"
  eval $no_journal_cmd
  
  if [[ $? -eq 0 ]]; then
    echo "  Entry creation successful without journal specification!"
    return 0
  fi
  
  echo "  Error: Failed to create entry even without journal specification"
  return 1
}

# -----------------------------------------------------------------------------
# Parse Command Line Arguments
# -----------------------------------------------------------------------------

# Default settings
JOURNAL_NAME="Historical Events"
NO_TAG=false
PDF_ATTACHMENT=false
FULL_SUMMARY=false
DRY_RUN=false
START_DATE=""
END_DATE=""
SPECIFIC_EVENT=""
SLEEP_TIME=7      # Default sleep between API calls (seconds)
MAX_RETRIES=3     # Maximum number of retry attempts on failure
RETRY_DELAY=30    # Seconds to wait between retry attempts

# Process command line arguments
while (( $# > 0 )); do
  case "$1" in
    -h|--help)
      usage
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
    --no-tag)
      NO_TAG=true
      shift
      ;;
    --pdf)
      PDF_ATTACHMENT=true
      shift
      ;;
    --full-summary)
      FULL_SUMMARY=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
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
    --max-retries)
      # Require number of retries argument
      if (( $# > 1 )); then
        MAX_RETRIES="$2"
        shift 2
      else
        echo "Error: --max-retries requires a number"
        usage
      fi
      ;;
    --retry-delay)
      # Require retry delay argument
      if (( $# > 1 )); then
        RETRY_DELAY="$2"
        shift 2
      else
        echo "Error: --retry-delay requires a value in seconds"
        usage
      fi
      ;;
    --start-date)
      # Require date argument
      if (( $# > 1 )) && [[ "$2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        START_DATE="$2"
        shift 2
      else
        echo "Error: --start-date requires a date in YYYY-MM-DD format"
        usage
      fi
      ;;
    --end-date)
      # Require date argument
      if (( $# > 1 )) && [[ "$2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        END_DATE="$2"
        shift 2
      else
        echo "Error: --end-date requires a date in YYYY-MM-DD format"
        usage
      fi
      ;;
    --event)
      # Require event text argument
      if (( $# > 1 )); then
        SPECIFIC_EVENT="$2"
        shift 2
      else
        echo "Error: --event requires event text"
        usage
      fi
      ;;
    *)
      echo "Error: Unknown option: $1"
      usage
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Main Script Logic
# -----------------------------------------------------------------------------

# Check prerequisites
function check_prerequisites() {
  # Check if historical-events.json exists
  if [[ ! -f "historical-events.json" ]]; then
    echo "Error: historical-events.json not found in the current directory"
    return 1
  fi

  # Check if jq is available
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required for JSON processing but not found"
    echo "Please install jq: brew install jq"
    return 1
  fi

  # Check if nyt_to_dayone.zsh is available and executable
  if [[ ! -x "nyt_to_dayone.zsh" ]]; then
    echo "Error: nyt_to_dayone.zsh not found or not executable in the current directory"
    return 1
  fi
  
  return 0
}

# Check prerequisites before proceeding
check_prerequisites || exit 1

# Read and process the historical events
echo "Reading historical events from historical-events.json..."
TOTAL_EVENTS=$(jq '. | length' historical-events.json)
echo "Found $TOTAL_EVENTS events in the file"

# Display filtering information if applicable
[[ -n "$START_DATE" ]] && echo "Filtering events with newspaper date on or after: $START_DATE"
[[ -n "$END_DATE" ]] && echo "Filtering events with newspaper date on or before: $END_DATE"
[[ -n "$SPECIFIC_EVENT" ]] && echo "Processing only events matching: \"$SPECIFIC_EVENT\""

# Initialize counters
PROCESSED=0
SKIPPED=0
CREATED=0

echo "\nBEGINNING PROCESSING\n-------------------"

# Display configuration information
echo "Sleep time between API calls: $SLEEP_TIME seconds"
echo "Error retry config: $MAX_RETRIES retries with $RETRY_DELAY seconds delay"

# Process each event in the JSON file
COUNTER=0
jq -c '.[]' historical-events.json | while read -r event_json; do
  # Extract date and event text with a single jq call
  event_date=$(jq -r '.Date' <<< "$event_json")
  event_text=$(jq -r '.Event' <<< "$event_json")
  
  # Skip if we're processing a specific event and this isn't it
  if [[ -n "$SPECIFIC_EVENT" && "$event_text" != *"$SPECIFIC_EVENT"* ]]; then
    ((SKIPPED++))
    continue
  fi
  
  # Add a delay between API calls (skip for first entry)
  if [[ $COUNTER -gt 0 && "$DRY_RUN" = false ]]; then
    echo "Waiting $SLEEP_TIME seconds before next API call (to avoid rate limiting)..."
    sleep $SLEEP_TIME
  fi
  ((COUNTER++))
  
  # Process this event with retry mechanism
  RETRY_COUNT=0
  PROCESS_SUCCESS=false
  
  while [[ $RETRY_COUNT -lt $MAX_RETRIES && "$PROCESS_SUCCESS" = false ]]; do
    if [[ $RETRY_COUNT -gt 0 ]]; then
      echo "Retry attempt $RETRY_COUNT of $MAX_RETRIES after waiting $RETRY_DELAY seconds..."
    fi
    
    # Try to process the event
    process_event "$event_date" "$event_text"
    RESULT=$?
    
    if [[ $RESULT -eq 0 ]]; then
      # Success!
      PROCESS_SUCCESS=true
    else
      # Failed - increment retry counter
      ((RETRY_COUNT++))
      
      if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
        echo "ERROR: Processing failed, will retry in $RETRY_DELAY seconds..."
        sleep $RETRY_DELAY
      else
        echo "ERROR: Processing failed after $MAX_RETRIES attempts. Skipping this event."
      fi
    fi
  done
  
  # Track counts based on result
  if [[ "$PROCESS_SUCCESS" = true ]]; then
    ((PROCESSED++))
    [[ "$DRY_RUN" = false ]] && ((CREATED++))
  else
    echo "WARNING: Skipping event due to persistent errors: $event_text ($event_date)"
    ((SKIPPED++))
  fi
done

# Print summary
echo "\nPROCESSING COMPLETE\n-------------------"
echo "Total events in file: $TOTAL_EVENTS"
echo "Events processed: $PROCESSED"
echo "Events skipped: $SKIPPED"

if [[ "$DRY_RUN" = true ]]; then
  echo "DRY RUN - No entries were actually created"
else
  echo "Entries created: $CREATED"
fi