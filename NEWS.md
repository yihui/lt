# CHANGES IN lt VERSION 0.2

- Added `lt_export()` to save an lt table to a file: `.html` (an HTML table, optionally baked to a static `<table>` via Node.js or a headless browser so it needs no JavaScript to view), `.pdf` (a vector PDF), or `.png` (a raster image). PDF and PNG are rendered in a headless Chromium browser and cropped tightly to the table by default.

# CHANGES IN lt VERSION 0.1

- Initial CRAN release.
