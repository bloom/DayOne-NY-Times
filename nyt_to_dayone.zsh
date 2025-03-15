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
  echo "  $script --bad-pdf 2018-01-10                   # Handle known corrupted PDF and add it to the list"
  
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

# List of corrupted PDFs is now in nyt_corrupt_pdf_list.json

# Function to check if a date has a corrupted PDF
function is_corrupted_pdf() {
  local check_date="$1"
  local json_file="$PWD/nyt_corrupt_pdf_list.json"
  
  # Check if the corrupted PDF list file exists
  if [[ -f "$json_file" ]]; then
    # Check if jq is available for JSON processing
    if (( $+commands[jq] )); then
      # Use jq to check if the date is in the corrupted PDF list
      if jq -e --arg date "$check_date" 'contains([$date])' "$json_file" > /dev/null; then
        return 0  # True, it is corrupted
      fi
    else
      echo "Warning: jq not found, cannot check corrupted PDF list"
      echo "To enable corrupted PDF detection, install jq: brew install jq"
    fi
  else
    echo "Warning: Corrupted PDF list file not found: $json_file"
  fi
  
  return 1  # False, it's not in the corrupted list or we couldn't check
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
      if [[ -z "$DATE" && $# -gt 1 && "$2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        # If no date was provided yet but the next argument is a date, use it
        DATE="$2"
        shift
      fi
      
      if [[ -z "$DATE" ]]; then
        echo "Error: --bad-pdf requires a date. Please specify a date before or after the --bad-pdf option."
        usage
      fi
      
      echo "Marking $DATE as having a corrupted PDF"
      PDF_CORRUPTED=true
      
      # If jq is available, add this date to the corrupted PDF list
      if (( $+commands[jq] )); then
        # Path to the corrupted PDF list file
        local json_file="$PWD/nyt_corrupt_pdf_list.json"
        
        if [[ -f "$json_file" ]]; then
          # Check if date is already in the list
          if ! jq -e --arg date "$DATE" 'contains([$date])' "$json_file" > /dev/null; then
            # Add date to the list and save back to file
            jq --arg date "$DATE" '. + [$date] | sort' "$json_file" > "${json_file}.tmp"
            mv "${json_file}.tmp" "$json_file"
            echo "Added $DATE to corrupted PDF list: $json_file"
          else
            echo "Note: $DATE is already in the corrupted PDF list"
          fi
        else
          # Create a new list with just this date
          echo "[$DATE]" > "$json_file"
          echo "Created new corrupted PDF list: $json_file"
        fi
      else
        echo "Warning: jq not found, cannot update corrupted PDF list"
        echo "To enable adding dates to the corrupted PDF list, install jq: brew install jq"
      fi
      
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

# Check if this date is known to have a corrupted PDF
if is_corrupted_pdf "$DATE" || [[ "$PDF_CORRUPTED" = true ]]; then
  echo "Note: PDF for $DATE is known to be corrupted. Will skip PDF processing."
  # Disable all PDF/JPG processing for this date
  ATTACH_PDF=false
  ATTACH_JPG=false
  # Set corrupted flag for handling during command execution
  PDF_CORRUPTED=true
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

# Corrupted PDF handling:
# 1. We check for corrupted PDFs early in the script (line ~207)
# 2. If a date has a corrupted PDF, we set PDF_CORRUPTED=true
# 3. We disable PDF/JPG processing (ATTACH_PDF=false and ATTACH_JPG=false)
# 4. We add a "Corrupted PDF" tag to the entry
# 5. When executing the dayone2 command, we'll skip the attachment arguments

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
      # Extract data separately to avoid complex jq syntax issues
      TOTAL_ARTICLES=$(jq -r --arg date "$PUB_DATE_PREFIX" '.response.docs | map(select(.pub_date | startswith($date))) | length' archive.json)
      
      # Extract longest article details
      LONGEST_ARTICLE=$(jq -r --arg date "$PUB_DATE_PREFIX" '
        .response.docs 
        | map(select(.pub_date | startswith($date))) 
        | sort_by(.word_count) 
        | reverse 
        | .[0] 
        | "\(.word_count) words | \(.headline.main)"' archive.json)
      
      # Extract opinion pieces
      TOP_OPINIONS=$(jq -r --arg date "$PUB_DATE_PREFIX" '
        .response.docs 
        | map(select(.pub_date | startswith($date)) 
        | select(.news_desk == "OpEd" or .section_name == "Opinion" or .type_of_material == "Op-Ed")) 
        | .[0:3] 
        | map("- \(.headline.main)") 
        | join("\n")' archive.json)
      
      # Extract section counts in a simpler way
      SECTION_DATA=$(jq -r --arg date "$PUB_DATE_PREFIX" '
        .response.docs 
        | map(select(.pub_date | startswith($date)) | .section_name) 
        | group_by(.) 
        | map({name: .[0], count: length}) 
        | sort_by(.count) 
        | reverse 
        | .[0:5]' archive.json)
        
      # Process the section data to create formatted output
      SECTION_COUNTS=""
      while read -r section; do
        name=$(echo "$section" | jq -r '.name // "Uncategorized"')
        count=$(echo "$section" | jq -r '.count')
        SECTION_COUNTS="${SECTION_COUNTS}- $name: $count articles\n"
      done < <(echo "$SECTION_DATA" | jq -c '.[]')
      
      # Extract trending keywords (this is more complex and kept separate)
      TOP_KEYWORDS=$(jq -r --arg date "$PUB_DATE_PREFIX" \
        '.response.docs[] | select(.pub_date | startswith($date)) | .keywords[].value' \
        archive.json | sort | uniq -c | sort -rn | head -10 | 
        awk '{print "- " $2 " " $3 " " $4 " " $5 " " $6 " " $7}' | sed 's/ *$//')
      
      # Create comprehensive content summary
      CONTENT_SUMMARY="### NYT Publication Summary
- Total articles published: $TOTAL_ARTICLES
- Longest article: $LONGEST_ARTICLE

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
if [[ "$ATTACH_JPG" = true || "$ATTACH_PDF" = true ]]; then
  # Entry with image placeholder and headline above
  HEADER="#### The New York Times: $HEADER_DATE
$FIRST_HEADLINE
[{photo}]"
else
  # Entry without image - same for corrupted PDFs and no-attachment entries
  HEADER="#### The New York Times: $HEADER_DATE
$FIRST_HEADLINE"
fi

# Build entry with or without full summary
if [[ "$INCLUDE_FULL_SUMMARY" = true && -n "$CONTENT_SUMMARY" ]]; then
  ENTRY_TEXT="${HEADER}
${REMAINING_HEADLINES}

${CONTENT_SUMMARY}"
else
  ENTRY_TEXT="${HEADER}
${REMAINING_HEADLINES}"
fi

# -----------------------------------------------------------------------------
# Create Day One Entry
# -----------------------------------------------------------------------------

echo "Creating Day One entry..."

# Prepare photo attachment arguments
PHOTO_ARGS=()

# If PDF is corrupted, don't use any attachments
if [[ "$PDF_CORRUPTED" = true ]]; then
  echo "Skipping attachments for corrupted PDF date..."
  # Don't add any attachments
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

# Build tag array for Day One
ALL_TAGS=()

# Populate tag array - add default tag if enabled and any additional tags
[[ "$ADD_DEFAULT_TAG" = true ]] && ALL_TAGS+=("$DEFAULT_TAG")
[[ ${#ADDITIONAL_TAGS[@]} -gt 0 ]] && ALL_TAGS+=("${ADDITIONAL_TAGS[@]}")

# Show which tags will be applied
echo "Tags configuration:"
if [[ ${#ALL_TAGS[@]} -eq 0 ]]; then
  echo "- No tags will be applied (--no-tag was specified)"
else
  echo "- Tags to be applied: ${ALL_TAGS[*]}"
fi

# Create a temporary file for the entry text
TEMP_FILE=$(mktemp)
echo "$ENTRY_TEXT" > "$TEMP_FILE"

# Prepare common arguments for dayone2 command
DAYONE_ARGS=()

# Add journal parameter if specified
if [[ -n "$JOURNAL_NAME" ]]; then
  DAYONE_ARGS+=("-j" "$JOURNAL_NAME")
fi

# Add date and all-day flag
DAYONE_ARGS+=("-d" "$DATE" "--all-day")

# Add tags
if [[ ${#ALL_TAGS[@]} -gt 0 ]]; then
  for tag in "${ALL_TAGS[@]}"; do
    DAYONE_ARGS+=("-t" "$tag")
  done
fi

# Add attachments (only if not a corrupted PDF)
if [[ "$PDF_CORRUPTED" = false && ${#PHOTO_ARGS[@]} -gt 0 ]]; then
  DAYONE_ARGS+=("-a")
  for photo in "${PHOTO_ARGS[@]}"; do
    DAYONE_ARGS+=("$photo")
  done
  DAYONE_ARGS+=("--")
fi

# Use a more direct and simplified approach for creating entries
echo "Executing Day One entry creation command..."

# Create entry with explicit arguments
if [[ -n "$JOURNAL_NAME" ]]; then
  # First try with the specified journal
  if [[ ${#ALL_TAGS[@]} -gt 0 ]]; then
    # With journal and tags
    if [[ ${#PHOTO_ARGS[@]} -gt 0 && "$PDF_CORRUPTED" = false ]]; then
      # With attachments
      COMMAND_OUTPUT=$(dayone2 new -j "$JOURNAL_NAME" -d "$DATE" --all-day --tags "${ALL_TAGS[@]}" -a "${PHOTO_ARGS[@]}" < "$TEMP_FILE")
    else
      # Without attachments (for corrupted PDFs)
      COMMAND_OUTPUT=$(dayone2 new -j "$JOURNAL_NAME" -d "$DATE" --all-day --tags "${ALL_TAGS[@]}" < "$TEMP_FILE")
    fi
    
    # Print the command output
    echo "$COMMAND_OUTPUT"
  else
    # With journal but no tags
    if [[ ${#PHOTO_ARGS[@]} -gt 0 && "$PDF_CORRUPTED" = false ]]; then
      # With attachments
      COMMAND_OUTPUT=$(dayone2 new -j "$JOURNAL_NAME" -d "$DATE" --all-day -a "${PHOTO_ARGS[@]}" < "$TEMP_FILE")
    else
      # Without attachments (for corrupted PDFs)
      COMMAND_OUTPUT=$(dayone2 new -j "$JOURNAL_NAME" -d "$DATE" --all-day < "$TEMP_FILE")
    fi
    
    # Print the command output
    echo "$COMMAND_OUTPUT"
  fi
  COMMAND_STATUS=$?
  
  # If journal not found, retry without journal
  if [[ $COMMAND_STATUS -eq 64 ]]; then
    echo "Warning: Journal '$JOURNAL_NAME' not found, saving to default journal instead"
    
    # Retry without journal specification
    if [[ ${#ALL_TAGS[@]} -gt 0 ]]; then
      # With tags
      if [[ ${#PHOTO_ARGS[@]} -gt 0 && "$PDF_CORRUPTED" = false ]]; then
        # With attachments
        COMMAND_OUTPUT=$(dayone2 new -d "$DATE" --all-day --tags "${ALL_TAGS[@]}" -a "${PHOTO_ARGS[@]}" < "$TEMP_FILE")
      else
        # Without attachments (for corrupted PDFs)
        COMMAND_OUTPUT=$(dayone2 new -d "$DATE" --all-day --tags "${ALL_TAGS[@]}" < "$TEMP_FILE")
      fi
      
      # Print the command output
      echo "$COMMAND_OUTPUT"
    else
      # No tags
      if [[ ${#PHOTO_ARGS[@]} -gt 0 && "$PDF_CORRUPTED" = false ]]; then
        # With attachments
        COMMAND_OUTPUT=$(dayone2 new -d "$DATE" --all-day -a "${PHOTO_ARGS[@]}" < "$TEMP_FILE")
      else
        # Without attachments (for corrupted PDFs)
        COMMAND_OUTPUT=$(dayone2 new -d "$DATE" --all-day < "$TEMP_FILE")
      fi
      
      # Print the command output
      echo "$COMMAND_OUTPUT"
    fi
    COMMAND_STATUS=$?
  fi
else
  # No journal specified, use default
  if [[ ${#ALL_TAGS[@]} -gt 0 ]]; then
    # With tags
    if [[ ${#PHOTO_ARGS[@]} -gt 0 && "$PDF_CORRUPTED" = false ]]; then
      # With attachments
      COMMAND_OUTPUT=$(dayone2 new -d "$DATE" --all-day --tags "${ALL_TAGS[@]}" -a "${PHOTO_ARGS[@]}" < "$TEMP_FILE")
    else
      # Without attachments (for corrupted PDFs)
      COMMAND_OUTPUT=$(dayone2 new -d "$DATE" --all-day --tags "${ALL_TAGS[@]}" < "$TEMP_FILE")
    fi
    
    # Print the command output
    echo "$COMMAND_OUTPUT"
  else
    # No tags
    if [[ ${#PHOTO_ARGS[@]} -gt 0 && "$PDF_CORRUPTED" = false ]]; then
      # With attachments
      COMMAND_OUTPUT=$(dayone2 new -d "$DATE" --all-day -a "${PHOTO_ARGS[@]}" < "$TEMP_FILE")
    else
      # Without attachments (for corrupted PDFs)
      COMMAND_OUTPUT=$(dayone2 new -d "$DATE" --all-day < "$TEMP_FILE")
    fi
    
    # Print the command output
    echo "$COMMAND_OUTPUT"
  fi
  COMMAND_STATUS=$?
fi

# -----------------------------------------------------------------------------
# Clean Up and Show Results
# -----------------------------------------------------------------------------

# Handle the result
if [[ $COMMAND_STATUS -eq 0 ]]; then
  # Clean up temporary files
  rm -f "$TEMP_FILE"
  rm -rf "$TEMP_DIR"
  
  # Extract UUID from command output 
  UUID=$(echo "$COMMAND_OUTPUT" | grep -o 'uuid: [A-F0-9]\{32\}' | cut -d' ' -f2)
  
  # Print success message
  if [[ -n "$UUID" ]]; then
    ENTRY_URL="dayone://view?entryId=$UUID"
    
    if [[ "$PDF_CORRUPTED" = true ]]; then
      echo "Done! Entry created for $DATE with NYT headlines (no PDF attachment)."
      echo "Entry URL: $ENTRY_URL"
    else
      echo "Done! Entry created for $DATE with NYT front page and headlines."
      echo "Entry URL: $ENTRY_URL"
    fi
  else
    # Fallback if we couldn't extract the UUID
    if [[ "$PDF_CORRUPTED" = true ]]; then
      echo "Done! Entry created for $DATE with NYT headlines (no PDF attachment)."
    else
      echo "Done! Entry created for $DATE with NYT front page and headlines."
    fi
  fi
else
  echo "ERROR: Failed to create Day One entry (exit code $COMMAND_STATUS)"
  
  # Clean up temporary files
  rm -f "$TEMP_FILE"
  rm -rf "$TEMP_DIR"
  exit $COMMAND_STATUS
fi