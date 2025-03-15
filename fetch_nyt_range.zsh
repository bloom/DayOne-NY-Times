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
  echo "Usage: $script START_DATE END_DATE [options]"
  echo ""
  echo "Arguments:"
  echo "  START_DATE: First date to fetch (YYYY-MM-DD format)"
  echo "  END_DATE:   Last date to fetch (YYYY-MM-DD format)"
  echo ""
  echo "Options: (passed to nyt_to_dayone.zsh)"
  echo "  --pdf            Also attach the PDF file (JPG only by default)"
  echo "  --full-summary   Include comprehensive NYT content analysis"
  echo "  --journal NAME   Specify Day One journal name (default: New York Times)"
  echo ""
  echo "Examples:"
  echo "  $script 2025-01-01 2025-01-31                  # Fetch all of January 2025"
  echo "  $script 2025-01-15 2025-02-15                  # Fetch a custom date range"
  echo "  $script 2025-01-01 2025-01-31 --pdf            # Include PDF attachments"
  echo "  $script 2025-01-01 2025-01-31 --journal \"History\"  # Use specific journal"
  
  exit 1
}

# -----------------------------------------------------------------------------
# Input Validation
# -----------------------------------------------------------------------------

# Check if required arguments are provided
if [[ $# -lt 2 ]]; then
  echo "Error: Missing required date arguments"
  usage
fi

# Store and validate date arguments
START_DATE="$1"
END_DATE="$2"
shift 2  # Remove dates from args

# Validate start date format
if ! [[ "$START_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Error: START_DATE must be in YYYY-MM-DD format"
  usage
fi

# Validate end date format
if ! [[ "$END_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Error: END_DATE must be in YYYY-MM-DD format"
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

# Store remaining arguments to pass to the individual day script
EXTRA_ARGS=("$@")

# -----------------------------------------------------------------------------
# Process Each Day in Range
# -----------------------------------------------------------------------------

# Array to collect all Day One entry URLs
CREATED_ENTRIES=()

# Process each day in the range
CURRENT_SECONDS=$START_SECONDS
for ((day=1; day<=DAYS_IN_RANGE; day++)); do
  # Format current date in YYYY-MM-DD format
  CURRENT_DATE=$(date -j -f "%s" "$CURRENT_SECONDS" "+%Y-%m-%d")
  
  # Show progress
  echo "Processing: $CURRENT_DATE ($day of $DAYS_IN_RANGE)"
  
  # Call the single-day script with appropriate arguments and capture output
  if [[ ${#EXTRA_ARGS[@]} -eq 0 ]]; then
    OUTPUT=$($PWD/nyt_to_dayone.zsh "$CURRENT_DATE")
  else
    OUTPUT=$($PWD/nyt_to_dayone.zsh "$CURRENT_DATE" "${EXTRA_ARGS[@]}")
  fi
  
  # Display the captured output
  echo "$OUTPUT"
  
  # Extract the Day One deep link if present in the output
  DEEP_LINK=$(echo "$OUTPUT" | grep "dayone://view?entryId=")
  if [[ -n "$DEEP_LINK" ]]; then
    CREATED_ENTRIES+=("$CURRENT_DATE: $DEEP_LINK")
  fi
  
  # Move to next day
  CURRENT_SECONDS=$((CURRENT_SECONDS + 86400))
  
  # Add delay to avoid API rate limiting
  sleep 7
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