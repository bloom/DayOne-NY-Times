#!/bin/zsh
#
# nyt_to_dayone.zsh
#
# Fetches New York Times front page and headlines for a specific date
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
  echo "  --journal NAME   Specify Day One journal name (default: New York Times)"
  echo ""
  echo "Environment variables:"
  echo "  NYT_API_KEY      Your New York Times API key (required)"
  echo ""
  echo "Examples:"
  echo "  $script                                       # Get today's front page"
  echo "  $script 2024-03-14                            # Get front page for specific date" 
  echo "  $script --pdf 2024-01-01                      # Include PDF attachment"
  echo "  $script --journal \"History\" 2022-09-08        # Save to different journal"
  
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

# Get day of month for filtering headlines
DAY=$(date -j -f "%Y-%m-%d" "$DATE" +%-d)

# Create formatted dates for URLs and display
FORMATTED_DATE=$(date -j -f "%Y-%m-%d" "$DATE" +"%A, %B %d, %Y")
FORMATTED_MONTH=$(date -j -f "%Y-%m-%d" "$DATE" +%m)
FORMATTED_DAY=$(date -j -f "%Y-%m-%d" "$DATE" +%d)
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

# Process API response if successful
if [[ -s archive.json ]]; then
  # Check if jq is available for JSON processing
  if (( $+commands[jq] )); then
    # Format date prefix for API filtering (YYYY-MM-DDT format)
    PUB_DATE_PREFIX="$YEAR-$(printf "%02d" $MONTH)-$(printf "%02d" $DAY)T"
    
    echo "Extracting content for $DATE..."
    
    # Extract top headlines from front page articles (we'll remove author info later)
    TOP_HEADLINES=$(jq -r --arg date "$PUB_DATE_PREFIX" \
      '.response.docs[] | select(.pub_date | startswith($date)) | select(.print_page == "1") | 
       "- \(.headline.main)"' \
      archive.json | head -6)
    
    # If no front page articles found, try news articles
    if [[ -z "$TOP_HEADLINES" ]]; then
      TOP_HEADLINES=$(jq -r --arg date "$PUB_DATE_PREFIX" \
        '.response.docs[] | select(.pub_date | startswith($date)) | select(.type_of_material == "News") | 
         "- \(.headline.main)"' \
        archive.json | head -6)
    fi
    
    # Remove author information from headlines (anything starting with " By ")
    if [[ -n "$TOP_HEADLINES" ]]; then
      TOP_HEADLINES=$(echo "$TOP_HEADLINES" | sed -E 's/ [B|b]y [^,]+,?//g')
    fi
    
    # If still no headlines found (e.g., very recent date), add a note
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
        echo "Note: No headlines found for this date"
        TOP_HEADLINES="- No headlines found for this date"
        FIRST_HEADLINE="New York Times"
      fi
    fi
    
    # Only build full summary if requested
    if [[ "$INCLUDE_FULL_SUMMARY" = true ]]; then
      # Count total articles for this day
      TOTAL_ARTICLES=$(jq --arg date "$PUB_DATE_PREFIX" \
        '.response.docs | map(select(.pub_date | startswith($date))) | length' \
        archive.json)
      
      # Extract opinion pieces
      TOP_OPINIONS=$(jq -r --arg date "$PUB_DATE_PREFIX" \
        '.response.docs[] | select(.pub_date | startswith($date)) | 
         select(.news_desk == "OpEd" or .section_name == "Opinion" or .type_of_material == "Op-Ed") | 
         "- \(.headline.main) \(.byline.original // "")"' \
        archive.json | head -3)
      
      # Extract trending keywords
      TOP_KEYWORDS=$(jq -r --arg date "$PUB_DATE_PREFIX" \
        '.response.docs[] | select(.pub_date | startswith($date)) | .keywords[].value' \
        archive.json | sort | uniq -c | sort -rn | head -10 | 
        awk '{print "- " $2 " " $3 " " $4 " " $5 " " $6 " " $7}' | sed 's/ *$//')
      
      # Get section breakdown
      SECTION_COUNTS=$(jq -r --arg date "$PUB_DATE_PREFIX" \
        '.response.docs[] | select(.pub_date | startswith($date)) | .section_name' \
        archive.json | sort | uniq -c | sort -rn | head -5 | 
        awk '{print "- " $2 ": " $1 " articles"}' | sed 's/^- :/- Uncategorized:/')
      
      # Find longest article
      LONGEST_ARTICLE=$(jq -r --arg date "$PUB_DATE_PREFIX" \
        '.response.docs[] | select(.pub_date | startswith($date)) | 
         "\(.word_count) words | \(.headline.main) \(.byline.original // "")"' \
        archive.json | sort -rn | head -1)
      
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
  FIRST_HEADLINE="New York Times"
  REMAINING_HEADLINES=""
fi

# Create entry text with appropriate format
if [[ "$ATTACH_JPG" = true || "$ATTACH_PDF" = true ]]; then
  # Entry with image placeholder and headline above
  HEADER="#### 🗞 The New York Times:
$FIRST_HEADLINE
[{photo}]"
else
  # Entry without image
  HEADER="#### 🗞 The New York Times:
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
if [[ "$ATTACH_JPG" = true && "$ATTACH_PDF" = true ]]; then
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

# Build Day One commands (with and without journal name)
if [[ ${#PHOTO_ARGS[@]} -gt 0 ]]; then
  # For entries with attachments
  ATTACHMENT_CMD="-a"
  for PHOTO in "${PHOTO_ARGS[@]}"; do
    ATTACHMENT_CMD="$ATTACHMENT_CMD \"$PHOTO\""
  done
  
  # Command with specified journal
  CMD_WITH_JOURNAL="dayone2 -j \"$JOURNAL_NAME\" -d \"$DATE\" --all-day -t \"New York Times\" $ATTACHMENT_CMD -- new \"$ENTRY_TEXT\""
  
  # Command without specifying journal (uses default)
  CMD_WITHOUT_JOURNAL="dayone2 -d \"$DATE\" --all-day -t \"New York Times\" $ATTACHMENT_CMD -- new \"$ENTRY_TEXT\""
else
  # For entries without attachments
  CMD_WITH_JOURNAL="dayone2 -j \"$JOURNAL_NAME\" -d \"$DATE\" --all-day -t \"New York Times\" new \"$ENTRY_TEXT\""
  CMD_WITHOUT_JOURNAL="dayone2 -d \"$DATE\" --all-day -t \"New York Times\" new \"$ENTRY_TEXT\""
fi

# Try with journal first, then fall back to no journal if it fails
echo "Executing command with specified journal..."
RESULT=$(eval $CMD_WITH_JOURNAL 2>&1)

# Check if there was an error with the journal
if [[ "$RESULT" == *"Invalid value(s) for option -j, --journal"* ]]; then
  echo "Warning: Journal '$JOURNAL_NAME' not found, saving to default journal instead"
  RESULT=$(eval $CMD_WITHOUT_JOURNAL)
fi

# -----------------------------------------------------------------------------
# Clean Up and Show Results
# -----------------------------------------------------------------------------

# Extract UUID from Day One response
ENTRY_UUID=$(echo "$RESULT" | grep -o "uuid: [A-Z0-9]\+" | awk '{print $2}')

# Clean up temporary files
rm -rf "$TEMP_DIR"

# Print success message with deep link if available
echo "Done! Entry created for $DATE with NYT front page and headlines."
if [[ -n "$ENTRY_UUID" ]]; then
  echo "View in Day One: dayone://view?entryId=$ENTRY_UUID"
fi