#!/bin/sh

# Replace API_URL placeholder in built JS files at runtime
# This allows configuring the API endpoint without rebuilding

if [ -n "$API_URL" ]; then
    # Find and replace the default API URL in JS files
    find /usr/share/nginx/html -name '*.js' -exec sed -i "s|http://workstation.local:8000|${API_URL}|g" {} \;
    echo "Configured API_URL: $API_URL"
fi

exec "$@"
