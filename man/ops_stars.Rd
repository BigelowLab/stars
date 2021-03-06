% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/ops.R
\name{ops_stars}
\alias{ops_stars}
\alias{Ops.stars}
\alias{Math.stars}
\alias{Ops.stars_proxy}
\alias{Math.stars_proxy}
\title{S3 Ops Group Generic Functions for stars objects}
\usage{
\method{Ops}{stars}(e1, e2)

\method{Math}{stars}(x, ...)

\method{Ops}{stars_proxy}(e1, e2)

\method{Math}{stars_proxy}(x, ...)
}
\arguments{
\item{e1}{object of class \code{stars}}

\item{e2}{object of class \code{stars}}

\item{x}{object of class stars}

\item{...}{parameters passed on to the Math functions}
}
\value{
object of class \code{stars}
}
\description{
Ops functions for stars objects, including comparison, product and divide, add, subtract
}
\examples{
tif = system.file("tif/L7_ETMs.tif", package = "stars")
x = read_stars(tif)
x * x
x / x
x + x
x + 10
all.equal(x * 10, 10 * x)
tif = system.file("tif/L7_ETMs.tif", package = "stars")
x = read_stars(tif)
a = sqrt(x)
b = log(x, base = 10)
}
