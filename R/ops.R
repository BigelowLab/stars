first_dimensions_match = function(e1, e2) {
	d1 = st_dimensions(e1)
	d2 = st_dimensions(e2)
	crs1 = st_crs(d1)
	crs2 = st_crs(d2)
	st_crs(d1) = st_crs(NA)
	st_crs(d2) = st_crs(NA)
	n = min(length(d1), length(d2))
	isTRUE(all.equal(d1[1:n], d2[1:n], check.attributes = FALSE)) && crs1 == crs2
}

#' S3 Ops Group Generic Functions for stars objects
#'
#' Ops functions for stars objects, including comparison, product and divide, add, subtract
#'
#' @param e1 object of class \code{stars}
#' @param e2 object of class \code{stars}
#'
#' @return object of class \code{stars}
#' @name ops_stars
#' @examples
#' tif = system.file("tif/L7_ETMs.tif", package = "stars")
#' x = read_stars(tif)
#' x * x
#' x / x
#' x + x
#' x + 10
#' all.equal(x * 10, 10 * x)
#' @export
#' @details if \code{e1} or \code{e2} is is a numeric vector, or \code{e2}
#' has less or smaller dimensions than \code{e1}, then \code{e2} is recycled
#' such that it fits \code{e1}, using usual R array recycling rules. The user
#' needs to make sure this is sensible; it may be needed to use \code{aperm}
#' to permutate dimensions first. 
Ops.stars <- function(e1, e2) {
	if (!missing(e2)) { 
		if (inherits(e1, "stars") && inherits(e2, "stars")) {
			if (!first_dimensions_match(e1, e2))
				stop("(first) dimensions of e1 and e2 do not match")
			dim_final = if (prod(dim(e1)) < prod(dim(e2)))
							st_dimensions(e2)
						else
							st_dimensions(e1)
		} else if (inherits(e1, "stars")) {
			dim_final = st_dimensions(e1)
		} else if (inherits(e2, "stars")) {
			dim_final = st_dimensions(e2)
		}
		if (!inherits(e2, c("stars", "units")))
			e1 = drop_units(e1)
	} else
		dim_final = st_dimensions(e1)
	ret = if (missing(e2))
			lapply(e1, .Generic)
		else if (!inherits(e2, "stars"))
			lapply(e1, .Generic, e2 = e2)
		else { # both e1 and e2 are stars objects:
			# https://github.com/r-spatial/stars/issues/187#issuecomment-834020710 :
			if (!is.null(dim(e1)) &&
					!isTRUE(all.equal(dim(e1), dim(e2), check.attributes = FALSE))) {
				stopifnot(length(e2) == 1)
				lapply(lapply(e1, structure, dim=NULL), .Generic, e2 = structure(e2[[1]], dim = NULL))
			} else
				mapply(.Generic, e1, e2, SIMPLIFY = FALSE)
		}
	if (any(sapply(ret, function(x) is.null(dim(x))))) # happens if e1[[1]] is a factor; #304
		ret = lapply(ret, function(x) { dim(x) = dim(dim_final); x })
	if (! inherits(e1, "stars"))
		st_as_stars(setNames(ret, names(e2)), dimensions = dim_final)
	else
		st_as_stars(ret, dimensions = dim_final)
}

#' Mathematical operations for stars objects
#'
#' @param x object of class stars
#' @param ... parameters passed on to the Math functions
#' 
#' @export
#' @name ops_stars
#' 
#' @examples
#' tif = system.file("tif/L7_ETMs.tif", package = "stars")
#' x = read_stars(tif)
#' a = sqrt(x)
#' b = log(x, base = 10)
#' @export
Math.stars = function(x, ...) {
	ret = lapply(x, .Generic, ...)
	st_as_stars(ret, dimensions = st_dimensions(x))
}

#' @name ops_stars
#' @export
Ops.stars_proxy <- function(e1, e2) {
	if (!inherits(e1, "stars_proxy"))
		stop("first argument in expression needs to be the stars_proxy object") # FIXME: needed?? #nocov
	if (missing(e2))
		collect(e1, match.call(), .Generic, "e1", env = environment())
	else
		collect(e1, match.call(), .Generic, c("e1", "e2"), env = environment())
}

#' @name ops_stars
#' @export
Math.stars_proxy = function(x, ...) {
	collect(x, match.call(), .Generic, env = environment())
}

# https://github.com/r-spatial/stars/issues/390
has_single_arg = function(fun, dots) {
	sum(!(names(as.list(args(fun))) %in% c("", "...", names(dots)))) <= 1
}
can_single_arg = function(fun) {
	!inherits(try(fun(1:10), silent = TRUE), "try-error")
}


#' @export
st_apply = function(X, MARGIN, FUN, ...) UseMethod("st_apply")

#' st_apply apply a function to one or more array dimensions
#' 
#' st_apply apply a function to array dimensions: aggregate over space, time, or something else
#' @name st_apply
#' @param X object of class \code{stars}
#' @param MARGIN see \link[base]{apply}; index number(s) or name(s) of the dimensions over which \code{FUN} will be applied 
#' @param FUN see \link[base]{apply} and see Details.
#' @param ... arguments passed on to \code{FUN}
#' @param CLUSTER cluster to use for parallel apply; see \link[parallel]{makeCluster}
#' @param PROGRESS logical; if \code{TRUE}, use \code{pbapply::pbapply} to show progress bar
#' @param FUTURE logical;if \code{TRUE}, use \code{future.apply::future_apply} 
#' @param rename logical; if \code{TRUE} and \code{X} has only one attribute and 
#' \code{FUN} is a simple function name, rename the attribute of the returned object 
#' to the function name
#' @param .fname function name for the new attribute name (if one or more 
#' dimensions are reduced) or the new dimension (if a new dimension is created); 
#' if missing, the name of \code{FUN} is used
#' @param single_arg logical; if \code{TRUE}, FUN takes a single argument (like \code{fn_ndvi1} below), 
#' if \code{FALSE} FUN takes multiple arguments (like \code{fn_ndvi2} below).
#' @return object of class \code{stars} with accordingly reduced number of dimensions; 
#' in case \code{FUN} returns more than one value, a new dimension is created carrying 
#' the name of the function used; see the examples. Following the logic of 
#' \link[base]{apply}, This new dimension is put before the
#' other dimensions; use \link{aperm} to rearrange this, see last example.
#' @param keep logical; if \code{TRUE}, preserve dimension metadata (e.g. time stamps)
#' @details FUN is a function which either operates on a single object, which will 
#' be the data of each iteration step over dimensions MARGIN, or a function that 
#' has as many arguments as there are elements in such an object. See the NDVI 
#' examples below. The second form can be VERY much faster e.g. when a trivial 
#' function is not being called for every pixel, but only once (example).
#' 
#' The heuristics for the default of \code{single_arg} work often, but not always; try
#' setting this to the right value when \code{st_apply} gives an error.
#' @examples
#' tif = system.file("tif/L7_ETMs.tif", package = "stars")
#' x = read_stars(tif)
#' st_apply(x, 1:2, mean) # mean band value for each pixel
#' st_apply(x, c("x", "y"), mean) # equivalent to the above
#' st_apply(x, 3, mean)   # mean of all pixels for each band
#' \dontrun{
#'  st_apply(x, "band", mean) # equivalent to the above
#'  st_apply(x, 1:2, range) # min and max band value for each pixel
#'  fn_ndvi1 = function(x) (x[4]-x[3])/(x[4]+x[3]) # ONE argument: will be called for each pixel
#'  fn_ndvi2 = function(red,nir) (nir-red)/(nir+red) # n arguments: will be called only once
#'  ndvi1 = st_apply(x, 1:2, fn_ndvi1)
#'    # note that we can select bands 3 and 4 in the first argument:
#'  ndvi2 = st_apply(x[,,,3:4], 1:2, fn_ndvi2) 
#'  all.equal(ndvi1, ndvi2)
#'  # compute the (spatial) variance of each band; https://github.com/r-spatial/stars/issues/430
#'  st_apply(x, 3, function(x) var(as.vector(x))) # as.vector is required!
#'  # to get a progress bar also in non-interactive mode, specify:
#'  if (require(pbapply)) { # install it, if FALSE
#'    pboptions(type = "timer")
#'  }
#'  st_apply(x, 1:2, range) # dimension "range" is first; rearrange by:
#'  st_apply(x, 1:2, range) %>% aperm(c(2,3,1))
#' }
#' @export
st_apply.stars = function(X, MARGIN, FUN, ..., CLUSTER = NULL, PROGRESS = FALSE, FUTURE = FALSE, 
		rename = TRUE, .fname, single_arg = has_single_arg(FUN, list(...)) || can_single_arg(FUN),
		keep = FALSE) {
	if (missing(.fname))
		.fname <- paste(deparse(substitute(FUN), 50), collapse = "\n")
	if (is.character(MARGIN))
		MARGIN = match(MARGIN, names(dim(X)))
	dX = dim(X)[MARGIN]

	if (PROGRESS && !requireNamespace("pbapply", quietly = TRUE))
		stop("package pbapply required, please install it first")
	
	if (FUTURE && !requireNamespace("future.apply", quietly = TRUE))
	  stop("package future.apply required, please install it first")

	fn = function(y, ...) {
		ret = if (PROGRESS)
				pbapply::pbapply(X = y, MARGIN = MARGIN, FUN = FUN, ..., cl = CLUSTER)
			else {
				if (is.null(CLUSTER) && !FUTURE)
					apply(X = y, MARGIN = MARGIN, FUN = FUN, ...)
				else if (FUTURE) {
					oopts = options(future.globals.maxSize = +Inf)
					on.exit(options(oopts))
					future.apply::future_apply(y, MARGIN = MARGIN, FUN = FUN, ...)
				} else
					parallel::parApply(CLUSTER, X = y, MARGIN = MARGIN, FUN = FUN, ...)
			}
		if (is.array(ret))
			ret
		else
			array(ret, dX)
	}
	no_margin = setdiff(seq_along(dim(X)), MARGIN)
	ret = if (single_arg) 
			lapply(X, fn, ...) 
		else # call FUN on full chunks:
			lapply(X, function(a) do.call(FUN, setNames(append(asplit(a, no_margin), list(...)), NULL)))
	# fix dimensions:
	dim_ret = dim(ret[[1]])
	ret = if (length(dim_ret) == length(MARGIN)) { # FUN returned a single value
			if (length(ret) == 1 && rename && make.names(.fname) == .fname)
				ret = setNames(ret, .fname)
			st_stars(ret, st_dimensions(X)[MARGIN])
		} else { # FUN returned multiple values: need to set dimension name & values
			dim_no_margin = dim(X)[-MARGIN]
			if (length(no_margin) > 1 && dim(ret[[1]])[1] == prod(dim_no_margin)) {
				r = attr(st_dimensions(X), "raster")
				new_dim = c(dim_no_margin, dim(ret[[1]])[-1])
				for (i in seq_along(ret))
					dim(ret[[i]]) = new_dim
				# set dims:
				dims = st_dimensions(X)[c(no_margin, MARGIN)]
			} else {
				orig = st_dimensions(X)[MARGIN]
				r = attr(orig, "raster")
				dims = if (keep) {
						c(st_dimensions(X)[no_margin], orig)
					} else {
						dim1 = if (!is.null(dimnames(ret[[1]])[[1]])) # FUN returned named vector:
								create_dimension(values = dimnames(ret[[1]])[[1]])
							else
								create_dimension(to = dim_ret[1])
						c(structure(list(dim1), names = .fname), orig)
					}
			}
			st_stars(ret, dimensions = create_dimensions(dims, r))
		}
	for (i in seq_along(ret))
		names(dim(ret[[i]])) = names(st_dimensions(ret))
	ret
}

if (!isGeneric("%in%"))
	setGeneric("%in%", function(x, table) standardGeneric("%in%"))

#' evaluate whether cube values are in a given set
#'
#' evaluate whether cube values are in a given set
#' @docType methods
#' @rdname in-methods
#' @param x data cube value
#' @param table values of the set
#' @exportMethod "%in%"
setMethod("%in%", signature(x = "stars"),
	function(x, table) {
		st_stars(lapply(x, function(y) structure(y %in% table, dim = dim(y))),
			st_dimensions(x))
	}
)
