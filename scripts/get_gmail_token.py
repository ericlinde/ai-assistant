"""
One-time script to generate a Gmail OAuth2 refresh token.
Run once locally during setup. The refresh token is then stored as a secret.

Usage: python get_gmail_token.py <client_id> <client_secret>
"""

import sys
from google_auth_oauthlib.flow import InstalledAppFlow

if len(sys.argv) != 3:
    print("Usage: python get_gmail_token.py <client_id> <client_secret>")
    sys.exit(1)

client_id = sys.argv[1]
client_secret = sys.argv[2]

flow = InstalledAppFlow.from_client_config(
    {
        "installed": {
            "client_id": client_id,
            "client_secret": client_secret,
            "redirect_uris": ["http://localhost:8080"],
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
        }
    },
    scopes=["https://mail.google.com/"],
)

creds = flow.run_local_server(port=8080)
print("\nGMAIL_REFRESH_TOKEN:", creds.refresh_token)
