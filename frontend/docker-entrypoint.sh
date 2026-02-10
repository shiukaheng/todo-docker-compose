#!/bin/sh

# Inject runtime configuration into index.html
# This allows setting API_URL without rebuilding the image

if [ -n "$API_URL" ]; then
    # Replace the default config with the actual URL
    sed -i "s|defaultApiUrl: \"\"|defaultApiUrl: \"${API_URL}\"|g" /usr/share/nginx/html/index.html
    echo "Configured API_URL: $API_URL"
else
    echo "No API_URL set - using relative URLs via proxy"
fi

exec "$@"
