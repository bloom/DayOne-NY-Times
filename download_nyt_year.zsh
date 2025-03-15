#!/bin/zsh
#
# download_nyt_year.zsh
#
# Downloads New York Times front page PDFs for an entire year
# and organizes them into a directory structure by month.
#
# Author: Paul Mayne
# Last Updated: 2024-03-14

# -----------------------------------------------------------------------------
# Function Definitions
# -----------------------------------------------------------------------------

# Display usage information
function usage() {
  local script=$(basename "$0")
  
  echo "Usage: ./download_nyt_year.zsh YEAR [options]"
  echo ""
  echo "Arguments:"
  echo "  YEAR: The year to download (YYYY format, must be 2012 or later)"
  echo ""
  echo "Options:"
  echo "  -d, --directory DIR  Specify download directory (default: ~/Downloads/NYT_YEAR)"
  echo "  -s, --sleep SEC      Sleep time between downloads in seconds (default: 2)"
  echo "  -h, --help           Show this help message"
  echo ""
  echo "Examples:"
  echo "  ./download_nyt_year.zsh 2022                      # Download all of 2022"
  echo "  ./download_nyt_year.zsh 2023 --directory ~/NYT    # Download to custom directory"
  echo "  ./download_nyt_year.zsh 2024 --sleep 5            # Use longer delay between downloads"
  
  exit 1
}

# Create month name from number
function get_month_name() {
  local month_num=$1
  local month_names=("January" "February" "March" "April" "May" "June" "July" "August" "September" "October" "November" "December")
  echo ${month_names[$month_num-1]}
}

# Download a PDF for a specific date
function download_pdf() {
  local year=$1
  local month=$2
  local day=$3
  local output_path=$4
  
  # Format date components for URL
  local month_padded=$(printf "%02d" $month)
  local day_padded=$(printf "%02d" $day)
  
  # Build URL
  local url="https://static01.nyt.com/images/$year/$month_padded/$day_padded/nytfrontpage/scan.pdf"
  
  # Format date for output - include month name in filename
  local month_name=$(get_month_name $month)
  local date_format="$year-$month_padded-$day_padded"
  
  echo "Downloading front page for $date_format..."
  
  # Create output filename
  local output_file="$output_path/NYT_$date_format.pdf"
  
  # Download the PDF with user agent to avoid potential restrictions
  curl -s -o "$output_file" -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15" "$url"
  
  # Check if download was successful
  if [[ -s "$output_file" ]]; then
    echo "✓ Success: Saved to $output_file"
    return 0
  else
    echo "✗ Failed: Could not download front page for $date_format"
    rm -f "$output_file"  # Remove empty file
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Input Validation and Setup
# -----------------------------------------------------------------------------

# Default settings
SLEEP_TIME=2   # Default sleep between downloads
YEAR=""
OUTPUT_DIR=""

# Parse command line arguments
while (( $# > 0 )); do
  case "$1" in
    -h|--help)
      usage
      ;;
    -d|--directory)
      if (( $# > 1 )); then
        OUTPUT_DIR="$2"
        shift 2
      else
        echo "Error: --directory requires a path"
        usage
      fi
      ;;
    -s|--sleep)
      if (( $# > 1 )); then
        SLEEP_TIME="$2"
        shift 2
      else
        echo "Error: --sleep requires a value in seconds"
        usage
      fi
      ;;
    *)
      # Check if argument is a year
      if [[ "$1" =~ ^[0-9]{4}$ ]]; then
        YEAR="$1"
        shift
      else
        echo "Error: Unknown option or invalid year format: $1"
        usage
      fi
      ;;
  esac
done

# Validate year
if [[ -z "$YEAR" ]]; then
  echo "Error: Year is required"
  usage
fi

# Check for date limitations
if (( YEAR < 2012 )); then
  echo "Error: NYT front page PDFs are only reliably available from 2012 onwards"
  echo "Please specify a year of 2012 or later"
  exit 1
fi

# Set output directory if not specified
if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$HOME/Downloads/NYT_$YEAR"
fi

# -----------------------------------------------------------------------------
# Main Script Execution
# -----------------------------------------------------------------------------

echo "Downloading NYT front pages for $YEAR"
echo "Output directory: $OUTPUT_DIR"
echo "Sleep time between downloads: $SLEEP_TIME seconds"
echo ""

# Create base directory
mkdir -p "$OUTPUT_DIR"

# Statistics
TOTAL_DOWNLOADS=0
SUCCESSFUL_DOWNLOADS=0
FAILED_DOWNLOADS=0

# Process each month
for month in {1..12}; do
  # Get month name for display purposes only
  month_name=$(get_month_name $month)
  
  echo ""
  echo "Processing month: $month_name"
  
  # Track statistics for this month
  month_successful_start=$SUCCESSFUL_DOWNLOADS
  month_total_start=$TOTAL_DOWNLOADS
  
  # Determine number of days in the month
  case $month in
    2) # February
      if (( YEAR % 400 == 0 || (YEAR % 4 == 0 && YEAR % 100 != 0) )); then
        days_in_month=29  # Leap year
      else
        days_in_month=28
      fi
      ;;
    4|6|9|11) # April, June, September, November
      days_in_month=30
      ;;
    *) # January, March, May, July, August, October, December
      days_in_month=31
      ;;
  esac
  
  # Skip future months in the current year
  current_year=$(date +%Y)
  current_month=$(date +%-m)
  
  if [[ $YEAR -eq $current_year && $month -gt $current_month ]]; then
    echo "Skipping future month: $month_name $YEAR"
    continue
  fi
  
  # Process each day in the month
  for day in $(seq 1 $days_in_month); do
    # Skip future days in the current month/year
    if [[ $YEAR -eq $current_year && $month -eq $current_month ]]; then
      current_day=$(date +%-d)
      if [[ $day -gt $current_day ]]; then
        echo "Skipping future date: $YEAR-$month-$day"
        continue
      fi
    fi
    
    # Special case for 2012 - only July onward is available
    if [[ $YEAR -eq 2012 && $month -lt 7 ]]; then
      echo "Skipping dates before July 2012 (not available)"
      break
    fi
    
    # Download PDF directly to the output directory (no month subfolders)
    TOTAL_DOWNLOADS=$((TOTAL_DOWNLOADS + 1))
    if download_pdf $YEAR $month $day "$OUTPUT_DIR"; then
      SUCCESSFUL_DOWNLOADS=$((SUCCESSFUL_DOWNLOADS + 1))
    else
      FAILED_DOWNLOADS=$((FAILED_DOWNLOADS + 1))
    fi
    
    # Avoid rate limiting
    sleep $SLEEP_TIME
  done
  
  month_successful=$((SUCCESSFUL_DOWNLOADS - month_successful_start))
  month_total=$((TOTAL_DOWNLOADS - month_total_start))
  echo "Completed month: $month_name ($month_successful/$month_total successful)"
done

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo "Download Summary for $YEAR:"
echo "  Total attempted downloads: $TOTAL_DOWNLOADS"
echo "  Successful downloads: $SUCCESSFUL_DOWNLOADS"
echo "  Failed downloads: $FAILED_DOWNLOADS"
echo ""
echo "Files saved to: $OUTPUT_DIR"
echo ""

# Open the directory in Finder
open "$OUTPUT_DIR"

exit 0