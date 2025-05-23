# close rings by repeating the first point
close_mat = function(m) {
	if (any(m[1,] != m[nrow(m),]))
		m = rbind(m, m[1,])
	if (nrow(m) < 4)
		stop("polygons require at least 4 points")
	unclass(m)
}

regrp = function(grp, i) {
	# work on single MULTIPOLYGON, group outer rings or outer rings+holes
	if (all(i == 0)) # only outer rings
		lapply(grp, function(x) list(close_mat(x))) # add one list level
	else {
		for (j in seq_along(grp))
			grp[[j]] = close_mat(grp[[j]])
		starts = which(i == 0)
		lst = vector("list", length(starts))
		for (j in seq_along(lst)) {
			end = start = starts[j]
			while (end < length(i) && i[end + 1] == 1)
				end = end + 1 # consume holes from start to end
			lst[j] = list(grp[start:end])
		}
		lst
	}
}

regroup = function(grps, ir) {
	mapply(regrp, grps, ir, SIMPLIFY = FALSE)
}

recreate_geometry = function(l) {
	if (length(geom <- l$geometry)) {
		cc = cbind(geom$x[[1]], geom$y[[1]])
		if (geom$geometry_type == "point") {
			sfc = do.call(st_sfc, lapply(seq_len(nrow(cc)), function(i) st_point(cc[i,])))
			dimension = attr(geom$x[[1]], "d_names")
		} else { 
			nc = geom$node_count[[1]]
			pnc = c(0, cumsum(geom$part_node_count[[1]]))
			parts = vector("list", length(geom$part_node_count[[1]]))
			for (i in seq_along(parts))
				parts[[i]] = cc[(pnc[i]+1):pnc[i+1],]
			i = findInterval(pnc[-1], cumsum(c(0, nc)), left.open = TRUE)
			grps = lapply(split(seq_along(parts), i), function(x) parts[x])
			dimension = attr(nc, "d_names")
			if (geom$geometry_type == "line")
				sfc = do.call(st_sfc, lapply(grps, st_multilinestring))
			else if (geom$geometry_type == "polygon") {
				ir = geom$interior_ring[[1]]
				grps = regroup(grps, split(ir, i))
				sfc = do.call(st_sfc, lapply(grps, st_multipolygon))
					# if all rings are exterior rings: add one list level to each
					# do.call(st_sfc, lapply(lapply(grps, function(x) lapply(x, list)), st_multipolygon))
			} else
				stop(paste("unsupported geometry type:", geom$geometry_type))
		}
		l$dimensions[[dimension]] = sfc
	}
	l
}

get_values_from_bounds = function(x, bnd, center) {
	a = gdal_read_mdim(x, bnd)$array_list[[1]]
	dim(a) = rev(dim(a))
	a = t(a)
	if (length(dim(a)) == 2) {
		if (!dim(a)[2] %in% 1:2)
			warning(paste("bounds variable", bnd, "has", dim(a)[2], "vertices and may be treated incorrectly"))
		if (center) {
			m = apply(a, 1, mean)
			if (regular_intervals(m))
				m
			else
				make_intervals(a[,1], a[,2])
		} else # start of bound:
			a[,1]
	} else
		a
}

mdim_use_bounds = function(dims, x, bnds, center = TRUE) {
	if (isTRUE(bnds)) {
		bnds = character()
		for (d in names(dims))
			if (d != "time" && !is.null(b <- attr(dims[[d]]$values[[1]], "attributes")["bounds"]))
				bnds = c(bnds, setNames(b, d))
	}
	if (length(bnds) && is.null(names(bnds)))
		stop("bounds must be a named vector, names indicating the non-bounds dimension variables")
	for (b in names(bnds))
		if (!is.na(bnds[b])) {
			v <- try(get_values_from_bounds(x, bnds[b], center = TRUE), silent = TRUE)
			if (!inherits(v, "try-error"))
				dims[[b]]$values[[1]] = v
		}
	dims
}

match_raster_dims = function(nms) {
	x = tolower(nms) %in% c("lon", "long", "longitude")
	y = tolower(nms) %in% c("lat", "latitude")
	if (sum(xor(x, y)) == 2)
		c(which(x), which(y))
	else
		1:2
}


#' Read or write data using GDAL's multidimensional array API
#'
#' Read or write data using GDAL's multidimensional array API
#' @name mdim
#' @param filename name of the source or destination file or data source
#' @param variable name of the array to be read; if `"?"`, a list of array names is returned, with group name as list element names.
#' @param options character; driver specific options regarding the opening (read_mdim) or creation (write_mdim) of the dataset
#' @param raster names of the raster variables (default: first two dimensions)
#' @param offset integer; zero-based offset for each dimension (pixels) of sub-array to read, defaults to 0 for each dimension(requires sf >= 1.0-9)
#' @param count integer; size for each dimension (pixels) of sub-array to read (default: read all); a value of NA will read the corresponding dimension entirely; counts are relative to the step size (requires sf >= 1.0-9)
#' @param step integer; step size for each dimension (pixels) of sub-array to read; defaults to 1 for each dimension (requires sf >= 1.0-9)
#' @param proxy logical; return proxy object?
#' @param debug logical; print debug info?
#' @param bounds logical or character: if \code{TRUE} tries to infer from "bounds" attribute; if character, 
#' named vector of the form \code{c(longitude="lon_bnds", latitude="lat_bnds")} with names dimension names
#' @param curvilinear control reading curvilinear (geolocation) coordinate arrays; if \code{NA} try reading the x/y dimension names; if character, defines the arrays to read; if \code{FALSE} do not try; see also \link{read_stars}
#' @param normalize_path logical; if \code{FALSE}, suppress a call to \link{normalizePath} on \code{filename}
#' @details it is assumed that the first two dimensions are easting and northing
#' @param ... ignored
#' @seealso \link[sf]{gdal_utils}, in particular util \code{mdiminfo} to query properties of a file or data source containing arrays
#' @export
read_mdim = function(filename, variable = character(0), ..., options = character(0), 
					 raster = NULL, offset = integer(0), count = integer(0), step = integer(0), proxy = FALSE, 
					 debug = FALSE, bounds = TRUE, curvilinear = NA, normalize_path = TRUE) {

	stopifnot(is.character(filename), is.character(variable), is.character(options))
	if (normalize_path)
		filename = enc2utf8char(maybe_normalizePath(filename, np = normalize_path))
	ret = gdal_read_mdim(filename, variable, options, rev(offset), rev(count), rev(step), proxy, debug)

	if (identical(variable, "?"))
		return(ret) # RETURNS

	if (length(ret$dimensions) == 1 && length(ret$array_list) == 1 && is.data.frame(ret$array_list[[1]]))
		return(ret$array_list[[1]]) ## composite data: RETURNS

	ret = recreate_geometry(ret)
	if (isTRUE(bounds) || is.character(bounds))
		ret$dimensions = mdim_use_bounds(ret$dimensions, filename, bounds)

	create_units = function(x) {
		u = attr(x, "units")
		x = structure(x, units = NULL) # remove attribute
		if (is.null(u) || u %in% c("", "none"))
			x
		else {
			if (!is.null(a <- attr(x, "attributes")) && !is.na(cal <- a["calendar"]) && 
						cal %in% c("360_day", "365_day", "noleap"))
				get_pcict(x, u, cal)
			else {
				days_since = grepl("days since", u)
				u = try_as_units(u)
				if (!inherits(u, "units")) # FAIL:
					x
				else {
					units(x) = u
					if (days_since && inherits(d <- try(as.Date(x), silent = TRUE), "Date")) 
						d
					else if (inherits(p <- try(as.POSIXct(x), silent = TRUE), "POSIXct"))
						p
					else
						x
				}
			}
		}
	}
	l = rev(lapply(ret$dimensions, function(x) {
			   if (inherits(x, "sfc")) x else create_units(x$values[[1]])
			}))
	if (length(offset) != 0 || length(step) != 0 || length(count) != 0) {
		if (length(offset) == 0)
			offset = rep(0, length(l))
		if (length(step) == 0)
			step = rep(1, length(l))
		ll = lengths(lapply(l, as.list)) # take care of dimensions of class intervals
		if (length(count) == 0)
			count = floor((ll - offset)/step)
		else if (any(a <- is.na(count)))
			count[a] = floor((ll[a] - offset[a])/step[a])
		for (i in seq_along(l)) {
			l[[i]] = l[[i]][seq(from = offset[i]+1, length.out = count[i], by = step[i])]
		}
	}

	# create dimensions table:
	sf = any(sapply(l, function(x) inherits(x, "sfc")))
	# FIXME: i %in% 1:2 always the case?
	raster_dims = match_raster_dims(names(l))
	d = mapply(function(x, i) create_dimension(values = x, is_raster = !sf && i %in% raster_dims,
									   point = ifelse(length(x) == 1, TRUE, NA)),
			   l, seq_along(l), SIMPLIFY = FALSE)
	if (is.null(raster)) {
		raster = if (sf)
					get_raster(dimensions = rep(NA_character_,2))
				else
					get_raster(dimensions = names(d)[raster_dims])
	} else
		raster = get_raster(dimensions = raster)
	dimensions = create_dimensions(d, raster = raster)

	# handle array units:
	for (i in seq_along(ret$array_list))
		if (nchar(u <- attr(ret$array_list[[i]], "units")) && inherits(u <- try_as_units(u), "units"))
			units(ret$array_list[[i]]) = u
	clean_units = function(x) { 
		if (identical(attr(x, "units"), "")) 
			structure(x, units = NULL)
		else
			x
	}

	# create return object:
	if (proxy) {
		lst = lapply(ret$array_list, function(x) filename)
		st = st_stars_proxy(lst, dimensions, NA_value = NA_real_, resolutions = NULL, class = "mdim")
		if (!is.null(ret$srs))
			st_set_crs(st, ret$srs)
		else
			st
	} else { 
		lst = lapply(ret$array_list, function(x) structure(clean_units(x), dim = rev(dim(x))))
		st = st_stars(lst, dimensions)
		if (is.null(ret$srs) || is.na(ret$srs)) {
			if (missing(curvilinear) || is.character(curvilinear)) { # try curvilinear:
				xy = raster$dimensions
				ll = curvilinear
				if (is.character(curvilinear)) {
					if (is.null(names(curvilinear)))
						names(curvilinear) = xy[1:2]
					ret = try(st_as_stars(st, curvilinear = curvilinear), silent = TRUE)
					if (inherits(ret, "stars"))
						st = ret
				}
				if (!is_curvilinear(st) &&
					inherits(x <- try(read_mdim(filename, ll[1], curvilinear = FALSE), silent = TRUE), "stars") &&
					inherits(y <- try(read_mdim(filename, ll[2], curvilinear = FALSE), silent = TRUE), "stars") &&
						identical(dim(x)[xy], dim(st)[xy]) && identical(dim(y)[xy], dim(st)[xy]))
					st = st_as_stars(st, curvilinear = setNames(list(x, y), xy))
			}
			st
		} else
			st_set_crs(st, ret$srs)
	}
}

# WRITE helper functions:

add_attr = function(x, at) { # append at to attribute "attrs"
		structure(x, attrs = c(attr(x, "attrs"), at))
}

add_units_attr = function(l) {
		f = function(x) {
			if (inherits(x, "units"))
				add_attr(x, c(units = as.character(units(x))))
			else if (inherits(x, c("POSIXct", "PCICt"))) {
				cal = if (!is.null(cal <- attr(x, "cal")))
					c(calendar = paste0(cal, "_day")) # else NULL, intended
				x = as.numeric(x)
				if (all(x %% 86400 == 0))
					add_attr(x/86400, c(units = "days since 1970-01-01", cal))
				else if (all(x %% 3600 == 0))
					add_attr(x / 3600, c(units = "hours since 1970-01-01 00:00:00", cal))
				else
					add_attr(x, c(units = "seconds since 1970-01-01 00:00:00", cal))
			} else if (inherits(x, "Date"))
				add_attr(as.numeric(x), c(units = "days since 1970-01-01"))
			else
				x
		}
		lapply(l, f)
}

cdl_add_geometry = function(e, i, sfc) {
	stopifnot(inherits(sfc, c("sfc_POINT", "sfc_POLYGON", "sfc_MULTIPOLYGON", "sfc_LINESTRING", "sfc_MULTILINESTRING")))

	if (inherits(sfc, "sfc_POLYGON"))
		sfc = st_cast(sfc, "MULTIPOLYGON")
	if (inherits(sfc, "sfc_LINESTRING"))
		sfc = st_cast(sfc, "MULTILINESTRING")

	cc = st_coordinates(sfc)
	if (inherits(sfc, c("sfc_MULTIPOLYGON"))) {
		e$node = structure(seq_len(nrow(cc)), dim = c(node = nrow(cc)))
		e$x = structure(cc[, 1], dim = c(node = nrow(cc)))
		e$y = structure(cc[, 2], dim = c(node = nrow(cc)))
		e$node_count = structure(rle(cc[,"L3"])$lengths, dim = setNames(length(sfc), names(e)[i]))
		part = rle(cc[,"L3"] * 2 * max(cc[,"L2"]) + 2 * (cc[,"L2"] - 1) + cc[,"L1"])$lengths
		e$part_node_count = structure(part, dim = c(part = length(part)))
		e$interior_ring = structure(as.numeric(cc[cumsum(part), "L1"] > 1), dim = c(part = length(part)))
		attr(e, "dims") = c(node = nrow(cc), part = length(part))
		e$geometry = add_attr(structure(numeric(0), dim = c("somethingNonEx%isting" = 0)),
			c(geometry_type = "polygon", node_count = "node_count", node_coordinates = "x y",
		  	part_node_count = "part_node_count", interior_ring = "interior_ring",
		  	grid_mapping = if (!is.na(st_crs(sfc))) "crs" else NULL))
	} else if (inherits(sfc, "sfc_MULTILINESTRING")) { # LINE:
		e$node = structure(seq_len(nrow(cc)), dim = c(node = nrow(cc)))
		e$x = structure(cc[, 1], dim = c(node = nrow(cc)))
		e$y = structure(cc[, 2], dim = c(node = nrow(cc)))
		e$node_count = structure(rle(cc[,"L2"])$lengths, dim = setNames(length(sfc), names(e)[i]))
		part = rle((cc[,"L2"] - 1) * max(cc[,"L1"]) + cc[,"L1"])$lengths
		e$part_node_count = structure(part, dim = c(part = length(part)))
		attr(e, "dims") = c(node = nrow(cc), part = length(part))
		e$geometry = add_attr(structure(numeric(0), dim = c("somethingNonEx%isting" = 0)),
			c(geometry_type = "line", node_count = "node_count", node_coordinates = "x y",
		  	part_node_count = "part_node_count",
		  	grid_mapping = if (!is.na(st_crs(sfc))) "crs" else NULL))
	} else { # POINT:
		if (ll <- isTRUE(st_is_longlat(sfc))) {
			e$lon = add_attr(structure(cc[, 1], dim = setNames(nrow(cc), names(e)[i])), 
						 	c(units = "degrees_north", standard_name = "longitude"))
			e$lat = add_attr(structure(cc[, 2], dim = setNames(nrow(cc), names(e)[i])), 
						 	c(units = "degrees_east", standard_name = "latitude"))
		} else {
			e$x = structure(cc[, 1], dim = setNames(nrow(cc), names(e)[i]))
			e$y = structure(cc[, 2], dim = setNames(nrow(cc), names(e)[i]))
		}
		e$geometry = add_attr(structure(numeric(0), dim = c("somethingNonEx%isting" = 0)),
				c(geometry_type = "point", node_coordinates = ifelse(ll, "lon lat", "x y"),
				grid_mapping = if (!is.na(st_crs(sfc))) "crs" else NULL))
	}
	e
}

# convert stars object into a list of CDL-like variables with named dimensions
st_as_cdl = function(x) {
	e = add_units_attr(expand_dimensions(x)) # TODO: handle sfc dimensions
	d = st_dimensions(x)
	dimx = dim(x)
	xy = attr(st_dimensions(x), "raster")$dimensions
	co = NULL
	for (i in seq_along(e)) {
		if (is.null(dim(e[[i]])) && !is.list(e[[i]]))
			e[[i]] = structure(e[[i]], dim = setNames(length(e[[i]]), names(e)[i]))
		else if (is_curvilinear(x)) { # curvilinear coordinate matrices:
			if (names(e)[i] == xy[1]) names(e)[i] = "lon"
			if (names(e)[i] == xy[2]) names(e)[i] = "lat"
		} else if (inherits(e[[i]], "sfc")) { # vector data cube:
			sfc = e[[i]]
			e[[i]] = structure(seq_along(sfc), dim = setNames(length(sfc), names(e)[i]))
			e = cdl_add_geometry(e, i, sfc)
			if (inherits(sfc, "sfc_POINT")) {
				if (isTRUE(st_is_longlat(x))) {
					co = c(coordinates = "lat lon")
					xy = c("lon", "lat") # hack
				} else {
					co = c(coordinates = "x y")
					xy = c("x", "y") # hack
				}
			} else {
				dimx = c(dimx, attr(e, "dims"))
				co = c(coordinates = "x y")
				xy = c("x", "y") # hack
			} 
			co = c(co, geometry = "geometry")
		}
	}

	if (is_curvilinear(x)) {
		e[["lat"]] = add_attr(e[["lat"]], c(units = "degrees_north", "_CoordinateAxisType" = "Lat", axis = "Y"))
		e[["lon"]] = add_attr(e[["lon"]], c(units = "degrees_east",  "_CoordinateAxisType" = "Lon", axis = "X"))
		co = paste(rev(setdiff(names(d), c("x", "y", "lat", "lon"))), "lat lon")
	} else {
		if (!any(is.na(xy))) {
			e[[ xy[1] ]] = add_attr(e[[ xy[1] ]], c(axis = "X"))
			e[[ xy[2] ]] = add_attr(e[[ xy[2] ]], c(axis = "Y"))
		}
	}
	for (i in seq_along(x))
		x[[i]] = add_attr(x[[i]], co)

	x = add_units_attr(x) # unclasses x
	for (i in seq_along(x))
		if (is.null(names(dim(x[[i]])))) # FIXME: read_ncdf() doesn't name array dim
			names(dim(x[[i]])) = names(d)

	for (i in names(e)) # copy over dimension values
		x[[i]] = e[[i]]

	which_dims = function(a, dimx) {
		m = match(names(dim(a)), names(dimx), nomatch = numeric(0)) - 1
		if (all(is.na(m)))
			integer(0)
		else
			m
	}
	ret = lapply(x, function(a) structure(a, which_dims = which_dims(a, dimx)))
	structure(ret, which_crs = !(names(ret) %in% names(e)), 
			  is_numeric = sapply(ret, is.numeric),
			  dims = attr(e, "dims"))
}


#' @name mdim
#' @param x stars object 
#' @param driver character; driver name
#' @param root_group_options character; driver specific options regarding the creation of the root group
#' @param as_float logical; if \code{TRUE} write 4-byte floating point numbers, if \code{FALSE} write 8-byte doubles
#' @param ... ignored
#' @export
#' @examples
#' set.seed(135)
#' m = matrix(runif(10), 2, 5)
#' names(dim(m)) = c("stations", "time")
#' times = as.Date("2022-05-01") + 1:5
#' pts = st_as_sfc(c("POINT(0 1)", "POINT(3 5)"))
#' s = st_as_stars(list(Precipitation = m)) |>
#'  st_set_dimensions(1, values = pts) |>
#'  st_set_dimensions(2, values = times)
#' nc = tempfile(fileext=".nc")
#' if (compareVersion(sf_extSoftVersion()["GDAL"], "3.4.0") > -1) {
#'   write_mdim(s, nc)
#'   # try ncdump on the generated file
#'   print(read_mdim(nc))
#' }
write_mdim = function(x, filename, driver = detect.driver(filename), ..., 
					  root_group_options = character(0), options = character(0),
					  as_float = TRUE, normalize_path = TRUE) {

	if (normalize_path)
		filename = enc2utf8(maybe_normalizePath(filename, TRUE))
	if (inherits(x, "stars_proxy"))
		x = st_as_stars(x)
	cdl = st_as_cdl(x)
	wkt = if (is.na(st_crs(x)))
			character(0)
		else
			st_crs(x)$wkt
	xy = attr(st_dimensions(x), "raster")$dimensions
	gdal_write_mdim(filename, driver, c(dim(x), attr(cdl, "dims")), cdl, wkt, xy, 
					root_group_options = root_group_options, options = options,
					as_float = as_float)
	invisible(x)
}

#' @export
st_as_stars.mdim = function(.x, ..., downsample = 0, debug = FALSE,
		envir = parent.frame()) {
	d = st_dimensions(.x)
	if (length(downsample) == 1) { # implies only spatial coordinates
		ds = dim(.x) * 0
		ds[1:2] = downsample
		downsample = ds
	}
	step = rep_len(round(downsample), length(dim(.x))) + 1
	offset = sapply(d, function(x) x$from) - 1
	count = (sapply(d, function(x) x$to) - offset) %/% step
	if (debug)
		print(data.frame(offset = offset, step = step, count = count))
	# read:
	l = vector("list", length(.x))
	for (i in seq_along(l))
		l[[i]] = read_mdim(.x[[i]], names(.x)[i], offset = offset, count = count, step = step, proxy = FALSE, ...)
	ret = do.call(c, l)
	if (!is.na(st_crs(.x)))
		st_crs(ret) = st_crs(.x)
	# post-process:
	cl = attr(.x, "call_list")
	if (!all(downsample == 0))
		lapply(cl, check_xy_warn, dimensions = st_dimensions(.x))
	process_call_list(ret, cl, envir = envir, downsample = downsample)
}

#' @export
`[.mdim` = function(x, i, j, ...) {
	structure(NextMethod(), class = class(x))
}

#' @export
#' @name st_crop
st_crop.mdim = function(x, y, ...) {
	structure(NextMethod(), class = class(x))
}
