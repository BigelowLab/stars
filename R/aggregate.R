#' spatially or temporally aggregate stars object
#' 
#' spatially or temporally aggregate stars object, returning a data cube with lower spatial or temporal resolution
#' 
#' @param x object of class \code{stars} with information to be aggregated
#' @param by object of class \code{sf} or \code{sfc} for spatial aggregation, for temporal aggregation a vector with time values (\code{Date}, \code{POSIXct}, or \code{PCICt}) that is interpreted as a sequence of left-closed, right-open time intervals or a string like "months", "5 days" or the like (see \link{cut.POSIXt}), or a function that cuts time into intervals; if by is an object of class \code{stars}, it is converted to sfc by \code{st_as_sfc(by, as_points = FALSE)} thus ignoring its time component. Note: each pixel is assigned to only a single group (in the order the groups occur) so non-overlapping spatial features and temporal windows are recommended.
#' @param FUN aggregation function, such as \code{mean}
#' @param ... arguments passed on to \code{FUN}, such as \code{na.rm=TRUE}
#' @param drop logical; ignored
#' @param join function; function used to find matches of \code{x} to \code{by}
#' @param rightmost.closed see \link{findInterval}
#' @param left.open logical; used for time intervals, see \link{findInterval} and \link{cut.POSIXt}
#' @param as_points see \link[stars]{st_as_sf}: shall raster pixels be taken as points, or small square polygons?
#' @param exact logical; if \code{TRUE}, use \link[exactextractr]{coverage_fraction} to compute exact overlap fractions of polygons with raster cells
#' @seealso \link[sf]{aggregate}, \link[sf]{st_interpolate_aw}, \link{st_extract}, https://github.com/r-spatial/stars/issues/317
#' @export
#' @aliases aggregate
#' @examples
#' # aggregate time dimension in format Date
#' tif = system.file("tif/L7_ETMs.tif", package = "stars")
#' t1 = as.Date("2018-07-31")
#' x = read_stars(c(tif, tif, tif, tif), along = list(time = c(t1, t1+1, t1+2, t1+3)))[,1:30,1:30]
#' st_get_dimension_values(x, "time")
#' x_agg_time = aggregate(x, by = t1 + c(0, 2, 4), FUN = max) 
#'
#' # aggregate time dimension in format Date - interval
#' by_t = "2 days"
#' x_agg_time2 = aggregate(x, by = by_t, FUN = max) 
#' st_get_dimension_values(x_agg_time2, "time")
#' #TBD:
#' #x_agg_time - x_agg_time2
#'
#' # aggregate time dimension in format POSIXct
#' x = st_set_dimensions(x, 4, values = as.POSIXct(c("2018-07-31", 
#'                                                   "2018-08-01", 
#'                                                   "2018-08-02", 
#'                                                   "2018-08-03")), 
#'                       names = "time")
#' by_t = as.POSIXct(c("2018-07-31", "2018-08-02"))
#' x_agg_posix = aggregate(x, by = by_t, FUN = max)
#' st_get_dimension_values(x_agg_posix, "time")
#' #TBD:
#' # x_agg_time - x_agg_posix
#' aggregate(x, "2 days", mean)
#' if (require(ncmeta, quietly = TRUE)) {
#'  # Spatial aggregation, see https://github.com/r-spatial/stars/issues/299
#'  prec_file = system.file("nc/test_stageiv_xyt.nc", package = "stars")
#'  prec = read_ncdf(prec_file, curvilinear = c("lon", "lat"))
#'  prec_slice = dplyr::slice(prec, index = 17, along = "time")
#'  nc = sf::read_sf(system.file("gpkg/nc.gpkg", package = "sf"), "nc.gpkg")
#'  nc = st_transform(nc, st_crs(prec_slice))
#'  agg = aggregate(prec_slice, st_geometry(nc), mean)
#'  plot(agg)
#' }
#'
#' # example of using a function for "by": aggregate by month-of-year
#' d = c(10, 10, 150)
#' a = array(rnorm(prod(d)), d) # pure noise
#' times = Sys.Date() + seq(1, 2000, length.out = d[3])
#' m = as.numeric(format(times, "%m"))
#' signal = rep(sin(m / 12 * pi), each = prod(d[1:2])) # yearly period
#' s = (st_as_stars(a) + signal) %>%
#'       st_set_dimensions(3, values = times)
#' f = function(x, format = "%B") {
#' 	  months = format(as.Date(paste0("01-", 1:12, "-1970")), format)
#' 	  factor(format(x, format), levels = months)
#' }
#' agg = aggregate(s, f, mean)
#' plot(agg)
aggregate.stars = function(x, by, FUN, ..., drop = FALSE, join = st_intersects, 
		as_points = any(st_dimension(by) == 2, na.rm = TRUE), rightmost.closed = FALSE,
		left.open = FALSE, exact = FALSE) {

	fn_name = substr(deparse1(substitute(FUN)), 1, 20)
	classes = c("sf", "sfc", "POSIXct", "Date", "PCICt", "character", "function", "stars")
	if (!is.function(by) && !inherits(by, classes))
		stop(paste("currently, only `by' arguments of class", 
			paste(classes, collapse= ", "), "supported"))
	if (inherits(by, "stars"))
		by = st_as_sfc(by, as_points = FALSE) # and if not, then use st_normalize(by)

	if (inherits(by, "sf")) {
		geom = attr(by, "sf_column")
		by = st_geometry(by)
	} else
		geom = "geometry"
	stopifnot(!missing(FUN), is.function(FUN))

	if (exact && inherits(by, c("sfc_POLYGON", "sfc_MULTIPOLYGON")) && has_raster(x)) {
    	if (!requireNamespace("raster", quietly = TRUE))
        	stop("package raster required, please install it first") # nocov
    	if (!requireNamespace("exactextractr", quietly = TRUE))
        	stop("package exactextractr required, please install it first") # nocov
		x = st_upfront(x)
		d = st_dimensions(x)[1:2]
		r = st_as_stars(list(a = array(1, dim = dim(d))), dimensions = d)
		e = exactextractr::coverage_fraction(as(r, "Raster"), by)
		st = do.call(raster::stack, e)
		m = raster::getValues(st)
		if (!identical(FUN, sum)) { # see https://github.com/r-spatial/stars/issues/289
			if (isTRUE(as.character(as.list(FUN)[[3]])[2] == "mean"))
				m = sweep(m, 2, colSums(m), "/") # mean: divide weights by the sum of weights
			else
				stop("for exact=TRUE, FUN should either be mean or sum")
		}
		new_dim = c(prod(dim(x)[1:2]), prod(dim(x)[-(1:2)]))
		out_dim = c(ncol(m), dim(x)[-(1:2)])
		if (isTRUE(list(...)$na.rm))
			x = st_as_stars(lapply(x, function(y) { y[is.na(y)] = 0.0; y }), dimensions = st_dimensions(x))
		agg = lapply(x, function(a) array(t(m) %*% array(a, dim = new_dim), dim = out_dim))
		# %*% dropped units, so to propagate units, if present we need to copy (mean/sum):
		d = create_dimensions(append(setNames(list(create_dimension(values = by)), geom),
			st_dimensions(x)[-(1:2)]))
		for (i in seq_along(x)) {
			if (inherits(x[[i]], "units")) 
				agg[[i]] = units::set_units(agg[[i]], units(x[[i]]), mode = "standard")
			names(dim(agg[[i]])) = names(d)
		}
		return(st_as_stars(agg, dimensions = d))
	}

	drop_y = FALSE
	grps = if (inherits(by, c("sf", "sfc"))) {
			x = if (has_raster(x)) {
					ndims = 2
					drop_y = TRUE
					st_upfront(x)
				} else if (has_sfc(x)) {
					ndims = 1
					st_upfront(x, which_sfc(x))
				}
	
			# find groups:
			# don't use unlist(join(x_geoms, by)) as this would miss the empty groups, 
			#      and may have multiple if geometries in by overlap, hence:
			if (identical(join, st_intersects) && has_raster(x))
				sapply(join(x, by, as_points = as_points),
					function(x) if (length(x)) x[1] else NA)
			else {
				x_geoms = if (has_raster(x))
						st_as_sfc(x, as_points = as_points)
					else
						st_dimensions(x)[[ which_sfc(x) ]]$values
				sapply(join(x_geoms, by), function(x) if (length(x)) x[1] else NA)
			}
		} else { # time: by is POSIXct/Date or character
			ndims = 1
			x = st_upfront(x, which_time(x))
			values = expand_dimensions(x)[[1]]
			if (is.function(by)) {
				i = by(values)
				if (!is.factor(i))
					i = as.factor(i)
				by = levels(i)
			} else if (inherits(by, "character")) {
				i = cut(values, by, right = left.open)
				by = if (inherits(values, "Date"))
						as.Date(levels(i))
					else
						as.POSIXct(levels(i))
			} else {
				if (!inherits(values, class(by)))
					warning(paste0('argument "by" is of a different class (', class(by)[1], 
						') than the time values (', class(values)[1], ')'))
				i = findInterval(values, by, left.open = left.open, rightmost.closed = rightmost.closed)
				i[ i == 0 | i == length(by) ] = NA
			}
			as.integer(i)
		}

	d = st_dimensions(x)
	dims = dim(d)

	agr_grps = function(x, grps, uq, FUN, bind, ...) { 
		do.call(bind, lapply(uq, function(i) {
				sel <- which(grps == i)
				if (!isTRUE(any(sel)))
					NA_real_
				else
					apply(x[sel, , drop = FALSE], 2, FUN, ...)
			}
		))
	}

	bind = if (length(FUN(1:10, ...)) > 1)
			cbind
		else
			rbind
	# rearrange:
	x = structure(x, dimensions = NULL, class = NULL) # unclass
	newdims = c(prod(dims[1:ndims]), prod(dims[-(1:ndims)]))
	for (i in seq_along(x)) {
		a = array(x[[i]], newdims)
		u = if (inherits(x[[i]], "units") && dim(a)[2] > 0) {
				a = units::set_units(a, units(x[[i]]), mode = "standard")
				try(out <- FUN(a[,1], ...))
				if (inherits(out, "units"))
					units(out)
				else
					NULL
			} else
				NULL
		x[[i]] = agr_grps(a, grps, seq_along(by), FUN, bind, ...)
		if (is.numeric(x[[i]]) && !is.null(u))
			x[[i]] = units::set_units(x[[i]], u, mode = "standard")
	}

	# reconstruct dimensions table:
	d[[1]] = create_dimension(values = by)
	names(d)[1] = if (is.function(by) || inherits(by, c("POSIXct", "Date", "PCICt", "function")))
			"time"
		else
			geom
	if (drop_y)
		d = d[-2] # y
	
	# suppose FUN resulted in more than one value?
	if ((r <- prod(dim(x[[1]])) / prod(dim(d))) > 1) {
		if (r %% 1 != 0)
			stop("unexpected array size: does FUN return a consistent number of values?")
		a = attributes(d)
		values = if (is.null(rn <- rownames(x[[1]])))
				seq_len(r)
			else
				rn[1:r]
		d = append(d, list(create_dimension(values = values)))
		n = length(d)
		names(d)[n] = fn_name
		d = d[c(n, 1:(n-1))]
		attr(d, "raster") = a$raster
		attr(d, "class") = a$class
		newdim = setNames(c(r, length(by), dims[-(1:ndims)]), names(d))
	} else
		newdim = setNames(c(length(by), dims[-(1:ndims)]), names(d))

	st_stars(lapply(x, structure, dim = newdim), dimensions = d)
}

	# aggregate is done over one or more dimensions
	# say we have dimensions 1,...,k and we want to aggregate over i,...,j
	# with 1 <= i <= j <= k; 
	# let |n| = j-1+1 be the number of dimensions to aggregate over, n
	# let |m| = k - n be the number of remaining dimensions, m
	# permute the cube such that the n dimensions are followed by the m
	# rearrange the cube to a 2D matrix with |i| x ... x |j| rows, and remaining cols
	# find the grouping of the rows
	# (rearrange such that groups are together)
	# for each sub matrix, belonging to a group, do
	#   apply FUN to every column
	#   assing the resulting row to the group
	# now we have |g| rows, with |g| the number of groups
	# assign each group to the target group of "by"
	# redimension the matrix such that unaffected dimensions match again

#' @export
aggregate.stars_proxy = function(x, by, FUN, ...) {
	if (!inherits(by, c("sf", "sfc", "sfg", "stars")))
		collect(x, match.call(), "aggregate", c("x", "by", "FUN"), env = environment(), ...)
	else {
		if (inherits(by, "stars"))
			by = st_as_sfc(by, as_points = FALSE)
		by = st_geometry(by)

		# this assumes each result of a [ selection is small enough to hold in memory
		l = lapply(seq_along(by), 
		   	function(i) {
			   	sel_i = st_normalize(st_as_stars(x[by[i]]))
			   	aggregate(sel_i, by[i], FUN, ...)
		   	}
		)
		do.call(c, c(l, along = list(which_sfc(l[[1]]))))
	}
}
