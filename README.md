# MCI Internet Packages Client

A lightweight Python client to fetch **unused internet package bytes**
from MCI (`my.mci.ir`) API.

------------------------------------------------------------------------

## Features

- Login + Refresh token handling
- ️Reuses existing session (avoids unnecessary login)
- Extracts all `unusedAmount` values from response
- Automatically stores tokens in `.env`
- Retry on expired session

------------------------------------------------------------------------

## Requirements

- Python 3.10+
- `requests`

Install dependencies:

``` bash
pip install requests python-dotenv
```

------------------------------------------------------------------------

## Environment Variables

Create a `.env` file:

``` env
MCI_USERNAME="9123456789"
MCI_PASSWORD="your_password"

MCI_ACCESS_TOKEN=""
MCI_REFRESH_TOKEN=""
MCI_SESSION_STATE=""
MCI_ACCESS_TOKEN_EXPIRES_AT=""
MCI_REFRESH_TOKEN_EXPIRES_AT=""
```

------------------------------------------------------------------------

## Usage

``` python
from client import MCIInternetClient

client = MCIInternetClient(".env")

unused_bytes = client.get_unused_amounts_bytes()

print(unused_bytes)
```

------------------------------------------------------------------------

## How It Works

1. Tries existing `access_token`
2. If expired → tries `refresh_token`
3. If that fails → logs in again
4. Saves new tokens to `.env`

------------------------------------------------------------------------

## Notes

- This API may require:
    - Iranian IP 🇮🇷
    - Proper headers (User-Agent, Origin, Referer, platform, version)
- If you get SSL errors → check headers and waite for some minutes

------------------------------------------------------------------------

## License

MIT
