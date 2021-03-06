
#' crossv_k
#' 
#' @param data the training data
#' @param y the response vector
#' @param k Number of folds (an integer).
#' @param id a character id
#' @param exclude optional vector indicating rows to exclude.
crossv_k <- function(data, y, k = 5, id = ".id", exclude=NULL) {
  if (!is.numeric(k) || length(k) != 1) {
    stop("`k` must be a single integer.", call. = FALSE)
  }
  
  ## TODO handle exclude argument
  
  n <- nrow(data)
  folds <- sample(rep(1:k, length.out = n))
  
  idx <- seq_len(n)
  fold_idx <- split(idx, folds)
  
  fold <- function(test) {
    tidx <- setdiff(idx, test)
    list(
      ytrain = y[tidx],
      ytest = y[test],
      train = resample(data, setdiff(idx, test)),
      test = resample(data, test)
    )
  }
  
  cols <- purrr::transpose(purrr::map(fold_idx, fold))
  cols[[id]] <- modelr:::id(k)
  
  tibble::as_data_frame(cols)
}



crossv_twofold <- function(data, y, block_var, block_ind, id = ".id", nreps=15, exclude=NULL) {
  if (!length(block_var) == length(y)) {
    stop("length of `block_var` must be equal to length(y)", call. = FALSE)
  }
  
  if (!is.null(exclude)) {
    block_ind <- block_ind[!(block_ind %in% exclude)]
  }
  
  nhalf <- floor(length(block_ind)/2)
  assert_that(nhalf > 0)
  
  fold_sets <- combn(block_ind, nhalf)
  nreps <- min(nreps, ncol(fold_sets))
  cols <- sample(1:ncol(fold_sets), nreps)
  
  fold_idx <- lapply(1:nreps, function(i) {
    bind <- fold_sets[, cols[i]]
    which(block_var %in% bind)
  })
  
  idx <- seq_len(nrow(data))
  
  fold <- function(test) {
    tidx <- setdiff(idx, test)
    list(
      ytrain = y[tidx],
      ytest = y[test],
      train = modelr::resample(data, tidx),
      test = modelr::resample(data, test)
    )
  }
  
  cols <- purrr::transpose(purrr::map(fold_idx, fold))
  cols[[id]] <- modelr:::id(length(fold_idx))
  
  tibble::as_data_frame(cols)
  
  
}


#' crossv_block
#' 
#' @importFrom modelr resample
crossv_block <- function(data, y, block_var, id = ".id", exclude=NULL) {
 
  if (!length(block_var) == length(y)) {
    stop("length of `block_var` must be equal to length(y)", call. = FALSE)
  }
  
  if (!is.null(exclude)) {
    idx <- seq_len(nrow(data))
    keep <- block_var != exclude
    idx <- idx[keep]
    fold_idx <- split(idx, block_var[keep])
  } else {
    idx <- seq_len(nrow(data))
    fold_idx <- split(idx, block_var)
  }
  
  
  fold <- function(test) {
    tidx <- setdiff(idx, test)
    list(
      ytrain = y[tidx],
      ytest = y[test],
      train = modelr::resample(data, tidx),
      test = modelr::resample(data, test)
    )
  }
  
  cols <- purrr::transpose(purrr::map(fold_idx, fold))
  cols[[id]] <- modelr:::id(length(fold_idx))
  
  tibble::as_data_frame(cols)
}



 
#' construct a cross-validation specification using a predefined blocking variable
#' 
#' @param block_var an integer vector of indicating the cross-validation blocks. Each block is indicating by a unique integer.
#' @param exclude exclude an optional vector indicating rows to exclude. 
#' @rdname cross_validation
#' @export
blocked_cross_validation <- function(block_var, exclude=NULL) {
  ret <- list(block_var=block_var, nfolds=length(unique(block_var)), block_ind=sort(unique(block_var)), exclude=exclude)
  class(ret) <- c("blocked_cross_validation", "cross_validation", "list")
  ret
}


#' @export 
#' @inheritParams blocked_cross_validation
#' @rdname cross_validation
twofold_blocked_cross_validation <- function(block_var, nreps=10, exclude=NULL) {
  block_var <- as.integer(block_var)
  ret <- list(block_var=block_var, nfolds=2, nreps=nreps, block_ind=sort(unique(block_var)), exclude=exclude)
  class(ret) <- c("twofold_blocked_cross_validation", "cross_validation", "list")
  ret
}

#' construct a cross-validation specification that randomly partitions input set into \code{nfolds} folds.
#' 
#' @param len the number of observations.
#' @param nfolds the number of cross-validation folds.
#' @param exclude an optional vector indicating rows to exclude.
#' @rdname cross_validation
#' @export
kfold_cross_validation <- function(len, nfolds=10, exclude=NULL) {
  block_var <- sample(rep(seq(1, nfolds), length.out=len))
  ret <- list(block_var=block_var, nfolds=nfolds, exclude=exclude)
  class(ret) <- c("kfold_cross_validation", "cross_validation", "list")
  ret
}


nest <- function(cval) {
  clist <- lapply(cval$block_ind, function(i) {
    blocked_cross_validation(cval$block_var, exclude=i)
  })
  
  class(clist) = c("nested_blocked_cross_validation", "list")
  clist
}

#' crossval_samples
#' 
#' @param obj the cross-validation control object
#' @param data the data to split up
#' @param y the response variable
#' @export
crossval_samples <- function(obj, data, y) { UseMethod("crossval_samples") }

## todo need to implement local version which stores 'y' variable in data.frame (train, test, y_train, y_test)
#' @export
crossval_samples.kfold_cross_validation <- function(obj, data,y) { 
  crossv_k(data, y, obj$nfolds, exclude=obj$exclude)
}

#' @export
crossval_samples.blocked_cross_validation <- function(obj, data, y) { 
  crossv_block(data, y, obj$block_var, exclude=obj$exclude)
}

#' @export
crossval_samples.twofold_blocked_cross_validation <- function(obj, data, y) { 
  crossv_twofold(data, y, obj$block_var, obj$block_ind,exclude=obj$exclude)
}


#' @export
print.blocked_cross_validation <- function(x) {
  cat("cross-validation: blocked \n")
  cat("  nobservations: ", length(x$block_var))
  cat("  nfolds: ", x$nfolds, "\n")
  cat("  block sizes: ", table(x$block_var))
}


#' @export
print.twofold_cross_validation <- function(x) {
  cat("cross-validation: repeated two-fold \n")
  cat("  nobservations: ", length(x$block_var))
  cat("  nfolds: ", 2, "\n")
  cat("  nreps: ", x$nreps, "\n")
}


#' @export
print.kfold_cross_validation <- function(x) {
  cat("cross-validation: k fold \n")
  cat("  nobservations: ", length(x$block_var), "\n")
  cat("  nfolds: ", x$nfolds, "\n")
}
