extends RefCounted

# Pure helpers for the Daily Challenge mod. No node lifecycle, no API access —
# everything in this file is testable by hand from a fresh GDScript instance.

# 64-bit FNV-1a constants. The offset's high bit is set, so as a signed Int64
# the literal is negative — `0xCBF29CE484222325` and `-3750763034362895579`
# share the same bit pattern in two's complement and the XOR/multiply ops
# below operate on bits, not interpreted sign. GDScript Int64 multiplication
# wraps modulo 2^64 silently, so no explicit mask is needed to keep `h`
# 64 bits wide.
const FNV_OFFSET_64 := -3750763034362895579  # 0xCBF29CE484222325
const FNV_PRIME_64 := 1099511628211          # 0x100000001B3


# Returns today's date in UTC as "YYYY-MM-DD". The seed boundary is UTC midnight
# so two players in different timezones see the same daily challenge whenever
# their wall clocks are on the same UTC day.
static func utc_date_string() -> String:
    var dict := Time.get_date_dict_from_unix_time(int(Time.get_unix_time_from_system()))
    return "%04d-%02d-%02d" % [int(dict.year), int(dict.month), int(dict.day)]


# 64-bit FNV-1a. Deterministic, fast, and fine for seeding a per-day RNG.
# Collision space is 2^64 — birthday-paradox 50% collision probability lives
# around 2^32 inputs (~4 billion days, ~11.7 million years). Practical
# guarantee: no two distinct date strings will ever land on the same seed.
# Not crypto — don't use for hashing secrets.
static func fnv1a64(s: String) -> int:
    var h := FNV_OFFSET_64
    for byte in s.to_utf8_buffer():
        h = (h ^ int(byte)) * FNV_PRIME_64
    return h


# Returns 1 if `today` is the calendar day after `prior` (UTC), 0 if same day,
# -1 if there's a gap or `prior` is empty/invalid. Used by streak logic.
static func day_delta(today: String, prior: String) -> int:
    if prior.is_empty():
        return -1
    if today == prior:
        return 0
    var a := _parse_iso_date(prior)
    var b := _parse_iso_date(today)
    if a.is_empty() or b.is_empty():
        return -1
    var ts_a := Time.get_unix_time_from_datetime_dict(a)
    var ts_b := Time.get_unix_time_from_datetime_dict(b)
    var diff := int(round((ts_b - ts_a) / 86400.0))
    return 1 if diff == 1 else -1


static func _parse_iso_date(s: String) -> Dictionary:
    var parts := s.split("-")
    if parts.size() != 3:
        return {}
    return {
        "year": int(parts[0]),
        "month": int(parts[1]),
        "day": int(parts[2]),
        "hour": 0, "minute": 0, "second": 0,
    }
