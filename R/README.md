# DB_API.R — Nutzung

Wrapper für die [Deutsche Bahn Timetables API](https://developers.deutschebahn.com/db-api-marketplace/apis/product/timetables). Jeder Request gibt einen **Tibble** zurück.

## Setup

### 1. Credentials in `.Renviron`

Im Projekt-Root (gleiche Ebene wie `DeutscheR_Bahn.Rproj`):

```
DB_CLIENT_ID=deine_client_id
DB_CLIENT_SECRET=dein_api_key
```

Kein Leerzeichen um `=`, keine Anführungszeichen. Stelle sicher, dass `.Renviron` in `.gitignore` steht.

### 2. Projekt über `.Rproj` starten

R komplett schließen → Doppelklick auf `DeutscheR_Bahn.Rproj`. RStudio liest die projekt-lokale `.Renviron` automatisch beim Start.

Falls R außerhalb gestartet wurde, manuell laden:
```r
readRenviron(".Renviron")
```

### 3. Funktionen laden

```r
source("R/DB_API.R")
```

Benötigte Pakete: `httr2`, `xml2`, `tibble`, `purrr`, `glue`.

---

## Funktionen

### `station_Request(pattern)`

Sucht Stationen nach Name/Pattern. Liefert u.a. die **EVA-Nummer**, die du für alle anderen Calls brauchst.

| Parameter | Typ      | Beispiel        |
|-----------|----------|-----------------|
| `pattern` | `string` | `"Frankfurt*"`  |

**Pattern-Syntax:** Laut DB-API-Doku akzeptiert das `pattern`-Feld:
- **Stationsname als Prefix** (Default): `"Frankfurt"` → alle Stationen, die mit "Frankfurt" anfangen
- **EVA-Nummer**: `"8000105"` → exakt eine Station
- **DS100/RL100-Code**: `"FF"`
- **Wildcard `*`**: für komplexere Patterns wie `"*Hbf"` oder `"Frankfurt*Süd"`

⚠️ **Bekannte API-Einschränkung:** Umlaute im Prefix funktionieren **nicht**. `"Köln"` liefert kein Ergebnis — stattdessen `"Koeln"` versuchen oder mit `*` arbeiten (`"K*ln"`).

Sonderzeichen (`(`, `)`, Leerzeichen) werden automatisch URL-encoded.

```r
stations <- station_Request("Frankfurt")   # Prefix
stations <- station_Request("*Hbf")        # alle Hauptbahnhöfe
stations <- station_Request("Koeln")       # Workaround für "Köln"
```

**Rückgabe-Spalten:**

| Spalte      | Beschreibung                                       |
|-------------|----------------------------------------------------|
| `name`      | Stationsname                                       |
| `eva`       | EVA-Nummer (für `fchg_/rchg_/plan_Request`)        |
| `ds100`     | DS100-Code (interner DB-Code)                      |
| `platforms` | Gleise, durch `\|` getrennt                        |
| `meta`      | Verbundene Meta-Stationen, durch `\|` getrennt     |

---

### `plan_Request(evaNo, date, hour)`

Geplanter Fahrplan einer Station für ein **Stunden-Zeitfenster**.

| Parameter | Typ      | Format    | Beispiel    |
|-----------|----------|-----------|-------------|
| `evaNo`   | `string` | EVA-Nr.   | `"8000105"` |
| `date`    | `string` | `YYMMDD`  | `"260619"`  |
| `hour`    | `string` | `HH`      | `"08"`      |

**Wichtig:** Alle Parameter müssen Strings sein. `plan_Request(8000105, 260619, 8)` schlägt fehl (`"8"` ≠ `"08"`).

Datum und Stunde werden vor dem Request durch `validate_date_hour()` geprüft — bei ungültiger Eingabe gibt es einen klaren Fehler, **bevor** ein HTTP-Request rausgeht.

```r
plan <- plan_Request("8000105", "260619", "08")
```

---

### `fchg_Request(evaNo)`

**Full changes** — alle bekannten Änderungen/Verspätungen einer Station (kein Datum/Stunde nötig, immer "aktuell").

```r
fchg <- fchg_Request("8000105")
```

---

### `rchg_Request(evaNo)`

**Recent changes** — nur die letzten ~2 Minuten Änderungen. Schneller, kleinerer Response. Gut für Polling.

```r
rchg <- rchg_Request("8000105")
```

---

## Rückgabe-Spalten (plan / fchg / rchg)

Eine **Zeile pro Stop**. Spalten sind in drei Blöcke gruppiert:

### Stop-Identifikation

| Spalte         | Beschreibung                                         |
|----------------|------------------------------------------------------|
| `station`      | Stationsname (aus `<timetable station="...">`)       |
| `station_eva`  | EVA der abgefragten Station                          |
| `stop_id`      | Eindeutige Stop-ID (`{tripId}-{YYMMdd}-{index}`)     |
| `eva`          | EVA des Stops                                        |

### Trip-Label (`<tl>`)

| Spalte           | Beschreibung                                  |
|------------------|-----------------------------------------------|
| `trip_category`  | Zugtyp, z.B. `"ICE"`, `"RE"`, `"S"`           |
| `trip_number`    | Zugnummer, z.B. `"4523"`                      |
| `trip_owner`     | EVU-Kürzel                                    |
| `trip_type`      | `p` planned / `e` / `z` / `s` / `h` / `n`     |
| `trip_filter`    | Filter-Flags                                  |

### Ankunft (`ar_*`) und Abfahrt (`dp_*`)

Beide Blöcke haben dieselben 9 Felder. `ar_*` ist `NA` an Startstationen, `dp_*` ist `NA` an Endstationen.

| Suffix              | Typ       | Beschreibung                                    |
|---------------------|-----------|-------------------------------------------------|
| `_planned_time`     | `POSIXct` | Geplante Zeit (Europe/Berlin)                   |
| `_changed_time`     | `POSIXct` | Geänderte/Ist-Zeit                              |
| `_planned_platform` | `chr`     | Geplantes Gleis                                 |
| `_changed_platform` | `chr`     | Geändertes Gleis                                |
| `_planned_path`     | `chr`     | Geplanter Laufweg, Stationen durch `\|`         |
| `_changed_path`     | `chr`     | Geänderter Laufweg                              |
| `_line`             | `chr`     | Linien-Bezeichner                               |
| `_changed_status`   | `chr`     | `p` planned / `a` added / `c` cancelled         |
| `_planned_status`   | `chr`     | `p` / `a` / `c`                                 |

**Zeit-Konvertierung:** Das DB-Format `"YYMMddHHmm"` wird automatisch zu `POSIXct` in Europe/Berlin. Du kannst direkt damit rechnen.

---

## Typische Workflows

### EVA-Nummer finden, dann Fahrplan abrufen

```r
station_Request("Unna")
# eva = 8000107

plan_Request("8000107", "260619", "08")
```

### Verspätungen berechnen

```r
library(dplyr)

fchg_Request("8000105") |>
  filter(!is.na(ar_changed_time)) |>
  mutate(
    delay_min = as.numeric(
      difftime(ar_changed_time, ar_planned_time, units = "mins")
    )
  ) |>
  select(trip_category, trip_number,
         ar_planned_time, ar_changed_time, delay_min) |>
  arrange(desc(delay_min))
```

### Plan + Änderungen kombinieren

```r
library(dplyr)

plan <- plan_Request("8000105", "260619", "08")
fchg <- fchg_Request("8000105")

combined <- plan |>
  left_join(
    fchg |> select(stop_id,
                   ar_changed_time, dp_changed_time,
                   ar_changed_platform, dp_changed_platform),
    by = "stop_id",
    suffix = c("", "_upd")
  )
```

### Nur ICE-Abfahrten

```r
library(dplyr)

plan_Request("8000105", "260619", "08") |>
  filter(trip_category == "ICE", !is.na(dp_planned_time)) |>
  select(trip_number, dp_planned_time, dp_planned_platform, dp_planned_path)
```

---

## Fehler-Diagnose

| Fehler                                        | Ursache                                                          |
|-----------------------------------------------|------------------------------------------------------------------|
| `HTTP 401 Unauthorized`                       | `.Renviron` nicht geladen oder Key nicht für Timetables-API frei |
| `Datum muss im Format YYMMDD sein`            | Datum war kein 6-stelliger String                                |
| `Stunde muss zwischen 00 und 23 liegen`       | Stunde außerhalb gültigem Bereich                                |
| `could not find function "station_Request"`   | `source("R/DB_API.R")` vergessen                                 |
| Empty Tibble                                  | Station hat in dem Zeitfenster keine Fahrten — kein Fehler       |

Bei 401 zur Diagnose Raw-Response holen:
```r
library(httr2)
request("https://apis.deutschebahn.com/db-api-marketplace/apis/timetables/v1/station/Unna") |>
  req_headers(
    "DB-Client-ID" = Sys.getenv("DB_CLIENT_ID"),
    "DB-Api-Key"   = Sys.getenv("DB_CLIENT_SECRET")
  ) |>
  req_error(is_error = \(r) FALSE) |>
  req_perform() |>
  resp_body_string()
```
