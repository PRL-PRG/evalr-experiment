suppressPackageStartupMessages(library(rlang))




nb_eval_call_sites <- function(eval_calls)
{
  # Two cases: with srcref, without srcref

  nb_with_srcref <- eval_calls %>% select(eval_call_srcref) %>% n_distinct(na.rm = TRUE)
  nb_without_srcref <- eval_calls %>% filter(is.na(eval_call_srcref)) %>% select(caller_package, caller_function) %>% n_distinct(na.rm = TRUE)

  return(nb_with_srcref + nb_without_srcref)
}


get_expr <- function(eval_call)
{
  if(is.na(eval_call))
  {
    return(NA)
  }
  # Special case for expressions starting with _ (such as _inherit in ggproto)
  escaped_eval_call <- if(startsWith(eval_call, "_"))
  {
    paste0("`", eval_call, "`")
  }
  else
  {
    eval_call
  }

  exp <- NA
  # Would fail for instance for
  # "`$<-`(new(\"C++Field\", .xData = <environment>), \"read_only\", TRUE)" (classInt package)
  # exp <- tryCatch(
  #   parse(text = escaped_eval_call)[[1]],
  #   error = function(e) {return(NA)})
  try(exp <- parse(text = escaped_eval_call)[[1]], silent = TRUE)


  return(exp)
}

function_name <- function(eval_call)
{
  exp <- get_expr(eval_call)
  if(is.call(exp))
  {
    return(paste(deparse(exp[[1]]), collapse = "\n"))
  }
  return(NA)
}


function_arguments <- function(eval_call)
{
  exp <- get_expr(eval_call)
  if(is.call(exp))
  {
    return(map_chr(as.list(exp[-1]), function(chr) { paste(deparse(chr), collapse = "\n")}))
  }
  return(NA)
}


# See extract_inner_exp which takes a str
# This one takes an expression
# We assume that eval_expr_call is a call
extract_inner_exp_aux <- function(eval_expr_call)
{
  args <- as.list(eval_expr_call[-1])
  leaves <- list()
  no_calls <- TRUE
  for(arg in args)
  {
    if(!missing(arg)) # we cannot have the two conditions in the same if
    {
      if(is.call(arg))
      {
        leaves <-  c(leaves, extract_inner_exp_aux(arg))
        no_calls <- FALSE
      }
    }
  }
  if(no_calls)
  {
    return(c(leaves, deparse(eval_expr_call)))
  }
  return(leaves)
}

# Extract the inner calls and arguments
# For instance, in f(g(h(e))), we would get h(e)
# For f(g(e), t), we will get g(e)
extract_inner_exp <- function(eval_call)
{
  #cat(eval_call, "\n")
  exp <- get_expr(eval_call)
  if(is.call(exp))
  {
    return(extract_inner_exp_aux(exp))
  }
  return(NA)
}

constant_leaves_expr <- function(eval_exp_call)
{
  if(is.call(eval_exp_call))
  {
    args <- as.list(eval_exp_call[-1])
    return(every(args, constant_leaves_expr))
  }
  else
  {
    return(!is.language(eval_exp_call))
  }
}



# Test if all the expression in the call graphs are not symbols but constant
# It would imply that there's no need for the eval!
constant_leaves <- function(eval_call)
{
  if(is.na(eval_call))
  {
    return(FALSE)
  }
  exp <- get_expr(eval_call)
  return(constant_leaves_expr(exp))
}

# Check if there is only one expression and that it is a call
check_call <- function(arg)
{
  exp <- parse(text = arg)
  return(length(exp) == 1 & is.call(exp[[1]]))
}


R_LIB_SRC <- "/var/lib/R/project-evalR/R-4.0.2/src/library"
CORE_PACKAGES <- c(
  "compiler",
  "graphics",
  "grDevices",
  "grid",
  "methods",
  "parallel",
  "profile",
  "splines",
  "stats",
  "stats4",
  "tcltk",
  "tools",
  "utils"
)
core_package_files <- map_dfr(CORE_PACKAGES, function(x) {
  p <- file.path(R_LIB_SRC, x, "R")
  f <- list.files(p, pattern="\\.R$", recursive=FALSE)
  f <- f[!str_ends(f, "all\\.R")]
  f <- file.path("./R", f)
  tibble(package=x, file=f)
})



replaceable_functions <- c("+", "*", "/", "-", "%%",
                           "<-", "[[<-", "[<-", "$<-", "<<-", "=",
                           "[", "[[", "$",
                           "@<-",
                           "slot", "@",
                           "&", "&&", "|", "||", "!",
                           "<", ">", "==", "<-", ">=", "!=",
                           "if")


is_replaceable <- function(expr)
{
  # We are going to traverse the ast recursively
  # We cannot replace in 2 cases: the function name in a call is too complex (we could do a do.call though), it is bytecode
  if(is.call(expr))
  {
    function_name <- expr[[1]]
    function_args <- expr[-1]
    return(as.character(function_name) %in% replaceable_functions && every(function_args, is_replaceable))

  }
  else if(is.expression(expr))
  {
    return(every(expr, is_replaceable))
  }
  else if(typeof(expr) == "bytecode")
  {
    return(FALSE)
  }
  else # Symbols, promises, vector types, closure and builtins, S4 objects. There should not be "..." here
  {
    return(TRUE)
  }
}

env_assign <- c("<<-", "assign")

is_assign <- function(expr)
{
  if(is.call(expr))
  {
    function_name <- expr[[1]]
    function_args <- expr[-1]
    return(as.character(function_name) %in% env_assign || some(function_args, is_assign))
  }
  else if(is.expression(expr))
  {
    return(some(expr, is_assign))
  }
  else
  {
    return(FALSE)
  }
}

is_assign_str <- function(expr)
{
  e <- get_expr(expr)
  return(is_assign(e))
}



is_replaceable_str <- function(expr)
{
  e <- get_expr(expr)
  return(is_replaceable(e))
}

expr_depth <- function(expr)
{
  if(is.call(expr))
  {
    return(1L + max(map_int(expr[-1], expr_depth)))
  }
  else if(is.expression(expr))
  {
    return(max(map_int(expr, expr_depth)))
  }
  else
  {
    return(1L)
  }
}

expr_depth_str <- function(expr)
{
  e <- get_expr(expr)
  return(expr_depth(e))
}

expr_size <- function(expr)
{
  if(is.call(expr))
  {
    return(1L + sum(map_int(expr[-1], expr_size)))
  }
  else if(is.expression(expr))
  {
    return(sum(map_int(expr, expr_size)))
  }
  else
  {
    return(1L)
  }
}

expr_size_str <- function(expr)
{
  e <- get_expr(expr)
  return(expr_size(e))
}

groupify_function <- function(expr_function)
{
  case_when(
    str_starts(expr_function, fixed("(function(")) ~ "anonymous",
    str_starts(expr_function, fixed(".Primitive(")) ~ "primitive",
    TRUE ~ expr_function
  )
}

build_env_rep <- function(env_class)
{
  splitted <- str_split(env_class, fixed("+"))[[1]]
  env_cl <- splitted[[length(splitted)]]
  env_cl <- replace_na(str_match(env_cl, "caller-([:digit:]+)")[[2]], env_cl)
  return(paste0(env_cl, if(length(splitted) > 1) "+" else ""))
}

simplify_envir <- function(env_class, envir_type, envir_expression)
{
  # Add a + to the last environment if the first is new
  case_when(
    is.na(env_class) & envir_type == "VECSXP" ~ "list",
    is.na(env_class) & envir_type == "NILSXP" ~ "NULL",
    is.na(env_class) & envir_type == "INTSXP" ~ paste0("sys.call(", envir_expression, ")"),
    TRUE ~ build_env_rep(env_class)
    )
}

extract_write_envir <- function(env_class)
{
  return(str_split(env_class, fixed("+"), n = 2)[[1]][[1]])
}


extract_envir <- function(env_class, envir_type, envir_expression)
{
  # First element is write, second is read
  case_when(
    is.na(env_class) & envir_type == "VECSXP" ~ c("list", "enclos"),
    is.na(env_class) & envir_type == "NILSXP" ~ c("NULL", "enclos"),
    is.na(env_class) & envir_type == "INTSXP" ~ {e <- paste0("sys.call(", envir_expression, ")"); c(e, e)},
    str_ends(env_class, fixed("global")) ~ c(extract_write_envir(env_class), "global"),
    str_ends(env_class, fixed("base")) ~ c(extract_write_envir(env_class), "base"),
    str_ends(env_class, fixed("callee")) ~ c(extract_write_envir(env_class), "callee"),
    str_ends(env_class, fixed("empty")) ~ c(extract_write_envir(env_class), "empty"),
    str_ends(env_class, "caller-.*") ~ c(extract_write_envir(env_class), str_extract(env_class, "caller-[0-9]*")),
    str_ends(env_class, "loop") ~ c("loop", "loop"),
    str_ends(env_class, "package:.*") ~ c(extract_write_envir(env_class), str_extract(env_class, "package:.*"))
  )
}


