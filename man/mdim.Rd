% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/mdim.R
\name{mdim}
\alias{mdim}
\alias{read_mdim}
\alias{write_mdim}
\title{Read or write data using GDAL's multidimensional array API}
\usage{
read_mdim(
  filename,
  variable = character(0),
  ...,
  options = character(0),
  raster = NULL,
  offset = integer(0),
  count = integer(0),
  step = integer(0),
  proxy = FALSE,
  debug = FALSE,
  bounds = TRUE,
  curvilinear = NA,
  normalize_path = TRUE
)

write_mdim(
  x,
  filename,
  driver = detect.driver(filename),
  ...,
  root_group_options = character(0),
  options = character(0),
  as_float = TRUE,
  normalize_path = TRUE
)
}
\arguments{
\item{filename}{name of the source or destination file or data source}

\item{variable}{name of the array to be read; if `"?"`, a list of array names is returned, with group name as list element names.}

\item{...}{ignored}

\item{options}{character; driver specific options regarding the opening (read_mdim) or creation (write_mdim) of the dataset}

\item{raster}{names of the raster variables (default: first two dimensions)}

\item{offset}{integer; zero-based offset for each dimension (pixels) of sub-array to read, defaults to 0 for each dimension(requires sf >= 1.0-9)}

\item{count}{integer; size for each dimension (pixels) of sub-array to read (default: read all); a value of NA will read the corresponding dimension entirely; counts are relative to the step size (requires sf >= 1.0-9)}

\item{step}{integer; step size for each dimension (pixels) of sub-array to read; defaults to 1 for each dimension (requires sf >= 1.0-9)}

\item{proxy}{logical; return proxy object?}

\item{debug}{logical; print debug info?}

\item{bounds}{logical or character: if \code{TRUE} tries to infer from "bounds" attribute; if character, 
named vector of the form \code{c(longitude="lon_bnds", latitude="lat_bnds")} with names dimension names}

\item{curvilinear}{control reading curvilinear (geolocation) coordinate arrays; if \code{NA} try reading the x/y dimension names; if character, defines the arrays to read; if \code{FALSE} do not try; see also \link{read_stars}}

\item{normalize_path}{logical; if \code{FALSE}, suppress a call to \link{normalizePath} on \code{filename}}

\item{x}{stars object}

\item{driver}{character; driver name}

\item{root_group_options}{character; driver specific options regarding the creation of the root group}

\item{as_float}{logical; if \code{TRUE} write 4-byte floating point numbers, if \code{FALSE} write 8-byte doubles}
}
\description{
Read or write data using GDAL's multidimensional array API
}
\details{
it is assumed that the first two dimensions are easting and northing
}
\examples{
set.seed(135)
m = matrix(runif(10), 2, 5)
names(dim(m)) = c("stations", "time")
times = as.Date("2022-05-01") + 1:5
pts = st_as_sfc(c("POINT(0 1)", "POINT(3 5)"))
s = st_as_stars(list(Precipitation = m)) |>
 st_set_dimensions(1, values = pts) |>
 st_set_dimensions(2, values = times)
nc = tempfile(fileext=".nc")
if (compareVersion(sf_extSoftVersion()["GDAL"], "3.4.0") > -1) {
  write_mdim(s, nc)
  # try ncdump on the generated file
  print(read_mdim(nc))
}
}
\seealso{
\link[sf]{gdal_utils}, in particular util \code{mdiminfo} to query properties of a file or data source containing arrays
}
