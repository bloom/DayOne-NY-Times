# NYT Front Page to Day One

A set of Zsh scripts to fetch New York Times front pages and headlines for specific dates or date ranges, converting them to Day One journal entries with attached images and content analysis.

## Features

- Fetches front page PDFs and top headlines for any date
- Creates high-resolution image attachments
- Provides deep links to easily open entries in Day One
- Includes option to show comprehensive content analysis
- Supports batch processing of date ranges (days, weeks, months)
- Configurable journal destination

## Requirements

- macOS with Day One app installed
- Day One CLI: `brew install dayone-cli`
- jq for JSON processing: `brew install jq`
- NYT API key (get one from [NYT Developer Portal](https://developer.nytimes.com))
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
4. **Day One Integration**: Creates formatted journal entries with attachments
5. **Deep Linking**: Provides direct links to open entries in Day One

## Technical Details

- **Image Processing**: Uses the macOS Quick Look API to convert PDFs to high-quality images
- **Content Extraction**: Parses the NYT Archive API using jq to extract structured data
- **API Key Management**: Supports both environment variables and local file for API key storage
- **Date Processing**: Includes robust date handling for ranges and formatted outputs
- **Journal Selection**: Allows specifying any Day One journal with fallback to default journal if not found
- **Deep Links**: Provides `dayone://view?entryId=UUID` links for direct entry access

## Notes

- Entries are created with "New York Times" tag
- Images are placed in the entry using the Day One `[{photo}]` placeholder
- Scripts include delays to avoid API rate limiting
- These scripts use native Zsh features and are optimized for macOS
- Due to NYT archive limitations, only dates from July 2012 onwards are supported