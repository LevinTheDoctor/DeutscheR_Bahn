library(shiny)
library(DT)

# .Renviron sicherheitshalber laden, falls App nicht via Rproj gestartet wurde
if (file.exists(".Renviron")) readRenviron(".Renviron")

source("R/Timetabels.R")
source("R/StaDa.R")

# Display-Helfer: list-columns aus StaDa flach machen, damit DT sie anzeigt
flatten_stada_for_display <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(df)

  pull_field <- function(lst, field) {
    if (length(lst) == 0) return(NA_character_)
    vals <- vapply(lst, function(o) {
      v <- o[[field]]
      if (is.null(v)) NA_character_ else as.character(v)
    }, character(1))
    paste(stats::na.omit(vals), collapse = " | ")
  }

  df$eva_codes <- vapply(df$evaNumbers, pull_field, character(1),
                         field = "number")
  df$ril100    <- vapply(df$ril100Identifiers, pull_field, character(1),
                         field = "rilIdentifier")
  df$city      <- vapply(df$mailingAddress, function(a) {
    if (is.null(a) || is.null(a$city)) NA_character_
    else as.character(a$city)
  }, character(1))

  # Nested raus für Anzeige
  df$evaNumbers <- NULL
  df$ril100Identifiers <- NULL
  df$regionalbereich <- NULL
  df$mailingAddress <- NULL

  # Sinnvolle Spaltenreihenfolge
  primary <- c("name", "eva_codes", "ril100", "city",
               "category", "federalState", "number")
  primary <- intersect(primary, names(df))
  rest <- setdiff(names(df), primary)
  df[, c(primary, rest)]
}

bundeslaender <- c(
  "Alle" = "",
  "Baden-Württemberg" = "baden-württemberg",
  "Bayern" = "bayern",
  "Berlin" = "berlin",
  "Brandenburg" = "brandenburg",
  "Bremen" = "bremen",
  "Hamburg" = "hamburg",
  "Hessen" = "hessen",
  "Mecklenburg-Vorpommern" = "mecklenburg-vorpommern",
  "Niedersachsen" = "niedersachsen",
  "Nordrhein-Westfalen" = "nordrhein-westfalen",
  "Rheinland-Pfalz" = "rheinland-pfalz",
  "Saarland" = "saarland",
  "Sachsen" = "sachsen",
  "Sachsen-Anhalt" = "sachsen-anhalt",
  "Schleswig-Holstein" = "schleswig-holstein",
  "Thüringen" = "thüringen"
)

ui <- fluidPage(
  titlePanel("Deutsche Bahn"),

  tabsetPanel(
    id = "tabs",

    tabPanel(
      "Station suchen (StaDa)",
      sidebarLayout(
        sidebarPanel(
          width = 3,
          textInput("stada_search", "Suche (searchstring)",
                    value = "Frankfurt*"),
          helpText(
            tags$b("Wildcards:"), code("*"), "(beliebig viele Zeichen),",
            code("?"), "(genau ein Zeichen).",
            tags$br(),
            "Listen mit Komma:", code("hamburg*,berlin*"),
            tags$br(),
            "Umlaute werden automatisch umgewandelt (ä→ae)."
          ),
          hr(),
          selectInput("stada_federalstate", "Bundesland",
                      choices = bundeslaender, selected = ""),
          textInput("stada_category", "Kategorie (1–7)",
                    value = "", placeholder = "z.B. 1,2 oder 1-3"),
          numericInput("stada_limit", "Max. Treffer (limit)",
                       value = 100, min = 1, max = 10000, step = 50),
          actionButton("search_stada", "Suchen",
                       class = "btn-primary", width = "100%")
        ),
        mainPanel(
          width = 9,
          verbatimTextOutput("stada_info", placeholder = TRUE),
          DT::DTOutput("stada_table")
        )
      )
    ),

    tabPanel(
      "Fahrplan (plan)",
      sidebarLayout(
        sidebarPanel(
          width = 3,
          textInput("plan_eva", "EVA-Nr.", value = "8000105"),
          dateInput("plan_date", "Datum", value = Sys.Date()),
          numericInput("plan_hour", "Stunde (0–23)",
                       value = as.integer(format(Sys.time(), "%H")),
                       min = 0, max = 23, step = 1),
          actionButton("fetch_plan", "Plan abrufen",
                       class = "btn-primary", width = "100%"),
          hr(),
          selectInput("plan_category", "Nur Zugtyp",
                      choices = c("Alle" = ""),
                      selected = "")
        ),
        mainPanel(
          width = 9,
          DT::DTOutput("plan_table")
        )
      )
    ),

    tabPanel(
      "Änderungen (fchg/rchg)",
      sidebarLayout(
        sidebarPanel(
          width = 3,
          textInput("chg_eva", "EVA-Nr.", value = "8000105"),
          radioButtons("chg_type", "Typ",
                       choices = c(
                         "Alle bekannten (fchg)" = "fchg",
                         "Letzte ~2 Min (rchg)"  = "rchg"
                       )),
          actionButton("fetch_chg", "Änderungen abrufen",
                       class = "btn-primary", width = "100%"),
          hr(),
          checkboxInput("only_delays",
                        "Nur Einträge mit geänderter Zeit", FALSE),
          checkboxInput("show_delay_col",
                        "Verspätungs-Spalte berechnen", TRUE)
        ),
        mainPanel(
          width = 9,
          DT::DTOutput("chg_table")
        )
      )
    )
  )
)

server <- function(input, output, session) {

  safe_request <- function(expr) {
    tryCatch(
      expr,
      error = function(e) {
        showNotification(
          paste("Fehler:", conditionMessage(e)),
          type = "error", duration = 10
        )
        NULL
      }
    )
  }

  # --- Tab 1: StaDa Station suchen ---
  stada_data <- eventReactive(input$search_stada, {
    req(nchar(input$stada_search) > 0)

    args <- list(searchstring = input$stada_search)
    if (nzchar(input$stada_federalstate)) {
      args$federalstate <- input$stada_federalstate
    }
    if (nzchar(input$stada_category)) {
      args$category <- input$stada_category
    }
    if (!is.na(input$stada_limit) && input$stada_limit > 0) {
      args$limit <- input$stada_limit
    }

    safe_request({
      json <- do.call(stada_stations, args)
      list(
        total = json$total,
        df    = parse_stada_stations(json)
      )
    })
  })

  output$stada_info <- renderText({
    res <- stada_data()
    req(res)
    total <- if (is.null(res$total)) "?" else as.character(res$total)
    sprintf("Gefunden: %s | Angezeigt: %d", total, nrow(res$df))
  })

  output$stada_table <- DT::renderDT({
    res <- stada_data()
    req(res)
    df <- flatten_stada_for_display(res$df)
    DT::datatable(
      df,
      filter = "top",
      options = list(pageLength = 25, scrollX = TRUE),
      rownames = FALSE
    )
  })

  # --- Tab 2: Fahrplan ---
  plan_data <- eventReactive(input$fetch_plan, {
    date_str <- format(input$plan_date, "%y%m%d")
    hour_str <- sprintf("%02d", as.integer(input$plan_hour))
    safe_request(plan_Request(input$plan_eva, date_str, hour_str))
  })

  observeEvent(plan_data(), {
    df <- plan_data()
    req(df)
    cats <- sort(unique(stats::na.omit(df$trip_category)))
    updateSelectInput(session, "plan_category",
                      choices = c("Alle" = "", cats),
                      selected = "")
  })

  output$plan_table <- DT::renderDT({
    df <- plan_data()
    req(df)
    if (nzchar(input$plan_category)) {
      df <- df[!is.na(df$trip_category) &
                 df$trip_category == input$plan_category, ]
    }
    DT::datatable(
      df,
      filter = "top",
      options = list(pageLength = 25, scrollX = TRUE),
      rownames = FALSE
    )
  })

  # --- Tab 3: Änderungen ---
  chg_data <- eventReactive(input$fetch_chg, {
    req(nchar(input$chg_eva) > 0)
    fn <- if (input$chg_type == "fchg") fchg_Request else rchg_Request
    safe_request(fn(input$chg_eva))
  })

  output$chg_table <- DT::renderDT({
    df <- chg_data()
    req(df)

    if (isTRUE(input$only_delays)) {
      df <- df[!is.na(df$ar_changed_time) | !is.na(df$dp_changed_time), ]
    }

    if (isTRUE(input$show_delay_col)) {
      df$ar_delay_min <- as.numeric(
        difftime(df$ar_changed_time, df$ar_planned_time, units = "mins")
      )
      df$dp_delay_min <- as.numeric(
        difftime(df$dp_changed_time, df$dp_planned_time, units = "mins")
      )
    }

    DT::datatable(
      df,
      filter = "top",
      options = list(pageLength = 25, scrollX = TRUE),
      rownames = FALSE
    )
  })
}

shinyApp(ui = ui, server = server)
