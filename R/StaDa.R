library(httr2)
library(tibble)
library(purrr)

# Umlaute werden von der StaDa-API in searchstring nicht akzeptiert.
# Helfer: ä -> ae, ö -> oe, ü -> ue, ß -> ss (analog für Großbuchstaben).
transliterate_umlauts <- function(x) {
  if (is.null(x)) return(NULL)
  chartr_map <- c(
    "ä" = "ae", "ö" = "oe", "ü" = "ue", "ß" = "ss",
    "Ä" = "Ae", "Ö" = "Oe", "Ü" = "Ue"
  )
  for (from in names(chartr_map)) {
    x <- gsub(from, chartr_map[[from]], x, fixed = TRUE)
  }
  x
}

# Basis-Request für die StaDa v2 API.
# `query` ist eine benannte Liste mit Query-Params; NULL-Werte werden
# von req_url_query() automatisch weggelassen.
StaDa_Request <- function(path, query = list()) {
  url <- paste0(
    "https://apis.deutschebahn.com/db-api-marketplace/apis/station-data/v2",
    path
  )

  req <- request(url) |>
    req_headers(
      "DB-Client-ID" = Sys.getenv("DB_CLIENT_ID"),
      "DB-Api-Key"   = Sys.getenv("DB_CLIENT_SECRET"),
      "Accept"       = "application/json"
    )

  # Query-Parameter nur setzen, wenn welche da sind
  if (length(query) > 0) {
    req <- rlang::inject(req_url_query(req, !!!query))
  }

  req |>
    req_perform() |>
    resp_body_json()
}

# /stations Endpoint mit allen optionalen Parametern aus der StaDa-Doku.
# Alle Parameter sind optional (NULL = nicht senden).
# searchstring: unterstützt Wildcards * und ?, sowie kommagetrennte Listen
#               (z.B. "hamburg*,berlin*"). Umlaute werden automatisch
#               in ae/oe/ue umgewandelt.
# limit:        max. Treffer (Server-Maximum 10000)
# offset:       für Paginierung
# category:     Stations-Kategorie 1-7, auch Listen ("2-4" oder "1,3-5")
# federalstate: deutsches Bundesland, auch Listen ("bayern,hamburg")
# eva:          EVA-Nummer (kein Wildcard)
# ril:          Ril100/DS100-Code (kein Wildcard)
# logicaloperator: "and" (Default) oder "or" für Kombination der Filter
stada_stations <- function(searchstring   = NULL,
                           limit          = NULL,
                           offset         = NULL,
                           category       = NULL,
                           federalstate   = NULL,
                           eva            = NULL,
                           ril            = NULL,
                           logicaloperator = NULL) {

  query <- list(
    searchstring    = transliterate_umlauts(searchstring),
    limit           = limit,
    offset          = offset,
    category        = category,
    federalstate    = federalstate,
    eva             = eva,
    ril             = ril,
    logicaloperator = logicaloperator
  )
  # NULLs rausfiltern
  query <- query[!vapply(query, is.null, logical(1))]

  StaDa_Request("/stations", query)
}

# Wandelt die /stations JSON-Antwort in einen flachen Tibble.
# Komplexe Felder (evaNumbers, ril100Identifiers, mailingAddress, ...)
# bleiben als list-columns erhalten, sodass nichts verloren geht.
parse_stada_stations <- function(json) {
  result <- json$result
  if (length(result) == 0) {
    return(tibble::tibble())
  }

  pick <- function(station, field) {
    v <- station[[field]]
    if (is.null(v)) NA else v
  }

  purrr::map(result, function(s) {
    tibble::tibble(
      number              = pick(s, "number"),
      name                = pick(s, "name"),
      category            = pick(s, "category"),
      federalState        = pick(s, "federalState"),
      regionalbereich     = list(s$regionalbereich),
      mailingAddress      = list(s$mailingAddress),
      evaNumbers          = list(s$evaNumbers),
      ril100Identifiers   = list(s$ril100Identifiers),
      hasParking          = pick(s, "hasParking"),
      hasBicycleParking   = pick(s, "hasBicycleParking"),
      hasLocalPublicTransport = pick(s, "hasLocalPublicTransport"),
      hasPublicFacilities = pick(s, "hasPublicFacilities"),
      hasLockerSystem     = pick(s, "hasLockerSystem"),
      hasTaxiRank         = pick(s, "hasTaxiRank"),
      hasTravelNecessities = pick(s, "hasTravelNecessities"),
      hasSteplessAccess   = pick(s, "hasSteplessAccess"),
      hasMobilityService  = pick(s, "hasMobilityService"),
      hasWiFi             = pick(s, "hasWiFi"),
      hasTravelCenter     = pick(s, "hasTravelCenter"),
      hasRailwayMission   = pick(s, "hasRailwayMission"),
      hasDBLounge         = pick(s, "hasDBLounge"),
      hasLostAndFound     = pick(s, "hasLostAndFound"),
      hasCarRental        = pick(s, "hasCarRental")
    )
  }) |>
    purrr::list_rbind()
}

# Convenience: direkt einen Tibble bekommen statt JSON.
stada_stations_df <- function(...) {
  parse_stada_stations(stada_stations(...))
}
