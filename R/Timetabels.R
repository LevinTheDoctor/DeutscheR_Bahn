library(httr2)
library(xml2)
library(tibble)
library(purrr)


TimetabelsAPI_Request <- function(url_end) {
  url <- glue::glue("https://apis.deutschebahn.com/db-api-marketplace/apis/timetables/v1/{url_end}")

  client_id <- Sys.getenv("DB_CLIENT_ID")
  client_secret <- Sys.getenv("DB_CLIENT_SECRET")

  request(url) |>
    req_headers(
      "DB-Client-ID" = client_id,
      "DB-Api-Key"   = client_secret
    ) |>
    req_perform() |>
    resp_body_xml()
}

# Prüft Datum (YYMMDD) und Stunde (HH) vor dem Request
validate_date_hour <- function(date, hour) {
  date <- as.character(date)
  hour <- as.character(hour)

  if (!grepl("^[0-9]{6}$", date)) {
    stop("Datum muss im Format YYMMDD sein (z.B. '260619'), bekommen: '", date, "'")
  }
  parsed <- as.Date(date, format = "%y%m%d")
  if (is.na(parsed)) {
    stop("Datum '", date, "' ist kein gültiges Datum.")
  }

  if (!grepl("^[0-9]{2}$", hour)) {
    stop("Stunde muss im Format HH sein (z.B. '08'), bekommen: '", hour, "'")
  }
  h <- as.integer(hour)
  if (h < 0 || h > 23) {
    stop("Stunde muss zwischen 00 und 23 liegen, bekommen: '", hour, "'")
  }

  list(date = date, hour = hour)
}

# DB-Zeitstempel "YYMMddHHmm" -> POSIXct (Europe/Berlin)
parse_db_time <- function(x) {
  as.POSIXct(x, format = "%y%m%d%H%M", tz = "Europe/Berlin")
}

# Wandelt ein <timetable>-XML (fchg/rchg/plan) in einen Tibble um:
# eine Zeile pro Stop mit ar_* / dp_* Spalten.
parse_timetable_xml <- function(xml) {
  station_name <- xml2::xml_attr(xml, "station")
  station_eva  <- xml2::xml_attr(xml, "eva")

  stops <- xml2::xml_find_all(xml, ".//s")

  if (length(stops) == 0) {
    return(empty_timetable_tibble())
  }

  purrr::map(stops, function(s) {
    tl <- xml2::xml_find_first(s, "./tl")
    ar <- xml2::xml_find_first(s, "./ar")
    dp <- xml2::xml_find_first(s, "./dp")

    tibble::tibble(
      station             = station_name,
      station_eva         = station_eva,
      stop_id             = xml2::xml_attr(s, "id"),
      eva                 = xml2::xml_attr(s, "eva"),
      trip_category       = xml2::xml_attr(tl, "c"),
      trip_number         = xml2::xml_attr(tl, "n"),
      trip_owner          = xml2::xml_attr(tl, "o"),
      trip_type           = xml2::xml_attr(tl, "t"),
      trip_filter         = xml2::xml_attr(tl, "f"),
      ar_planned_time     = parse_db_time(xml2::xml_attr(ar, "pt")),
      ar_changed_time     = parse_db_time(xml2::xml_attr(ar, "ct")),
      ar_planned_platform = xml2::xml_attr(ar, "pp"),
      ar_changed_platform = xml2::xml_attr(ar, "cp"),
      ar_planned_path     = xml2::xml_attr(ar, "ppth"),
      ar_changed_path     = xml2::xml_attr(ar, "cpth"),
      ar_line             = xml2::xml_attr(ar, "l"),
      ar_changed_status   = xml2::xml_attr(ar, "cs"),
      ar_planned_status   = xml2::xml_attr(ar, "ps"),
      dp_planned_time     = parse_db_time(xml2::xml_attr(dp, "pt")),
      dp_changed_time     = parse_db_time(xml2::xml_attr(dp, "ct")),
      dp_planned_platform = xml2::xml_attr(dp, "pp"),
      dp_changed_platform = xml2::xml_attr(dp, "cp"),
      dp_planned_path     = xml2::xml_attr(dp, "ppth"),
      dp_changed_path     = xml2::xml_attr(dp, "cpth"),
      dp_line             = xml2::xml_attr(dp, "l"),
      dp_changed_status   = xml2::xml_attr(dp, "cs"),
      dp_planned_status   = xml2::xml_attr(dp, "ps")
    )
  }) |>
    purrr::list_rbind()
}

empty_timetable_tibble <- function() {
  tibble::tibble(
    station             = character(),
    station_eva         = character(),
    stop_id             = character(),
    eva                 = character(),
    trip_category       = character(),
    trip_number         = character(),
    trip_owner          = character(),
    trip_type           = character(),
    trip_filter         = character(),
    ar_planned_time     = as.POSIXct(character(), tz = "Europe/Berlin"),
    ar_changed_time     = as.POSIXct(character(), tz = "Europe/Berlin"),
    ar_planned_platform = character(),
    ar_changed_platform = character(),
    ar_planned_path     = character(),
    ar_changed_path     = character(),
    ar_line             = character(),
    ar_changed_status   = character(),
    ar_planned_status   = character(),
    dp_planned_time     = as.POSIXct(character(), tz = "Europe/Berlin"),
    dp_changed_time     = as.POSIXct(character(), tz = "Europe/Berlin"),
    dp_planned_platform = character(),
    dp_changed_platform = character(),
    dp_planned_path     = character(),
    dp_changed_path     = character(),
    dp_line             = character(),
    dp_changed_status   = character(),
    dp_planned_status   = character()
  )
}

# Wandelt ein <stations>-XML in einen Tibble um.
parse_stations_xml <- function(xml) {
  stations <- xml2::xml_find_all(xml, ".//station")

  tibble::tibble(
    name      = xml2::xml_attr(stations, "name"),
    eva       = xml2::xml_attr(stations, "eva"),
    ds100     = xml2::xml_attr(stations, "ds100"),
    platforms = xml2::xml_attr(stations, "p"),
    meta      = xml2::xml_attr(stations, "meta")
  )
}

# Returns all known changes for a station
fchg_Request <- function(evaNo){
  TimetabelsAPI_Request(glue::glue("fchg/{evaNo}")) |>
    parse_timetable_xml()
}

# Returns all recent changes for a station
rchg_Request <- function(evaNo){
  TimetabelsAPI_Request(glue::glue("rchg/{evaNo}")) |>
    parse_timetable_xml()
}

# Returns planned data for the specified station within an hourly time slice
# Datums Format YYMMDD
# Zeit in HH
plan_Request <- function(evaNo, date, hour){
  v <- validate_date_hour(date, hour)
  TimetabelsAPI_Request(glue::glue("plan/{evaNo}/{v$date}/{v$hour}")) |>
    parse_timetable_xml()
}

# Hier findet man die EVA_No
# pattern unterstützt Wildcards: "Frankfurt*", "*Hbf", "*Frankfurt*"
# Ohne Wildcard sucht die TimetabelsAPI nach exaktem Namen.
station_Request <- function(pattern){
  encoded <- utils::URLencode(pattern, reserved = FALSE)
  TimetabelsAPI_Request(glue::glue("station/{encoded}")) |>
    parse_stations_xml()
}

