library(shiny)
library(tools)
## Teste release 3
## Teste 3
ui <- fluidPage(
  h3("Upload de foto -> salva em www/uploads"),
  fileInput("foto", "Selecione uma imagem - (formato png/jpg)", accept = c("image/png","image/jpeg")),
  textOutput("msg"),
  tags$hr(),
  uiOutput("preview")
)

server <- function(input, output, session){

  uploads_dir <- file.path("www", "uploads")
  if (!dir.exists(uploads_dir)) dir.create(uploads_dir, recursive = TRUE)

  saved_path <- reactiveVal(NULL)

  observeEvent(input$foto, {
    req(input$foto)
    ext <- tolower(file_ext(input$foto$name))
    validate(need(ext %in% c("png","jpg","jpeg"), "Apenas PNG/JPG/JPEG."))

    # nome seguro e único
    stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    safe_name <- paste0("foto_", stamp, ".", ifelse(ext=="jpeg","jpg",ext))

    dest <- file.path(uploads_dir, safe_name)
    file.copy(input$foto$datapath, dest, overwrite = FALSE)

    saved_path(dest)
  })

  output$msg <- renderText({
    if (is.null(saved_path())) "Nenhuma foto salva ainda."
    else paste("Salvo em:", saved_path())
  })

  output$preview <- renderUI({
    req(saved_path())
    # caminho relativo ao www para servir no browser
    rel <- sub("^www/", "", saved_path())
    tagList(
      h4("Preview"),
      tags$img(src = rel, style = "max-width: 600px; border: 1px solid #ccc;")
    )
  })
}

shinyApp(ui, server)
