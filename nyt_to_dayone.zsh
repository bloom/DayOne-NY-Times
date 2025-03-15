#!/bin/zsh
#
# nyt_to_dayone.zsh
#
# Fetches The New York Times front page and headlines for a specific date
# and creates a Day One journal entry with the content.
#
# Author: Paul Mayne
# Last Updated: 2024-03-14

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
  echo "Usage: $script [options] [date]"
  echo "  date: Date in YYYY-MM-DD format (default: today)"
  echo ""
  echo "Options:"
  echo "  -h, --help       Show this help message"
  echo "  --pdf            Also attach the PDF file (JPG only by default)"
  echo "  --full-summary   Include comprehensive NYT content analysis"
  echo "  --journal NAME   Specify Day One journal name (default: The New York Times)"
  echo "  --no-tag         Don't add the default tag \"$DEFAULT_TAG\""
  echo "  --tag TAG        Add additional tag (can be used multiple times)"
  echo "  --headline TEXT  Replace the first headline with custom text"
  echo "  --bad-pdf        Mark this date as having a corrupted PDF"
  echo ""
  echo "Environment variables:"
  echo "  NYT_API_KEY      Your New York Times API key (required)"
  echo ""
  echo "Examples:"
  echo "  $script                                       # Get today's front page"
  echo "  $script 2024-03-14                            # Get front page for specific date" 
  echo "  $script --pdf 2024-01-01                      # Include PDF attachment"
  echo "  $script --journal \"History\" 2022-09-08        # Save to different journal"
  echo "  $script --no-tag 2024-02-15                   # Skip adding the default tag"
  echo "  $script --tag \"Historical Event\" 2021-01-07   # Add additional tag"
  echo "  $script --headline \"Capitol Riots\" 2021-01-07 # Use custom headline"
  echo "  $script --bad-pdf 2018-01-10                   # Handle known corrupted PDF"
  
  exit 1
}

# -----------------------------------------------------------------------------
# Parse Command Line Arguments
# -----------------------------------------------------------------------------

# Default settings
ATTACH_PDF=false        # PDF attachment is off by default
ATTACH_JPG=true         # JPG attachment is always on by default
INCLUDE_FULL_SUMMARY=false  # Full content analysis is off by default
DATE=""                 # Date to fetch (empty = today)
JOURNAL_NAME="The New York Times"  # Default journal name
DEFAULT_TAG="The New York Times"  # Default tag (can be disabled)
ADD_DEFAULT_TAG=true    # Whether to add the default tag
ADDITIONAL_TAGS=()      # Additional tags to add
CUSTOM_HEADLINE=""      # Custom headline to use instead of NYT first headline
PDF_CORRUPTED=false     # Whether the PDF is known to be corrupted

# List of dates with known corrupted PDFs (YYYY-MM-DD format)
CORRUPTED_PDFS=(
  "2018-01-10"
  "2018-01-11" 
  "2018-01-12"
  "2018-01-13"
)

# Function to check if a date has a corrupted PDF
function is_corrupted_pdf() {
  local check_date="$1"
  for bad_date in "${CORRUPTED_PDFS[@]}"; do
    if [[ "$check_date" == "$bad_date" ]]; then
      return 0  # True, it is corrupted
    fi
  done
  return 1  # False, it's not in the corrupted list
}

# Process command line arguments
while (( $# > 0 )); do
  case "$1" in
    -h|--help)
      usage
      ;;
    --pdf)
      ATTACH_PDF=true
      shift
      ;;
    --full-summary)
      INCLUDE_FULL_SUMMARY=true
      shift
      ;;
    --no-tag)
      ADD_DEFAULT_TAG=false
      shift
      ;;
    --tag)
      # Require tag argument
      if (( $# > 1 )); then
        ADDITIONAL_TAGS+=("$2")
        shift 2
      else
        echo "Error: --tag requires a tag value"
        usage
      fi
      ;;
    --headline)
      # Require headline text argument
      if (( $# > 1 )); then
        CUSTOM_HEADLINE="$2"
        shift 2
      else
        echo "Error: --headline requires text"
        usage
      fi
      ;;
    --bad-pdf)
      # Mark the date as having a corrupted PDF
      # Note: This is just informational for this run; to permanently add,
      # the user needs to edit the script
      echo "Marking $DATE as having a corrupted PDF"
      PDF_CORRUPTED=true
      shift
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
    *)
      # Check if argument is a date in YYYY-MM-DD format
      if [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        DATE="$1"
      else
        echo "Error: Unknown option: $1"
        usage
      fi
      shift
      ;;
  esac
done

# -----------------------------------------------------------------------------
# API Key Handling
# -----------------------------------------------------------------------------

# Get API key from environment variable or file
API_KEY="$NYT_API_KEY"
if [[ -z "$API_KEY" ]]; then
  # Try to read from file if not in environment
  if [[ -f "$PWD/nyt_api_key.txt" ]]; then
    API_KEY=$(<"$PWD/nyt_api_key.txt")
  fi
  
  # If still no API key, show error and exit
  if [[ -z "$API_KEY" ]]; then
    echo "Error: NYT API key not found"
    echo "Please either:"
    echo "  1. Set NYT_API_KEY environment variable"
    echo "  2. Create nyt_api_key.txt file in current directory"
    exit 1
  fi
fi

# -----------------------------------------------------------------------------
# Date Processing
# -----------------------------------------------------------------------------

# If no date provided, use today
if [[ -z "$DATE" ]]; then
  DATE=$(date +%Y-%m-%d)
  URL_DATE=$(date +%Y/%m/%d)
  YEAR=$(date +%Y)
  MONTH=$(date +%-m)  # Month without leading zero
else
  # Convert input date to required formats
  URL_DATE=$(date -j -f "%Y-%m-%d" "$DATE" +%Y/%m/%d)
  YEAR=$(date -j -f "%Y-%m-%d" "$DATE" +%Y)
  MONTH=$(date -j -f "%Y-%m-%d" "$DATE" +%-m)
  
  # Check for date limitations - NYT PDFs are only reliably available from July 2012 onwards
  DATE_SECONDS=$(date -j -f "%Y-%m-%d" "$DATE" +%s)
  LIMIT_DATE_SECONDS=$(date -j -f "%Y-%m-%d" "2012-07-01" +%s)
  
  if [[ $DATE_SECONDS -lt $LIMIT_DATE_SECONDS ]]; then
    echo "Error: NYT front page PDFs are only reliably available from July 2012 onwards"
    echo "The requested date ($DATE) is too early for this service"
    exit 1
  fi
fi

# -----------------------------------------------------------------------------
# Historical Events Processing
# -----------------------------------------------------------------------------

# Initialize variable for historical event
HISTORICAL_EVENT=""

# Check if historical-events.json exists
if [[ -f "$PWD/historical-events.json" ]]; then
  echo "Checking for historical events that might correspond to this newspaper date..."
  
  # Check if jq is available for JSON processing
  if (( $+commands[jq] )); then
    # Calculate the "event date" which would be the day before the newspaper date
    # (Since newspapers report on events from the previous day)
    EVENT_DATE=$(date -j -v-1d -f "%Y-%m-%d" "$DATE" +"%B %-d, %Y")
    
    # Extract event if date matches
    if [[ -n "$EVENT_DATE" ]]; then
      HISTORICAL_EVENT=$(jq -r --arg date "$EVENT_DATE" '.[] | select(.Date == $date) | .Event' "$PWD/historical-events.json")
      
      if [[ -n "$HISTORICAL_EVENT" ]]; then
        echo "Found historical event for newspaper date $DATE (event occurred on $EVENT_DATE): $HISTORICAL_EVENT"
      fi
    fi
  else
    echo "Warning: jq not found, skipping historical events check"
    echo "To enable historical events feature, install jq: brew install jq"
  fi
fi

# Get day of month for filtering headlines
DAY=$(date -j -f "%Y-%m-%d" "$DATE" +%-d)

# Create formatted dates for URLs and display
FORMATTED_DATE=$(date -j -f "%Y-%m-%d" "$DATE" +"%A, %B %d, %Y")
FORMATTED_MONTH=$(date -j -f "%Y-%m-%d" "$DATE" +%m)
FORMATTED_DAY=$(date -j -f "%Y-%m-%d" "$DATE" +%d)

# Get day of month for ordinal suffix
DAY_NUM=$(date -j -f "%Y-%m-%d" "$DATE" +%-d)
# Add ordinal suffix (st, nd, rd, th)
if [[ $DAY_NUM -eq 11 || $DAY_NUM -eq 12 || $DAY_NUM -eq 13 ]]; then
  DAY_SUFFIX="th"
elif [[ $((DAY_NUM % 10)) -eq 1 ]]; then
  DAY_SUFFIX="st"
elif [[ $((DAY_NUM % 10)) -eq 2 ]]; then
  DAY_SUFFIX="nd"
elif [[ $((DAY_NUM % 10)) -eq 3 ]]; then
  DAY_SUFFIX="rd"
else
  DAY_SUFFIX="th"
fi

HEADER_DATE=$(date -j -f "%Y-%m-%d" "$DATE" +"%B %-d")${DAY_SUFFIX}
NYT_ARCHIVE_URL="https://www.nytimes.com/issue/todayspaper/$YEAR/$FORMATTED_MONTH/$FORMATTED_DAY/todays-new-york-times"

# -----------------------------------------------------------------------------
# Temporary Directory Setup
# -----------------------------------------------------------------------------

# Create temp directory for files
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

# -----------------------------------------------------------------------------
# Fetch and Process Front Page PDF
# -----------------------------------------------------------------------------

# First, check if the date is in the corrupted PDFs list or manually marked as corrupted
if is_corrupted_pdf "$DATE" || [[ "$PDF_CORRUPTED" = true ]]; then
  echo "Warning: PDF for $DATE is known to be corrupted. Skipping PDF/JPG processing."
  
  # Set the corrupted flag (in case it was set by the is_corrupted_pdf function)
  PDF_CORRUPTED=true
  
  # Notify about skipped attachments but continue processing
  if [[ "$ATTACH_PDF" = true ]]; then
    echo "PDF attachment was requested but will be skipped."
  fi
  
  if [[ "$ATTACH_JPG" = true ]]; then
    echo "JPG attachment was requested but will be skipped."
  fi
  
  # IMPORTANT: Ensure we don't try to process any PDFs
  ATTACH_PDF=false
  ATTACH_JPG=false
  
  # Skip the PDF processing section entirely
  echo "Continuing without PDF/JPG processing..."
else
  # Fetch PDF if needed for either PDF or JPG attachment
  if [[ "$ATTACH_PDF" = true || "$ATTACH_JPG" = true ]]; then
    echo "Fetching NYT front page for $DATE..."
    PDF_URL="https://static01.nyt.com/images/$URL_DATE/nytfrontpage/scan.pdf"
    /usr/bin/curl -s -o frontpage.pdf "$PDF_URL"

    # Verify download was successful
    if [[ ! -s frontpage.pdf ]]; then
      echo "Error: Failed to download NYT front page for $DATE"
      rm -rf "$TEMP_DIR"
      exit 1
    fi

    # Convert PDF to JPG if needed
    if [[ "$ATTACH_JPG" = true ]]; then
      echo "Converting PDF to high-resolution JPG..."
      
      # Method 1: Use macOS Quick Look for high quality rendering
      qlmanage -t -s 4500 -o . frontpage.pdf
      
      if [[ -f "frontpage.pdf.png" ]]; then
        # Convert PNG to JPG with high quality
        echo "Converting PNG to JPG with high quality..."
        sips -s format jpeg -s formatOptions high frontpage.pdf.png --out frontpage.jpg
        rm frontpage.pdf.png
        
        # Check the resolution of the output
        WIDTH=$(sips -g pixelWidth frontpage.jpg | grep pixelWidth | awk '{print $2}')
        HEIGHT=$(sips -g pixelHeight frontpage.jpg | grep pixelHeight | awk '{print $2}')
        echo "High resolution image created: ${WIDTH}×${HEIGHT} pixels"
      else
        # Fallback Method: Use sips directly with upscaling
        echo "Using fallback conversion method..."
        
        # First convert to regular JPG
        sips -s format jpeg frontpage.pdf --out frontpage.jpg
        
        # Then scale up by 6x for better quality
        WIDTH=$(sips -g pixelWidth frontpage.jpg | grep pixelWidth | awk '{print $2}')
        HEIGHT=$(sips -g pixelHeight frontpage.jpg | grep pixelHeight | awk '{print $2}')
        WIDTH=${WIDTH%.*}
        HEIGHT=${HEIGHT%.*}
        NEW_WIDTH=$((WIDTH * 6))
        NEW_HEIGHT=$((HEIGHT * 6))
        
        echo "Resizing from ${WIDTH}x${HEIGHT} to ${NEW_WIDTH}x${NEW_HEIGHT}..."
        sips -z $NEW_HEIGHT $NEW_WIDTH frontpage.jpg -s formatOptions high
      fi
    fi
  fi
fi

# -----------------------------------------------------------------------------
# Fetch and Process NYT Content from API
# -----------------------------------------------------------------------------

echo "Fetching data from NYT Archive API..."
/usr/bin/curl -s -o archive.json "https://api.nytimes.com/svc/archive/v1/$YEAR/$MONTH.json?api-key=$API_KEY"

# Initialize variables
TOP_HEADLINES=""
CONTENT_SUMMARY=""

# Function to extract headlines using jq
function extract_headlines() {
  local json_file="$1"
  local date_prefix="$2"
  
  # Try to get front page articles first
  local headlines=$(jq -r --arg date "$date_prefix" \
    '.response.docs[] | select(.pub_date | startswith($date)) | select(.print_page == "1") | 
     "- \(.headline.main)"' \
    "$json_file" | head -6)
  
  # If no front page articles, try news articles
  if [[ -z "$headlines" ]]; then
    headlines=$(jq -r --arg date "$date_prefix" \
      '.response.docs[] | select(.pub_date | startswith($date)) | select(.type_of_material == "News") | 
       "- \(.headline.main)"' \
      "$json_file" | head -6)
  fi
  
  # Remove author information
  if [[ -n "$headlines" ]]; then
    headlines=$(echo "$headlines" | sed -E 's/ [B|b]y [^,]+,?//g')
  fi
  
  echo "$headlines"
}

# Process API response if successful
if [[ -s archive.json ]]; then
  # Check if jq is available for JSON processing
  if (( $+commands[jq] )); then
    # Format date prefix for API filtering (YYYY-MM-DDT format)
    PUB_DATE_PREFIX="$YEAR-$(printf "%02d" $MONTH)-$(printf "%02d" $DAY)T"
    
    echo "Extracting content for $DATE..."
    
    # Extract headlines using our function
    TOP_HEADLINES=$(extract_headlines "archive.json" "$PUB_DATE_PREFIX")
    
    # If still no headlines found (e.g., very recent date), attempt a retry
    if [[ -z "$TOP_HEADLINES" ]]; then
      # Check if date is today or yesterday (very recent)
      TODAY=$(date +%Y-%m-%d)
      YESTERDAY=$(date -v-1d +%Y-%m-%d)
      
      if [[ "$DATE" == "$TODAY" || "$DATE" == "$YESTERDAY" ]]; then
        echo "Note: Headlines not yet available from NYT Archive API for very recent dates"
        TOP_HEADLINES="- Headlines not yet available for recent dates
- Front page image is available for viewing"
        FIRST_HEADLINE="Recent Front Page"
      else
        echo "No headlines found for this date. Waiting 10 seconds and trying again..."
        
        # Try fetching from API again
        echo "Retrying API fetch..."
        sleep 10
        /usr/bin/curl -s -o archive_retry.json "https://api.nytimes.com/svc/archive/v1/$YEAR/$MONTH.json?api-key=$API_KEY"
        
        # Process retry response if successful
        if [[ -s archive_retry.json && -n "$(command -v jq)" ]]; then
          # Extract headlines from retry using our function
          RETRY_TOP_HEADLINES=$(extract_headlines "archive_retry.json" "$PUB_DATE_PREFIX")
          
          # If we got headlines on the retry, use them
          if [[ -n "$RETRY_TOP_HEADLINES" ]]; then
            echo "Headlines found on retry!"
            TOP_HEADLINES="$RETRY_TOP_HEADLINES"
          else
            echo "Note: Still no headlines found after retry"
            TOP_HEADLINES=""
            FIRST_HEADLINE="The New York Times"
          fi
        else
          echo "Retry failed or jq not available."
          TOP_HEADLINES=""
          FIRST_HEADLINE="The New York Times"
        fi
      fi
    fi
    
    # Only build full summary if requested
    if [[ "$INCLUDE_FULL_SUMMARY" = true ]]; then
      # Use a single jq query to extract all the needed data more efficiently
      SUMMARY_DATA=$(jq -r --arg date "$PUB_DATE_PREFIX" '
        {
          total: (.response.docs | map(select(.pub_date | startswith($date))) | length),
          longest: (.response.docs | map(select(.pub_date | startswith($date))) | sort_by(.word_count) | reverse | .[0] | "\(.word_count) words | \(.headline.main) \(.byline.original // \"\")"),
          opinions: (.response.docs | map(select(.pub_date | startswith($date)) | select(.news_desk == "OpEd" or .section_name == "Opinion" or .type_of_material == "Op-Ed")) | .[0:3] | map("- \(.headline.main) \(.byline.original // \"\")") | join("\n")),
          sections: (.response.docs | map(select(.pub_date | startswith($date)) | .section_name) | group_by(.) | map({name: .[0], count: length}) | sort_by(.count) | reverse | .[0:5] | map("- \(.name // \"Uncategorized\"): \(.count) articles") | join("\n"))
        }' archive.json)
      
      # Extract results to variables
      TOTAL_ARTICLES=$(echo "$SUMMARY_DATA" | jq -r '.total')
      LONGEST_ARTICLE=$(echo "$SUMMARY_DATA" | jq -r '.longest')
      TOP_OPINIONS=$(echo "$SUMMARY_DATA" | jq -r '.opinions')
      SECTION_COUNTS=$(echo "$SUMMARY_DATA" | jq -r '.sections')
      
      # Extract trending keywords (this is more complex and kept separate)
      TOP_KEYWORDS=$(jq -r --arg date "$PUB_DATE_PREFIX" \
        '.response.docs[] | select(.pub_date | startswith($date)) | .keywords[].value' \
        archive.json | sort | uniq -c | sort -rn | head -10 | 
        awk '{print "- " $2 " " $3 " " $4 " " $5 " " $6 " " $7}' | sed 's/ *$//')
      
      # Create comprehensive content summary
      CONTENT_SUMMARY="### NYT Publication Summary
- Total articles published: $TOTAL_ARTICLES
- Longest article: $LONGEST_ARTICLE
- [View full archived issue]($NYT_ARCHIVE_URL)

### Section Breakdown
$SECTION_COUNTS

### Top Opinion Pieces
$TOP_OPINIONS

### Trending Topics
$TOP_KEYWORDS"
    fi
  else
    echo "Warning: jq not found, skipping content extraction"
    echo "To enable content extraction, install jq: brew install jq"
  fi
else
  echo "Error: Failed to fetch data from NYT Archive API"
fi

# -----------------------------------------------------------------------------
# Build Day One Entry Content
# -----------------------------------------------------------------------------

# Process headlines to extract first one and format the rest
FIRST_HEADLINE=""
REMAINING_HEADLINES=""

if [[ -n "$TOP_HEADLINES" ]]; then
  # Get the first headline (remove the '- ' prefix)
  FIRST_HEADLINE=$(echo "$TOP_HEADLINES" | head -1 | sed 's/^- //')
  
  # Get the remaining headlines (skip the first one)
  REMAINING_HEADLINES=$(echo "$TOP_HEADLINES" | tail -n +2)
else
  FIRST_HEADLINE="The New York Times"
  REMAINING_HEADLINES=""
fi

# Override with historical event if available
if [[ -n "$HISTORICAL_EVENT" ]]; then
  echo "Using historical event as top headline: $HISTORICAL_EVENT"
  # Save original first headline to use in remaining headlines
  if [[ -n "$FIRST_HEADLINE" ]]; then
    # When using historical event, include ALL headlines in the remaining list
    REMAINING_HEADLINES="- $FIRST_HEADLINE
$REMAINING_HEADLINES"
  fi
  FIRST_HEADLINE="$HISTORICAL_EVENT"
  
  # Automatically add the "Historical Event" tag (respecting user's tag preferences)
  if [[ "$ADD_DEFAULT_TAG" = true ]]; then
    echo "Adding \"Historical Event\" tag to entry"
    ADDITIONAL_TAGS+=("Historical Event")
  fi
# Otherwise override with custom headline if provided
elif [[ -n "$CUSTOM_HEADLINE" ]]; then
  FIRST_HEADLINE="$CUSTOM_HEADLINE"
fi

# Create entry text with appropriate format
if [[ "$PDF_CORRUPTED" = true ]]; then
  # Entry with corrupted PDF notice - no image placeholder needed
  HEADER="#### The New York Times: $HEADER_DATE
$FIRST_HEADLINE

**(PDF is corrupted)**"
elif [[ "$ATTACH_JPG" = true || "$ATTACH_PDF" = true ]]; then
  # Entry with image placeholder and headline above
  HEADER="#### The New York Times: $HEADER_DATE
$FIRST_HEADLINE
[{photo}]"
else
  # Entry without image
  HEADER="#### The New York Times: $HEADER_DATE
$FIRST_HEADLINE"
fi

# Build entry with or without full summary
if [[ "$INCLUDE_FULL_SUMMARY" = true && -n "$CONTENT_SUMMARY" ]]; then
  ENTRY_TEXT="${HEADER}
${REMAINING_HEADLINES}

${NYT_ARCHIVE_URL}

${CONTENT_SUMMARY}"
else
  ENTRY_TEXT="${HEADER}
${REMAINING_HEADLINES}

${NYT_ARCHIVE_URL}"
fi

# -----------------------------------------------------------------------------
# Create Day One Entry
# -----------------------------------------------------------------------------

echo "Creating Day One entry..."

# Prepare photo attachment arguments
PHOTO_ARGS=()

# Skip attachments completely if the PDF is corrupted (should already be set, but double-check)
if [[ "$PDF_CORRUPTED" = true ]]; then
  echo "Skipping attachments due to corrupted PDF..."
  # These should already be set to false earlier, but ensure it again
  ATTACH_JPG=false
  ATTACH_PDF=false
elif [[ "$ATTACH_JPG" = true && "$ATTACH_PDF" = true ]]; then
  echo "Attaching both JPG and PDF..."
  PHOTO_ARGS=("frontpage.jpg" "frontpage.pdf")
elif [[ "$ATTACH_JPG" = true ]]; then
  echo "Attaching only JPG..."
  PHOTO_ARGS=("frontpage.jpg")
elif [[ "$ATTACH_PDF" = true ]]; then
  echo "Attaching only PDF..."
  PHOTO_ARGS=("frontpage.pdf")
else
  echo "No attachments..."
fi

# Print journal information
echo "Using journal: $JOURNAL_NAME"

# Build tag command string for Day One
ALL_TAGS=()

# Populate tag array - add default tag if enabled and any additional tags
[[ "$ADD_DEFAULT_TAG" = true ]] && ALL_TAGS+=("$DEFAULT_TAG")
[[ ${#ADDITIONAL_TAGS[@]} -gt 0 ]] && ALL_TAGS+=("${ADDITIONAL_TAGS[@]}")

# Add a special tag for corrupted PDFs
[[ "$PDF_CORRUPTED" = true && "$ADD_DEFAULT_TAG" = true ]] && ALL_TAGS+=("Corrupted PDF")

# Build the tag command string using the correct format
TAG_CMD=""
if [[ ${#ALL_TAGS[@]} -gt 0 ]]; then
  TAG_CMD="--tags"
  for tag in "${ALL_TAGS[@]}"; do
    TAG_CMD="$TAG_CMD \"$tag\""
  done
fi

# Show which tags will be applied
echo "Tags configuration:"
if [[ ${#ALL_TAGS[@]} -eq 0 ]]; then
  echo "- No tags will be applied (--no-tag was specified)"
else
  echo "- Tags to be applied: ${ALL_TAGS[*]}"
fi

# Build the Day One command
function build_dayone_cmd() {
  local use_journal=$1
  local cmd="dayone2"
  
  # Add basic parameters
  [[ "$use_journal" = true ]] && cmd+=" -j \"$JOURNAL_NAME\""
  cmd+=" -d \"$DATE\" --all-day"
  
  # Add tags if any
  [[ -n "$TAG_CMD" ]] && cmd+=" $TAG_CMD"
  
  # Add attachments if any
  if [[ ${#PHOTO_ARGS[@]} -gt 0 ]]; then
    cmd+=" -a"
    for PHOTO in "${PHOTO_ARGS[@]}"; do
      cmd+=" \"$PHOTO\""
    done
    cmd+=" --"
  fi
  
  # Add entry content
  cmd+=" new \"$ENTRY_TEXT\""
  
  echo "$cmd"
}

# Build commands for both with and without journal
CMD_WITH_JOURNAL=$(build_dayone_cmd true)
CMD_WITHOUT_JOURNAL=$(build_dayone_cmd false)

# Log the command for debugging
echo "Command to be executed:"
echo "$CMD_WITH_JOURNAL"

# Try with journal first, then fall back to no journal if it fails
echo "Executing command with specified journal..."
echo "DEBUG: Command = $CMD_WITH_JOURNAL"

# Execute the command
RESULT=$(eval $CMD_WITH_JOURNAL 2>&1)
COMMAND_STATUS=$?
echo "DEBUG: Command exit status = $COMMAND_STATUS"
echo "DEBUG: Result = $RESULT"

# Check if there was an error with the journal
if [[ "$RESULT" == *"Invalid value(s) for option -j, --journal"* ]]; then
  echo "Warning: Journal '$JOURNAL_NAME' not found, saving to default journal instead"
  echo "DEBUG: Falling back to command = $CMD_WITHOUT_JOURNAL"
  RESULT=$(eval $CMD_WITHOUT_JOURNAL)
  COMMAND_STATUS=$?
  echo "DEBUG: Fallback command exit status = $COMMAND_STATUS"
fi

# -----------------------------------------------------------------------------
# Clean Up and Show Results
# -----------------------------------------------------------------------------

# Process the result including error checking
if [[ $COMMAND_STATUS -eq 0 ]]; then
  # Extract UUID from Day One response
  ENTRY_UUID=$(echo "$RESULT" | grep -o "uuid: [A-Z0-9]\+" | awk '{print $2}')
  echo "DEBUG: UUID extraction result = '$ENTRY_UUID'"
  
  # Clean up temporary files
  rm -rf "$TEMP_DIR"
  
  # Print success message with deep link if available
  echo "Done! Entry created for $DATE with NYT front page and headlines."
  if [[ -n "$ENTRY_UUID" ]]; then
    echo "View in Day One: dayone://view?entryId=$ENTRY_UUID"
  else
    echo "Warning: Entry was created but UUID could not be extracted from response."
  fi
else
  echo "ERROR: Failed to create Day One entry (exit code $COMMAND_STATUS)"
  echo "ERROR: Command output was: $RESULT"
  
  # Clean up temporary files
  rm -rf "$TEMP_DIR"
  exit $COMMAND_STATUS
fi