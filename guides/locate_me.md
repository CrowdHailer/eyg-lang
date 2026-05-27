---
name: locate me
description: When a user makes a location specific query (what is the weather tomorrow) or asks for anything relative to their location.
---

# Locate Me Skill

Get the user's location information for location-specific queries. Uses the ipinfo.io service to determine basic location data including city, region, country, and coordinates.

The service is documented at https://ipinfo.io/developers

Requests to the service should be made using EYG scripts with the standard HTTP library.

ALWAYS load the `write-eyg` skill before creating a function.
ALWAYS load the `decoding-json` skill when parsing the response.
NEVER return dummy or example data. Tell the user you can't write the script if you keep getting errors.

## Example Usage

```eyg
let {http: http, result: result, string: string} = @standard
let {parse: parse, decode: decode, expect: expect} = @json

let get_location = (_) -> {
  let request = http.get("ipinfo.io")
  let request = http.path(request, "/json")
  match http.send(request) {
    Ok({body: body}) -> {
      match string.from_binary(body) {
        Ok(json_string) -> {
          let decoder = decode.object((decoded) -> {
            let city = decode.field("city", decode.string, decoded)
            let region = decode.field("region", decode.string, decoded)
            let country = decode.field("country", decode.string, decoded)
            let ip = decode.field("ip", decode.string, decoded)
            let loc = decode.field("loc", decode.string, decoded)
            {city: city, region: region, country: country, ip: ip, loc: loc}
          })
          match parse(json_string, decoder) {
            Ok(location) -> { location }
            Error(err) -> { {error: err} }
          }
        }
        Error(_) -> { {error: "failed to read response body"} }
      }
    }
    Error(err) -> { {error: "failed to fetch location"} }
  }
}

let get_city = (_) -> {
  match get_location({}) {
    {error: err} -> { "Unknown" }
    location -> { location.city }
  }
}

{get_location: get_location, get_city: get_city}
```

## Available Functions

### get_location
Fetches complete location information from ipinfo.io.

**Returns:** A record with the following fields on success:
- `city`: The city name
- `region`: The region/state/province
- `country`: The country code (e.g., "US", "GB")
- `ip`: The public IP address
- `loc`: Latitude and longitude as "lat,lon" string

On error, returns `{error: "error message"}`

### get_city
Convenience function that returns just the city name.

**Returns:** The city name as a string, or "Unknown" on error.

## Response Format

The ipinfo.io service returns JSON with the following structure:

```json
{
  "ip": "123.45.67.89",
  "city": "San Francisco",
  "region": "California",
  "country": "US",
  "loc": "37.7749,-122.4194",
  "postal": "94102",
  "timezone": "America/Los_Angeles"
}
```

## Error Handling

The skill handles errors at multiple levels:
1. HTTP request failures (network issues)
2. Response body parsing failures
3. JSON decoding failures

All errors return a record with an `error` field containing a descriptive message.

## Usage Examples

**Get full location info:**
```eyg
let location = get_location({})
```

**Get just the city:**
```eyg
let city = get_city({})
```

**Use in weather queries:**
```eyg
let city = get_city({})
// Then use city to fetch weather data
```

## Notes

- No API key is required for basic usage (limited to 1000 requests/day)
- The service uses the request's IP address to determine location
- For more detailed location data, consider upgrading to a paid ipinfo.io plan
- All requests use HTTPS automatically through the standard HTTP library
