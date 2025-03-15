# NYT Front Page to Day One

A set of Zsh scripts to fetch New York Times front pages and headlines for specific dates or date ranges, converting them to Day One journal entries with attached images and content analysis.

## Features

- Fetches front page PDFs and top headlines for any date
- Creates high-resolution image attachments
- Provides deep links to easily open entries in Day One
- Includes option to show comprehensive content analysis
- Supports batch processing of date ranges (days, weeks, months)
- Links historical events to newspaper dates automatically
- Configurable journal destination

## Requirements

- macOS with Day One app installed
- Day One CLI: `brew install dayone-cli`
- jq for JSON processing: `brew install jq`
- NYT API key (get one from [NYT Developer Portal](https://developer.nytimes.com)) Optional to fetch Top Headlines
- Internet connection

## Setup

1. Create a file named `nyt_api_key.txt` containing your NYT API key:
   ```zsh
   echo "your_api_key_here" > nyt_api_key.txt
   ```
   
   Or set an environment variable:
   ```zsh
   export NYT_API_KEY=your_api_key_here
   ```

2. Make scripts executable:
   ```zsh
   chmod +x *.zsh
   ```

## Usage

### PDF Download

```zsh
# Download all front pages for 2023
./download_nyt_year.zsh 2023

# Download to a specific directory
./download_nyt_year.zsh 2023 --directory ~/Documents/NYT_Archive

# Use longer pause between downloads to avoid rate limiting
./download_nyt_year.zsh 2023 --sleep 5
```

### Single Day Entry

```zsh
# Get today's NYT front page
./nyt_to_dayone.zsh

# Get front page for a specific date
./nyt_to_dayone.zsh 2025-03-10

# Include PDF attachment
./nyt_to_dayone.zsh --pdf 2025-03-10

# Show comprehensive content analysis
./nyt_to_dayone.zsh --full-summary 2025-03-10

# Save to a specific journal 
./nyt_to_dayone.zsh --journal "Historical" 2022-11-09

# With multiple options
./nyt_to_dayone.zsh --pdf --full-summary --journal "Archives" 2025-03-10

# Use a custom headline (overrides historical events)
./nyt_to_dayone.zsh --headline "Custom Headline" 2021-01-07

# Add additional tags
./nyt_to_dayone.zsh --tag "Election" --tag "Politics" 2020-11-04

# Show help
./nyt_to_dayone.zsh --help
```

### Date Range Processing

```zsh
# Fetch all of January 2025
./fetch_nyt_range.zsh 2025-01-01 2025-01-31

# Fetch a custom date range
./fetch_nyt_range.zsh 2025-01-15 2025-01-29

# With content analysis for each day
./fetch_nyt_range.zsh 2025-01-01 2025-01-31 --full-summary

# Save to a specific journal
./fetch_nyt_range.zsh 2025-01-01 2025-01-31 --journal "History"

# Include PDF attachments for the entire range
./fetch_nyt_range.zsh 2025-01-01 2025-01-31 --pdf

# Show help
./fetch_nyt_range.zsh
```

## How It Works

1. **Front Page Retrieval**: Fetches PDFs from the NYT archive at static01.nyt.com
2. **Image Processing**: Converts PDFs to high-resolution JPGs using macOS tools
3. **Content Analysis**: Extracts headlines and content from the NYT Archive API
4. **Historical Integration**: Checks if the date corresponds to a significant historical event
5. **Day One Integration**: Creates formatted journal entries with attachments and appropriate tags
6. **Deep Linking**: Provides direct links to open entries in Day One

## Technical Details

- **Image Processing**: Uses the macOS Quick Look API to convert PDFs to high-quality images
- **Content Extraction**: Parses the NYT Archive API using jq to extract structured data
- **API Key Management**: Supports both environment variables and local file for API key storage
- **Date Processing**: Includes robust date handling for ranges and formatted outputs
- **Historical Events**: Reads from a JSON file to correlate newspaper dates with significant events
- **Journal Selection**: Allows specifying any Day One journal with fallback to default journal if not found
- **Tag Management**: Automatically adds appropriate tags based on entry type
- **Deep Links**: Provides `dayone://view?entryId=UUID` links for direct entry access

## Historical Events

The scripts can automatically integrate historical events with newspaper front pages, creating a more meaningful historical record in Day One.

### How Historical Events Work

1. The `historical-events.json` file contains a list of significant historical events with their dates
2. When creating an entry, the script checks if the newspaper date corresponds to an event from the previous day
3. If a match is found, the event is displayed as the top headline above the front page image
4. All regular headlines are still included below the image
5. Entries with historical events receive both "The New York Times" and "Historical Event" tags

### Historical Events File Format

```json
[
    {"Date": "January 6, 2021", "Event": "Attack on the U.S. Capitol by pro-Trump rioters"},
    {"Date": "November 8, 2016", "Event": "Donald Trump elected as the 45th U.S. President"}
]
```

### Creating Historical Event Entries

```zsh
# Process all historical events in the JSON file
./fetch_historical.zsh

# Process only events from 2020 onwards
./fetch_historical.zsh --start-date 2020-01-01

# Process only specific events
./fetch_historical.zsh --event "Capitol"

# Show what would be done without creating entries
./fetch_historical.zsh --dry-run

# Save to a specific journal
./fetch_historical.zsh --journal "History"

# Show help
./fetch_historical.zsh --help
```

## Notes

- Regular entries are created with "The New York Times" tag
- Historical event entries receive both "The New York Times" and "Historical Event" tags
- Images are placed in the entry using the Day One `[{photo}]` placeholder
- Scripts include delays to avoid API rate limiting
- These scripts use native Zsh features and are optimized for macOS
- Due to NYT archive limitations, only dates from July 2012 onwards are supported