is_outlier_min <- function(x, m=1.5) quantile(x, 0.25) - m * IQR(x)

is_outlier_max <- function(x, m=1.5) quantile(x, 0.75) + m * IQR(x)

is_outlier <- function(x, m=1.5) {
  (x < is_outlier_min(x, m)) | (x > is_outlier_max(x, m))
}

show_url <- Vectorize(function(path, name=basename(path), hostname=params$hostname, port=params$port) {
  browser()
  str_glue('<a href="http://{hostname}:{port}/{URLencode(path)}">{name}</a>')
}, vectorize.args=c("path", "name"))

read_task_result <- function(path) {
  read_fst(path) %>% as_tibble() %>% mutate(package=basename(package))
}

read_parallel_log <- function(path) {
  read_fst(path) %>% 
    as_tibble() %>% 
    rename_all(tolower) %>%
    mutate(
      package=map_chr(command, ~basename(str_split(., " ")[[1]][2])),
      starttime=as_datetime(starttime),
      endtime=as_datetime(starttime + jobruntime),
      runtime=endtime-starttime,
      run_path=map_chr(command, ~dirname(str_split(., " ")[[1]][3]))
    ) %>%
    select(package, exitval, starttime, endtime, runtime, command, run_path)
}

## "%||%" <- function(a, b) {
##   if (!is.null(a)) a else b
## }

## geom_flat_violin <- function(mapping = NULL, data = NULL, stat = "ydensity",
##                              position = "dodge", trim = TRUE, scale = "area",
##                              show.legend = NA, inherit.aes = TRUE, ...) {
##   layer(
##     data = data,
##     mapping = mapping,
##     stat = stat,
##     geom = GeomFlatViolin,
##     position = position,
##     show.legend = show.legend,
##     inherit.aes = inherit.aes,
##     params = list(
##       trim = trim,
##       scale = scale,
##       ...
##     )
##   )
## }

## GeomFlatViolin <-
##   ggproto("GeomFlatViolin", Geom,
##           setup_data = function(data, params) {
##             data$width <- data$width %||%
##               params$width %||% (resolution(data$x, FALSE) * 0.9)
            
##             # ymin, ymax, xmin, and xmax define the bounding rectangle for each group
##             data %>%
##               group_by(group) %>%
##               mutate(ymin = min(y),
##                      ymax = max(y),
##                      xmin = x,
##                      xmax = x + width / 2
##               )
##           },
  
##   draw_group = function(data, panel_scales, coord) {
##     # Find the points for the line to go all the way around
##     data <- transform(data, xminv = x,
##                       xmaxv = x + violinwidth * (xmax - x))
    
##     # Make sure it's sorted properly to draw the outline
##     newdata <- rbind(plyr::arrange(transform(data, x = xminv), y),
##                      plyr::arrange(transform(data, x = xmaxv), -y))
    
##     # Close the polygon: set first and last point the same
##     # Needed for coord_polar and such
##     newdata <- rbind(newdata, newdata[1,])
    
##     ggplot2:::ggname("geom_flat_violin", GeomPolygon$draw_panel(newdata, panel_scales, coord))
##   },
  
##   draw_key = draw_key_polygon,
  
##   default_aes = aes(weight = 1, colour = "grey20", fill = "white", size = 0.5,
##                     alpha = NA, linetype = "solid"),
  
##   required_aes = c("x", "y")
## )
