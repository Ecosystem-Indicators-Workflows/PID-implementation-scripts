## Fetch metadata from an existing Zenodo Draft (or Published) Deposit
##
## Purpose:
## > Downloads the metadata of a Zenodo deposit after you have edited it in the
## > browser (e.g. adding grants/funding, communities, contributors, or subjects)
## > so you can inspect the exact JSON structure or update .zenodo.json.
##
## Recommended usage:
## > Fetch a specific deposit ID from Sandbox (default):
##   ZENODO_DEPOSIT_ID=1234567 Rscript inc/zenodo-fetch-metadata.R
## > Fetch the most recently modified draft from Sandbox (if ZENODO_DEPOSIT_ID is omitted):
##   Rscript inc/zenodo-fetch-metadata.R
## > Fetch from Production Zenodo:
##   ZENODO_ENV=production R --vanilla < R/zenodo-fetch-metadata.R --args 24207312

library(httr2)
library(jsonlite)

here::i_am("R/zenodo-fetch-metadata.R")
readRenviron("~/.Renviron")
out_dir <- here::here("metadata-examples")
if (!dir.exists(out_dir)) {
  dir.create(out_dir, recursive = TRUE)
}

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  deposit_id <- Sys.getenv("ZENODO_DEPOSIT_ID", unset = "")
  message(
    "No argument supplied; trying to find deposit_id in the environment variables\n"
  )
} else {
  deposit_id <- args[1]
}


## 1. Environment & authentication setup
zenodo_env <- tolower(Sys.getenv("ZENODO_ENV", unset = "sandbox"))
use_sandbox <- zenodo_env != "production"

base_url <- if (use_sandbox) {
  "https://sandbox.zenodo.org/api"
} else {
  "https://zenodo.org/api"
}

token_var <- if (use_sandbox) "ZENODO_SANDBOX_TOKEN" else "ZENODO_TOKEN"
token <- Sys.getenv(token_var)

if (!nzchar(token)) {
  stop(
    sprintf(
      "Missing API token: environment variable `%s` is not set.\nAdd `%s=\"...\"` to ~/.Renviron.",
      token_var,
      token_var
    ),
    call. = FALSE
  )
}

## 2. If no ZENODO_DEPOSIT_ID is given, find the latest deposit in the account
if (!nzchar(deposit_id)) {
  cat(sprintf(
    "No ZENODO_DEPOSIT_ID specified; querying latest deposit on %s...\n",
    toupper(zenodo_env)
  ))
  deps <- request(paste0(base_url, "/deposit/depositions")) |>
    req_auth_bearer_token(token) |>
    req_perform() |>
    resp_body_json()

  if (length(deps) == 0) {
    stop("No deposits found in this Zenodo account.", call. = FALSE)
  }
  deposit_id <- as.character(deps[[1]]$id)
  cat(sprintf(
    "Found latest deposit ID: %s ('%s')\n",
    deposit_id,
    deps[[1]]$title %||% ""
  ))
}

## 3. Fetch legacy deposit representation (/api/deposit/depositions/{id})
##    Its `$metadata` block matches the `.zenodo.json` schema.
cat(sprintf("Fetching deposit metadata for ID %s...\n", deposit_id))
dep <- request(sprintf("%s/deposit/depositions/%s", base_url, deposit_id)) |>
  req_auth_bearer_token(token) |>
  req_perform() |>
  resp_body_json()

meta_path <- file.path(out_dir, sprintf("zenodo-metadata-%s.json", deposit_id))
write_json(dep$metadata, meta_path, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("✔ Saved .zenodo.json-compatible metadata to:\n  %s\n", meta_path))

## 4. Also fetch the InvenioRDM draft record (/api/records/{id}/draft) if available,
##    which includes any newer Web UI fields (such as custom funding/grants structures).
rdm_draft <- tryCatch(
  request(sprintf("%s/records/%s/draft", base_url, deposit_id)) |>
    req_auth_bearer_token(token) |>
    req_perform() |>
    resp_body_json(),
  error = function(e) NULL
)

if (!is.null(rdm_draft)) {
  rdm_path <- file.path(
    out_dir,
    sprintf("zenodo-inveniordm-draft-%s.json", deposit_id)
  )
  write_json(rdm_draft, rdm_path, auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf(
    "✔ Saved full InvenioRDM draft JSON (including Web UI funding/custom fields) to:\n  %s\n",
    rdm_path
  ))
}
