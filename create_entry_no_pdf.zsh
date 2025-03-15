#!/bin/zsh
#
# create_entry_no_pdf.zsh
#
# Creates a Day One entry for dates with corrupt PDFs
# This is a simplified version that skips all PDF processing
#
# Usage: ./create_entry_no_pdf.zsh 2018-01-10

# Set default values
DATE="$1"
JOURNAL_NAME="The New York Times"
API_KEY="$NYT_API_KEY"

# Check if we have a date
if [[ -z "$DATE" ]]; then
  echo "Error: Date is required in YYYY-MM-DD format"
  echo "Usage: $0 YYYY-MM-DD"
  exit 1
fi

# Check for API key
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

# Get required date formats
URL_DATE=$(date -j -f "%Y-%m-%d" "$DATE" +%Y/%m/%d)
YEAR=$(date -j -f "%Y-%m-%d" "$DATE" +%Y)
MONTH=$(date -j -f "%Y-%m-%d" "$DATE" +%-m)
DAY=$(date -j -f "%Y-%m-%d" "$DATE" +%-d)
HEADER_DATE=$(date -j -f "%Y-%m-%d" "$DATE" +"%B %-d")

# Add ordinal suffix 
case $DAY in
    1|21|31) HEADER_DATE="${HEADER_DATE}st" ;;
    2|22)    HEADER_DATE="${HEADER_DATE}nd" ;;
    3|23)    HEADER_DATE="${HEADER_DATE}rd" ;;
    *)       HEADER_DATE="${HEADER_DATE}th" ;;
esac

FORMATTED_MONTH=$(date -j -f "%Y-%m-%d" "$DATE" +%m)
FORMATTED_DAY=$(date -j -f "%Y-%m-%d" "$DATE" +%d)
NYT_ARCHIVE_URL="https://www.nytimes.com/issue/todayspaper/$YEAR/$FORMATTED_MONTH/$FORMATTED_DAY/todays-new-york-times"

echo "Fetching NYT headlines for $DATE..."
/usr/bin/curl -s -o archive.json "https://api.nytimes.com/svc/archive/v1/$YEAR/$MONTH.json?api-key=$API_KEY"

# Extract headlines
if [[ -s archive.json && -n "$(command -v jq)" ]]; then
  PUB_DATE_PREFIX="$YEAR-$(printf "%02d" $MONTH)-$(printf "%02d" $DAY)T"
  
  # Get headlines  
  TOP_HEADLINES=$(jq -r --arg date "$PUB_DATE_PREFIX" \
    '.response.docs[] | select(.pub_date | startswith($date)) | select(.print_page == "1") | 
     "- \(.headline.main)"' \
    archive.json | head -6 | sed -E 's/ [B|b]y [^,]+,?//g')
    
  # If no headlines found, try news articles
  if [[ -z "$TOP_HEADLINES" ]]; then
    TOP_HEADLINES=$(jq -r --arg date "$PUB_DATE_PREFIX" \
      '.response.docs[] | select(.pub_date | startswith($date)) | select(.type_of_material == "News") | 
       "- \(.headline.main)"' \
      archive.json | head -6 | sed -E 's/ [B|b]y [^,]+,?//g')
  fi
else
  echo "Error: jq not found or API response invalid"
  exit 1
fi

# Process headlines
if [[ -n "$TOP_HEADLINES" ]]; then
  FIRST_HEADLINE=$(echo "$TOP_HEADLINES" | head -1 | sed 's/^- //')
  REMAINING_HEADLINES=$(echo "$TOP_HEADLINES" | tail -n +2)
else
  FIRST_HEADLINE="The New York Times"
  REMAINING_HEADLINES=""
fi

# Create entry content
ENTRY_TEXT="#### The New York Times: $HEADER_DATE
$FIRST_HEADLINE
$REMAINING_HEADLINES

$NYT_ARCHIVE_URL"

# Create temp file for entry content
TEMP_FILE=$(mktemp)
echo "$ENTRY_TEXT" > "$TEMP_FILE"

# Create Day One entry with a simpler approach
echo "Creating Day One entry without PDF..."

# Create very simple entry (use actual headlines but simplified approach)
echo "Creating entry for $DATE..."
dayone2 -d "$DATE" -t "The New York Times" -t "Corrupted PDF" new "$ENTRY_TEXT"
RESULT=$?

if [[ $RESULT -eq 0 ]]; then
  echo "Done! Entry created for $DATE with NYT headlines (no PDF attachment)."
else
  echo "Error: Failed to create entry for $DATE."
  exit 1
fi

# Clean up
rm -f "$TEMP_FILE" "$TEMP_FILE.input" "$TEMP_FILE.cmd"
rm -f archive.json