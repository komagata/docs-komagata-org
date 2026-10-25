# Lokka Google Analytics

Google Analytics plugin for Lokka.

## Installation

    $ cd LOKKA_ROOT/public/plugin
    $ git clone git://github.com/komagata/lokka-google_analytics.git

## Usage

Enter a GA4 Measurement ID (for example, `G-XXXXXXXXXX`) or a legacy
Universal Analytics Tracker ID (for example, `UA-12345-1`) on the plugin settings page.
The existing optional Domain Name field is retained.

GA4 IDs load gtag.js and send the default page view through `gtag('config', ...)`.
Legacy UA IDs retain the analytics.js initialization and page view call.
Only IDs matching `G-` followed by uppercase letters or digits, or `UA-` followed
by digits, a hyphen, and digits are accepted. Blank or malformed IDs emit no tracking script.

Tracking scripts are included only in production (`RACK_ENV=production`) for
visitors who are not logged in.
