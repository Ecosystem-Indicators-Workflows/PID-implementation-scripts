## Create or update an unpublished Zenodo Draft Deposit from output-best-candidate/
##
## Purpose:
## > Reads metadata from output-best-candidate/.zenodo.json, creates (or updates)
## > a draft deposit on Zenodo Sandbox or Production Zenodo via the REST API,
## > pre-reserves a DOI, and uploads the dataset files from output-best-candidate/.
## > Does NOT publish the deposit automatically, allowing visual inspection and
## > embargo/metadata verification in the Zenodo web interface before publishing.
##
## Prerequisites:
## > 1. Create a Zenodo Personal Access Token with the `deposit:write` scope at:
## >    - Sandbox:    https://sandbox.zenodo.org/account/settings/applications/tokens/new/
## >    - Production: https://zenodo.org/account/settings/applications/tokens/new/
## > 2. Add the token to your ~/.Renviron file (never commit tokens to Git):
## >    ZENODO_SANDBOX_TOKEN="your_sandbox_token"
## >    ZENODO_TOKEN="your_production_token"
##
## Recommended usage:
## > Sandbox test (default):
##   Rscript inc/zenodo-upload-draft.R
## > Production Zenodo draft:
##   ZENODO_ENV=production Rscript inc/zenodo-upload-draft.R
## > Update an existing draft deposit (replace files & metadata in-place):
##   ZENODO_DEPOSIT_ID=1234567 Rscript inc/zenodo-upload-draft.R

library(httr2)
library(jsonlite)

readRenviron("~/.Renviron")
out_dir <- getwd()

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
      "Missing API token: environment variable `%s` is not set.\nAdd `%s=\"...\"` to ~/.Renviron and restart R.",
      token_var,
      token_var
    ),
    call. = FALSE
  )
}

cat(sprintf("Target environment: %s (%s)\n", toupper(zenodo_env), base_url))

## 2. Read and validate .zenodo.json metadata
zenodo_json_path <- file.path(out_dir, ".zenodo.json")
if (!file.exists(zenodo_json_path)) {
  stop("Metadata file not found: ", zenodo_json_path, call. = FALSE)
}

meta <- fromJSON(zenodo_json_path, simplifyVector = FALSE)
meta$prereserve_doi <- TRUE

## Clean fields that Zenodo's /api/deposit/depositions endpoint rejects:
## 1) `scheme` inside `related_identifiers` is auto-detected by Zenodo and causes
##    HTTP 400 ("Unknown field") if sent explicitly to /api/deposit/depositions.
if (!is.null(meta$related_identifiers)) {
  meta$related_identifiers <- lapply(meta$related_identifiers, function(x) {
    x$scheme <- NULL
    x
  })
}

## 2) On Zenodo Sandbox, production community slugs (e.g. "iucn-rle") do not exist
##    and cause HTTP 400 ("Provided community does not exist").
if (use_sandbox && !is.null(meta$communities)) {
  cat(
    "Note: Omitting `communities` when uploading to SANDBOX",
    "(production communities do not exist on sandbox.zenodo.org).\n"
  )
  meta$communities <- NULL
}

## Helper to display Zenodo's detailed field-level validation errors on HTTP 400
zenodo_error_body <- function(resp) {
  err <- tryCatch(resp_body_json(resp), error = function(e) NULL)
  if (is.null(err)) {
    return(resp_body_string(resp))
  }
  msgs <- c(sprintf("Zenodo API message: %s", err$message %||% "HTTP error"))
  if (!is.null(err$errors)) {
    for (e in err$errors) {
      field_name <- e$field %||% "unknown_field"
      field_msgs <- paste(unlist(e$messages), collapse = "; ")
      msgs <- c(msgs, sprintf("  • %s: %s", field_name, field_msgs))
    }
  }
  msgs
}

if (identical(meta$access_right, "embargoed") && is.null(meta$embargo_date)) {
  stop(
    "`access_right` is set to 'embargoed' in .zenodo.json, but `embargo_date` (YYYY-MM-DD) is missing.",
    call. = FALSE
  )
}
if (
  identical(meta$access_right, "restricted") && is.null(meta$access_conditions)
) {
  stop(
    "`access_right` is set to 'restricted' in .zenodo.json, but `access_conditions` is missing.",
    call. = FALSE
  )
}

## 3. Create a new draft deposit or update an existing draft
deposit_id <- Sys.getenv("ZENODO_DEPOSIT_ID", unset = "")

if (!nzchar(deposit_id)) {
  cat("Creating empty draft deposit...\n")
  dep_init <- request(paste0(base_url, "/deposit/depositions")) |>
    req_auth_bearer_token(token) |>
    req_body_raw("{}", type = "application/json") |>
    req_error(body = zenodo_error_body) |>
    req_perform() |>
    resp_body_json()
  deposit_id <- as.character(dep_init$id)
  cat(sprintf("Created draft deposit ID: %s\n", deposit_id))
}

cat(sprintf(
  "Applying metadata from .zenodo.json to deposit ID: %s...\n",
  deposit_id
))
dep <- request(sprintf("%s/deposit/depositions/%s", base_url, deposit_id)) |>
  req_method("PUT") |>
  req_auth_bearer_token(token) |>
  req_body_json(list(metadata = meta), auto_unbox = TRUE) |>
  req_error(body = zenodo_error_body) |>
  req_perform() |>
  resp_body_json()

bucket_url <- dep$links$bucket
deposit_id <- dep$id
reserved_doi <- dep$metadata$prereserve_doi$doi

cat(sprintf("Draft Deposit ID : %s\n", deposit_id))
cat(sprintf("Pre-reserved DOI : %s\n", reserved_doi))
cat(sprintf("Access right     : %s\n", meta$access_right))
if (!is.null(meta$embargo_date)) {
  cat(sprintf("Embargo date     : %s\n", meta$embargo_date))
}

## 4. Upload dataset and documentation files into the draft bucket
datapkg_meta <- fromJSON(file.path(out_dir, "datapackage.json"))

pkg_files <- datapkg_meta$resources[[2]]

files_to_upload <- c(
  "README.md",
  "README.qmd",
  "LICENSE",
  "datapackage.json",
  pkg_files
)

missing_files <- files_to_upload[
  !file.exists(file.path(out_dir, files_to_upload))
]
if (length(missing_files) > 0) {
  stop(
    "Missing expected files in current folder/: ",
    paste(missing_files, collapse = ", "),
    call. = FALSE
  )
}

for (fname in files_to_upload) {
  fpath <- file.path(out_dir, fname)
  fsize_mb <- file.info(fpath)$size / (1024^2)
  cat(sprintf("Uploading %-34s (%.2f MB)...\n", fname, fsize_mb))

  request(paste0(bucket_url, "/", fname)) |>
    req_method("PUT") |>
    req_auth_bearer_token(token) |>
    req_body_file(fpath) |>
    req_perform()
}

cat("\n✔ All files uploaded to Zenodo draft!\n")
cat(sprintf(
  "Review, verify metadata/embargo settings, and publish at:\n  %s\n",
  dep$links$html
))
cat(sprintf(
  "To update this same draft later without creating a new one, run:\n  ZENODO_DEPOSIT_ID=%s Rscript inc/zenodo-upload-draft.R\n",
  deposit_id
))
